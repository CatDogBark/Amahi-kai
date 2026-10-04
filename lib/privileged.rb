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
# In dummy mode (development and tests) nothing runs: calls are recorded in
# Privileged.calls and answered with {"ok"=>true}.

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
    def call(operation, **args)
      return record(operation, args) if Shell.dummy?

      Rails.logger.info("Privileged: #{operation}")
      # A clean environment: Bundler's RUBYOPT must not reach a root Ruby process.
      out, err, status = Open3.capture3(ENV_MIN, *command(operation), stdin_data: JSON.generate(args),
                                        unsetenv_others: true, chdir: '/')
      reply = parse(out)
      return reply if status.success? && reply['ok']

      message = reply['error'].presence || err.strip.presence || "exit #{status.exitstatus}"
      Rails.logger.warn("Privileged: #{operation} failed: #{message}")
      raise Error.new(operation, message, refused: status.exitstatus == 1)
    rescue SystemCallError => e
      raise Error.new(operation, "the privileged helper couldn't be run (#{e.message})")
    end

    # Calls made in dummy mode, oldest first: [operation, args] pairs.
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
