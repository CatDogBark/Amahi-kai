require 'json'

# The logs Settings → Help shows and a problem's report quotes, each as its newest lines:
# Amahi-kai's own, the root helper's (root:amahi 0640, so the app reads it), System Update's, the
# system journal and each app's container output (those two through the root helper, which can
# read them).
module HelpLogs
  LINES = 150
  HELPER_LOG = '/var/log/amahi-kai/helper.log'.freeze
  UPDATE_LOG = '/var/log/amahi-kai/update.log'.freeze
  TAIL_BYTES = 512 * 1024 # the end of a file read for its last lines, not the whole of it
  ARGS_MAX = 300 # a helper call's arguments, as shown

  class Unreadable < StandardError; end

  Source = Struct.new(:key, :label, :about, keyword_init: true)

  module_function

  # The logs there are: the app's three files, the journal, and one an installed app.
  def sources(apps = DockerApp.order(:name))
    [
      Source.new(key: 'amahi', label: 'Amahi-kai', about: 'The web app: what was done through these pages, and what went wrong there.'),
      Source.new(key: 'helper', label: 'Root helper',
                 about: 'Every change made as root, each with what it was asked. Passwords and keys are never written here.'),
      Source.new(key: 'update', label: 'System Update', about: 'The last System Update, step by step.'),
      Source.new(key: 'journal', label: 'System journal', about: "The system's own log: services starting, stopping and failing."),
      *apps.map { |app| Source.new(key: "app:#{app.identifier}", label: app.name, about: "#{app.name}'s own output, from its container.") }
    ]
  end

  def source(key, apps = DockerApp.order(:name))
    sources(apps).find { |s| s.key == key }
  end

  # The newest +count+ lines of the log +key+ names, oldest first. Raises Unreadable with why not.
  def lines(key, count = LINES)
    case key
    when 'amahi' then tail(rails_log, count)
    when 'helper' then tail(HELPER_LOG, count).map { |line| helper_line(line) }
    when 'update' then tail(UPDATE_LOG, count)
    when 'journal' then Array(Privileged.call('system.journal', lines: count)['lines'])
    when /\Aapp:([a-z0-9][a-z0-9_-]*)\z/ then app_lines(Regexp.last_match(1), count)
    else raise Unreadable, "there's no log #{key.inspect}"
    end
  rescue Privileged::Error => e
    raise Unreadable, e.message
  end

  # Every log, each under its name, as one text: Download logs, and the end of a report.
  def text(count = LINES, apps = DockerApp.order(:name))
    sources(apps).map do |s|
      body = begin
        lines(s.key, count).join("\n").presence || '(empty)'
      rescue Unreadable => e
        "(couldn't be read: #{e.message})"
      end
      "── #{s.label} ──\n#{body}"
    end.join("\n\n")
  end

  def rails_log
    Rails.root.join('log', "#{Rails.env}.log").to_s
  end

  def app_lines(id, count)
    reply = Privileged.call('apps.logs', app: id, lines: count)
    return ['(no container: install it again)'] if reply['missing']

    Array(reply['lines'])
  end

  # The last +count+ lines of the file at +path+, read from its end. A missing file has none.
  def tail(path, count)
    File.open(path, 'rb') do |file|
      size = file.size
      file.seek([size - TAIL_BYTES, 0].max)
      found = file.read.to_s.force_encoding('UTF-8').scrub('?').lines(chomp: true)
      found.shift if size > TAIL_BYTES # the first line read is cut
      found.last(count)
    end
  rescue Errno::ENOENT
    []
  rescue SystemCallError => e
    raise Unreadable, e.message
  end

  # A root helper log entry (one JSON object a line) as a line to read:
  # "2026-10-29 03:41:06 apps.install app=transmission → failed: setfacl exited 1 (8143 ms)".
  def helper_line(raw)
    entry = JSON.parse(raw)
    return raw unless entry.is_a?(Hash)

    time = entry['time'].to_s.sub('T', ' ').sub(/\.\d+Z\z/, '').sub(/Z\z/, '')
    args = Hash(entry['args']).map { |key, value| "#{key}=#{value.is_a?(String) ? value : JSON.generate(value)}" }.join(' ')
    args = "#{args[0, ARGS_MAX]}…" if args.length > ARGS_MAX
    outcome = entry['error'] ? "→ failed: #{entry['error']}" : '→ ok'
    took = entry['ms'] ? " (#{entry['ms']} ms)" : ''
    [time, entry['op'], args.presence, "#{outcome}#{took}"].compact.join(' ')
  rescue JSON::ParserError, TypeError
    raw
  end
end
