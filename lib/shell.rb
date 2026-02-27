# Unified shell execution for Amahi-kai.
#
# Replaces the legacy Command class with a simpler, consistent API.
# Handles sudo escalation, logging, and error reporting.
#
# Usage:
#   Shell.run("mkdir -p /var/hda/files/movies")
#   Shell.run("chown user:users /path", "chmod g+w /path")
#   Shell.run!("systemctl restart smbd")  # raises on failure
#
#   # Blocking execution (waits for completion, used by package installs)
#   Shell.run!("apt-get -y install ntfs-3g", blocking: true)

require 'open3'
require 'shellwords'

module Shell
  # Privileged commands that need sudo when not running as root
  SUDO_COMMANDS = %w[
    useradd usermod userdel
    systemctl hostnamectl
    chmod chown
    mkdir rmdir cp mv rm
    pdbedit
    sh bash
    apt-get dpkg rpm yum pacman
    docker
    fallocate dd mkswap swapon swapoff
    mount umount
    reboot poweroff
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

    # Execute a single command and return [stdout, stderr, status].
    # For cases where you need the output.
    def capture(cmd)
      actual_cmd = prepare(cmd)
      log_cmd(actual_cmd)
      Open3.capture3(actual_cmd)
    end

    # Check if we're in dummy mode (dev/test without real system access)
    def dummy?
      return @dummy if defined?(@dummy)
      @dummy = begin
        require_relative 'yetting'
        Yetting.dummy_mode
      rescue StandardError
        Rails.env.test? rescue true
      end
    end

    # Allow overriding dummy mode (useful for specific tests)
    # Pass nil to reset to auto-detection.
    def dummy=(val)
      if val.nil?
        remove_instance_variable(:@dummy) if defined?(@dummy)
      else
        @dummy = val
      end
    end

    private

    def exec_one(cmd)
      if dummy?
        log_cmd("[DUMMY] #{cmd}")
        return [true, '', '', 0]
      end

      actual_cmd = prepare(cmd)
      log_cmd(actual_cmd)

      stdout, stderr, status = Open3.capture3(actual_cmd)
      unless status.success?
        log_warn("Command failed (exit #{status.exitstatus}): #{actual_cmd}\nstderr: #{stderr}")
      end
      [status.success?, stdout, stderr, status.exitstatus]
    end

    def prepare(cmd)
      return cmd if Process.uid == 0

      # Extract the actual command name, skipping env vars
      parts = cmd.strip.split(/\s+/)
      cmd_idx = parts.index { |p| !p.include?('=') } || 0
      cmd_name = File.basename(parts[cmd_idx].to_s)

      return cmd unless SUDO_COMMANDS.include?(cmd_name)

      # Resolve to full path for sudoers NOPASSWD matching
      full_path = `which #{parts[cmd_idx]} 2>/dev/null`.strip
      parts[cmd_idx] = full_path unless full_path.empty?
      "sudo #{parts.join(' ')}"
    end

    def log_cmd(cmd)
      Rails.logger.info("Shell: #{cmd}") if defined?(Rails) && Rails.logger
    end

    def log_warn(msg)
      Rails.logger.warn("Shell: #{msg}") if defined?(Rails) && Rails.logger
    end
  end
end
