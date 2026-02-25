# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."

require 'open3'
require_relative 'yetting'

class Command

  # Legacy hda-ctl constants (kept for reference)
  CMD_FIFO = "/var/run/hda-ctl/notify"
  HDACTL_PID = "/var/run/hda-ctl.pid"

  # Execution mode:
  #   :direct  - execute commands directly via shell (default on Ubuntu)
  #   :hdactl  - send commands to hda-ctl daemon (legacy Fedora mode)
  #   :dummy   - don't execute anything (dev/test)
  EXEC_MODE = if Yetting.dummy_mode
    :dummy
  elsif File.exist?(HDACTL_PID)
    :hdactl
  else
    :direct
  end

  def initialize(cmd = nil)
    @cmd = cmd ? [cmd] : []
  end

  def execute
    return if EXEC_MODE == :dummy

    case EXEC_MODE
    when :direct
      execute_direct
    when :hdactl
      execute_hdactl
    end

    @cmd = []
  end

  def run_now
    return if EXEC_MODE == :dummy

    case EXEC_MODE
    when :direct
      execute_direct
    when :hdactl
      execute_hdactl_blocking
    end

    @cmd = []
  end

  def submit(command)
    @cmd.push command
  end

  private

  # Execute commands directly via shell
  # Uses sudo for privileged commands when not running as root
  def execute_direct
    @cmd.each do |cmd|
      actual_cmd = if needs_sudo?(cmd)
        # Resolve command to full path so sudoers NOPASSWD rules match
        parts = cmd.strip.split(/\s+/)
        cmd_idx = parts.index { |p| !p.include?('=') } || 0
        full_path = `which #{parts[cmd_idx]} 2>/dev/null`.strip
        parts[cmd_idx] = full_path unless full_path.empty?
        "sudo #{parts.join(' ')}"
      else
        cmd
      end
      Rails.logger.info("Command.execute_direct: #{actual_cmd}") if defined?(Rails)

      stdout, stderr, status = Open3.capture3(actual_cmd)
      unless status.success?
        Rails.logger.warn("Command failed (exit #{status.exitstatus}): #{actual_cmd}\nstderr: #{stderr}") if defined?(Rails)
      end
    end
  end

  # Determine if a command needs sudo
  # Commands that modify system state need root privileges
  def needs_sudo?(cmd)
    return false if Process.uid == 0  # already root

    privileged_prefixes = %w[
      useradd usermod userdel
      systemctl hostnamectl
      chmod chown
      mkdir rmdir cp mv rm
      pdbedit
      sh bash
      apt-get dpkg rpm yum pacman
    ]

    cmd_name = cmd.strip.split(/\s+/).first
    # Handle env vars before command (e.g., "DEBIAN_FRONTEND=noninteractive apt-get ...")
    if cmd_name&.include?('=')
      cmd_name = cmd.strip.split(/\s+/).find { |part| !part.include?('=') }
    end
    # Handle full paths
    cmd_name = File.basename(cmd_name.to_s)

    privileged_prefixes.include?(cmd_name)
  end

  # Legacy: send commands to hda-ctl daemon
  def execute_hdactl
    raise "hda-ctl does not appear to be running!" unless hdactl_running?
    command = @cmd.join "\n"
    f = UNIXSocket.open(CMD_FIFO)
    f.send(command, 0)
    f.close
  end

  # Legacy: send commands to hda-ctl and wait for completion
  def execute_hdactl_blocking
    raise "hda-ctl does not appear to be running!" unless hdactl_running?
    confirm = "done"
    @cmd.push "confirm: #{confirm}\n"
    command = @cmd.join "\n"
    f = UNIXSocket.open(CMD_FIFO)
    f.send(command, 0)
    f.flush
    begin
      r = f.read
      r.strip!
    end until r == confirm or f.eof
    raise "error run_now - did not get confirmation of command completion." unless r == confirm
    f.close
  end

  def hdactl_running?
    begin
      f = File.open HDACTL_PID
      s = f.readline
      f.close
      s.chomp!
      File.exist?("/proc/#{s}") ? true : false
    rescue => e
      false
    end
  end
end
