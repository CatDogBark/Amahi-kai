# Unified shell execution for Amahi-kai.
#
# Replaces the legacy Command class with a simpler, consistent API.
# Handles logging and error reporting.
#
# Usage:
#   Shell.capture("pgrep -f greyhole")
#   Shell.run!("true")  # raises on failure
#
# Commands run as the app's own user: nothing here uses sudo. Everything that needs root
# goes through the root helper (Privileged.call).

require 'open3'
require 'shellwords'

module Shell
  # A last line of defence for the log: secrets belong on stdin or in private files
  # (see run_with_input), but anything secret-shaped that reaches a command is masked.
  REDACTIONS = [
    [/(IDENTIFIED\s+BY\s+)'[^']*'/i, "\\1'[FILTERED]'"],
    [/(--token\s+)\S+/, '\1[FILTERED]'],
    [/((?:password|passwd|db_pass|secret|token)\s*[=:]\s*)\S+/i, '\1[FILTERED]']
  ].freeze

  class CommandError < StandardError
    attr_reader :command, :stderr, :exit_code

    def initialize(command, stderr, exit_code)
      @command = command
      @stderr = stderr
      @exit_code = exit_code
      super("Command failed (exit #{exit_code}): #{command}\n#{stderr}")
    end
  end

  class << self
    # Execute one or more commands sequentially. Returns true if all succeed.
    # Logs failures but does not raise.
    def run(*commands)
      commands.flatten.each do |cmd|
        success, _stdout, _stderr, _exit_code = exec_one(cmd)
        return false unless success
      end
      true
    end

    # Execute one or more commands sequentially. Raises Shell::CommandError on failure.
    def run!(*commands)
      commands.flatten.each do |cmd|
        success, _stdout, stderr, exit_code = exec_one(cmd)
        raise CommandError.new(cmd, stderr, exit_code) unless success
      end
      true
    end

    # Execute a single command, feeding +input+ on stdin. Returns true on success.
    # Use this for secrets such as passwords, so they never appear in argv or the log.
    def run_with_input(cmd, input)
      if simulated?
        log_cmd("[SIMULATED] #{cmd} (stdin withheld)")
        return true
      end

      log_cmd("#{cmd} (stdin withheld)")

      _stdout, stderr, status = Open3.capture3(cmd, stdin_data: input)
      unless status.success?
        log_warn("Command failed (exit #{status.exitstatus}): #{cmd}\nstderr: #{stderr}")
      end
      status.success?
    end

    # Execute a single command and return [stdout, stderr, status].
    # For cases where you need the output.
    def capture(cmd)
      log_cmd(cmd)
      Open3.capture3(cmd)
    end

    # +text+ with anything secret-shaped masked (REDACTIONS).
    def redact(text)
      REDACTIONS.reduce(text.to_s) { |out, (pattern, replacement)| out.gsub(pattern, replacement) }
    end

    # Outside production (development and tests) commands are only logged, never run, and
    # Privileged.call records root helper calls instead of running the helper, so the specs
    # and a laptop running Amahi-kai never change the computer. Production always runs them:
    # no setting can turn this on there (it used to be "dummy mode", which a setting in
    # amahi.env could switch on).
    def simulated?
      return @simulated unless @simulated.nil?
      !(defined?(Rails) && Rails.env.production?)
    end

    # For specs that test the real code paths with the system calls stubbed: false runs them,
    # nil goes back to the rule above.
    def simulated=(value)
      @simulated = value
    end

    private

    def exec_one(cmd)
      if simulated?
        log_cmd("[SIMULATED] #{cmd}")
        return [true, '', '', 0]
      end

      log_cmd(cmd)

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        log_warn("Command failed (exit #{status.exitstatus}): #{cmd}\nstderr: #{stderr}")
      end
      [status.success?, stdout, stderr, status.exitstatus]
    end

    def log_cmd(cmd)
      Rails.logger.info("Shell: #{redact(cmd)}") if defined?(Rails) && Rails.logger
    end

    def log_warn(msg)
      Rails.logger.warn("Shell: #{redact(msg)}") if defined?(Rails) && Rails.logger
    end
  end
end
