# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# Service management model — wraps systemctl for the settings UI.
# Monit integration removed (not installed on Amahi-kai).

require 'platform'
require 'shell'

class Server < ApplicationRecord

  PID_PATH = "/var/run"

  validates_uniqueness_of :name
  validates_presence_of :name

  before_save :before_save_hook
  after_create :create_hook
  after_destroy :destroy_hook

  def self.create_default_servers
    Server.create(name: 'smb', pidfile: Platform.file_name(:samba_pid), comment: I18n.t('file_server_samba'))
  end

  def pids
    estimate_pids
  end

  def do_start
    Shell.run(start_cmd)
  end

  def do_stop
    Shell.run(stop_cmd)
  end

  def do_restart
    Shell.run(stop_cmd, start_cmd)
  end

  def stopped?
    pids.empty?
  end

  def running?
    !stopped?
  end

  def clean_name
    name.gsub(/@/, '-')
  end

  protected

  def pid_file
    tmp = self.pidfile || (self.name + ".pid")
    (tmp =~ /^\//) ? tmp : File.join(PID_PATH, tmp)
  end

  def start_cmd
    Platform.service_start_command(name)
  end

  def stop_cmd
    Platform.service_stop_command(name)
  end

  def enable_cmd
    Platform.service_enable_command(name)
  end

  def disable_cmd
    Platform.service_disable_command(name)
  end

  def destroy_hook
    Shell.run(disable_cmd, stop_cmd)
  end

  def before_save_hook
    if start_at_boot_changed?
      start_at_boot ? Shell.run(enable_cmd) : Shell.run(disable_cmd)
    end
  end

  def create_hook
    Shell.run(enable_cmd, start_cmd)
  end

  def estimate_pids
    pf = pid_file
    ret = []
    begin
      if File.exist?(pf) && File.readable?(pf)
        File.open(pf) do |p|
          list = p.readlines.map { |line| line.gsub(/\n/, '').split(' ') }.flatten
          ret = list.map { |pid| File.exist?("/proc/#{pid}") ? pid : nil }.compact
        end
      end
    rescue => e
      # something went wrong
    end
    return ret unless ret.empty?

    begin
      IO.popen("pgrep #{Platform.service_name name}") do |p|
        ret = p.readlines.map { |pid| pid.gsub(/\n/, '') }
      end
      return ret unless ret.empty?
      IO.popen("pgrep #{name}") do |p|
        ret = p.readlines.map { |pid| pid.gsub(/\n/, '') }
      end
    rescue => e
      []
    end
    ret
  end
end
