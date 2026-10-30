# A problem's report (Settings → Help → Report a problem): what the red flag said and on which
# page, this server in a few lines (ServerSummary), and the newest lines of the logs most likely to
# show what went wrong, with an app's own when it needs attention. The page takes the names and
# addresses out (ReportScrubber) and the browser sends it (report.js): Amahi-kai sends nothing.
module ProblemReport
  ISSUES_URL = 'https://github.com/CatDogBark/Amahi-kai/issues/new'.freeze
  EMAIL = 'catdogbark@pm.me'.freeze
  # The logs a report quotes, and how many of each one's newest lines.
  LOGS = { 'helper' => 30, 'amahi' => 30, 'update' => 15, 'journal' => 30 }.freeze
  APP_LINES = 20
  # The bug form's Storage choices (.github/ISSUE_TEMPLATE/bug_report.yml), word for word.
  STORAGE = { greyhole: 'Greyhole (drives in a pool)', zfs: 'A ZFS pool', both: 'Both', neither: 'Neither, or not sure' }.freeze

  module_function

  def details(about: nil, page: nil)
    parts = []
    parts << "The flag said#{" on #{page}" if page}: #{about}" if about.present?
    parts << ServerSummary.text
    LOGS.each { |key, count| parts << log(key, HelpLogs.source(key, []).label, count) }
    DockerApp.where(status: 'error').order(:name).each do |app|
      parts << log("app:#{app.identifier}", "#{app.name} (needs attention)", APP_LINES)
    end
    parts.join("\n\n")
  end

  def log(key, label, count)
    body = begin
      HelpLogs.lines(key, count).join("\n").presence || '(empty)'
    rescue HelpLogs::Unreadable => e
      "(couldn't be read: #{e.message})"
    end
    "── #{label}, last #{count} lines ──\n#{body}"
  end

  # "1.4.4 (bc809de)", for the bug form's version.
  def version
    version = Rails.root.join('VERSION').read.strip
    commit = SystemServices.app_commit
    commit ? "#{version} (#{commit})" : version
  rescue SystemCallError
    'unknown'
  end

  # The bug form's Storage choice for this server.
  def storage_choice
    zfs = begin
      StoragePools.status[:pools].any?(&:managed?)
    rescue StandardError
      false
    end
    greyhole = Greyhole.installed? && DiskPoolPartition.exists?
    STORAGE.fetch(if zfs && greyhole then :both elsif zfs then :zfs elsif greyhole then :greyhole else :neither end)
  end
end
