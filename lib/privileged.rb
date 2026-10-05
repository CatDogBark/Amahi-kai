# Runs one operation of the root helper (libexec/amahi-helper, installed as
# /usr/local/sbin/amahi-helper):
#
#   Privileged.call('users.create', login: 'ann', name: 'Ann')   # => {"ok"=>true}
#
# Arguments, passwords included, go to the helper as JSON on stdin, never on a command
# line. The app runs it through `sudo -n`; a root process (the updater's `rails runner`,
# the installer's seeds) runs it directly. A refused or failed operation raises
# Privileged::Error with the helper's message, which is fit to show in the UI.
#
# With a block, each line the helper writes to stderr while it runs is yielded (apt's
# output during packages.install, for a progress stream).
#
# Outside production (development and tests; Shell.simulated?) nothing runs: calls are
# recorded in Privileged.calls and answered with {"ok"=>true}.

require 'json'
require 'open3'
require 'shell'

module Privileged
  HELPER = '/usr/local/sbin/amahi-helper'
  SOURCE = File.expand_path('../libexec/amahi-helper', __dir__)
  SUDO = '/usr/bin/sudo'
  ENV_MIN = { 'PATH' => '/usr/sbin:/usr/bin:/sbin:/bin' }.freeze
  MAX_RECORDED = 100

  class Error < StandardError
    attr_reader :operation

    def initialize(operation, message, refused: false)
      @operation = operation
      @refused = refused
      super(message)
    end

    # The helper turned the request down as invalid; nothing was changed.
    def refused?
      @refused
    end
  end

  class << self
    def call(operation, **args, &progress)
      return record(operation, args) if Shell.simulated?

      Rails.logger.info("Privileged: #{operation}")
      # A clean environment: Bundler's RUBYOPT must not reach a root Ruby process.
      out, err, status = if progress
                           run_streaming(operation, args, &progress)
                         else
                           Open3.capture3(ENV_MIN, *command(operation), stdin_data: JSON.generate(args),
                                          unsetenv_others: true, chdir: '/')
                         end
      reply = parse(out)
      return reply if status.success? && reply['ok']

      message = reply['error'].presence || err.strip.presence || "exit #{status.exitstatus}"
      Rails.logger.warn("Privileged: #{operation} failed: #{message}")
      raise Error.new(operation, message, refused: status.exitstatus == 1)
    rescue SystemCallError => e
      raise Error.new(operation, "the privileged helper couldn't be run (#{e.message})")
    end

    # Calls recorded outside production, oldest first: [operation, args] pairs.
    def calls
      @calls ||= []
    end

    def reset!
      @calls = []
    end

    # The operations the helper knows, read from its source.
    def operations
      load SOURCE unless defined?(AmahiHelper)
      AmahiHelper::OPERATIONS.keys
    end

    private

    # Like capture3, but yields stderr lines as they come. If the block fails (a closed
    # progress stream), the output is still drained so the helper, and apt under it,
    # run to the end.
    def run_streaming(operation, args)
      Open3.popen3(ENV_MIN, *command(operation), unsetenv_others: true, chdir: '/') do |stdin, stdout, stderr, wait|
        stdin.write(JSON.generate(args))
        stdin.close
        reader = Thread.new { stdout.read }
        tail = []
        listening = true
        stderr.each_line do |line|
          tail = (tail << line).last(5)
          begin
            yield line.chomp if listening
          rescue StandardError
            listening = false
          end
        end
        [reader.value, tail.join, wait.value]
      end
    end

    def command(operation)
      Process.uid.zero? ? [HELPER, operation] : [SUDO, '-n', HELPER, operation]
    end

    def parse(out)
      reply = JSON.parse(out.to_s.lines.last.to_s)
      reply.is_a?(Hash) ? reply : {}
    rescue JSON::ParserError
      {}
    end

    def record(operation, args)
      raise ArgumentError, "unknown privileged operation #{operation.inspect}" unless operations.include?(operation)
      calls.shift while calls.size >= MAX_RECORDED
      calls << [operation, args]
      { 'ok' => true }
    end
  end
end
