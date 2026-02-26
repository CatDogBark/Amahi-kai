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

require 'platform'
require 'shell'

class Server < ApplicationRecord

  PID_PATH = "/var/run"

  validates_uniqueness_of :name
  validates_presence_of :name

  before_save  :before_save_hook
  after_create  :create_hook
  after_destroy  :destroy_hook

  def self.create_default_servers
    Server.create(:name => 'smb', :pidfile => Platform.file_name(:samba_pid), :comment => I18n.t('file_server_samba'))
    r = "# WARNING - This file was automatically generated on #{Time.now}\n" \
      "\nset daemon 30\n" \
      "include #{Platform.file_name(:monit_dir)}/logging\n" \
      "include #{Platform.file_name(:monit_dir)}/*.conf\n"
    fname = TempCache.unique_filename "server-conf"
    f = File.new fname, "w"
    f.write r
    Shell.run(
      "cp -f #{f.path} #{Platform.file_name(:monit_conf)}",
      "rm -f #{f.path}",
      "chmod 644 #{Platform.file_name(:monit_log)}",
      Platform.watchdog_restart_command
    )
    f.close
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
    name.gsub /@/, '-'
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
    Shell.run(
      "rm -f #{File.join(Platform.file_name(:monit_dir), Platform.service_name(name))}.conf",
      Platform.watchdog_restart_command,
      disable_cmd,
      stop_cmd
    )
  end

  def cmd_file
    "# WARNING - This file was automatically generated on #{Time.now}\n"  \
    "check process #{self.clean_name} with pidfile \"#{self.pid_file}\"\n"  \
          "\tstart program = \"#{self.start_cmd}\"\n"        \
          "\tstop  program = \"#{self.stop_cmd}\"\n"
  end

  def monit_file_add
    fname = TempCache.unique_filename "server-#{self.name}"
    File.open(fname, "w") { |f| f.write cmd_file }
    Shell.run(
      "cp -f #{fname} #{File.join(Platform.file_name(:monit_dir), Platform.service_name(self.name))}.conf",
      "rm -f #{fname}",
      Platform.watchdog_restart_command
    )
  end

  def monit_file_remove
    Shell.run(
      "rm -f #{File.join(Platform.file_name(:monit_dir), Platform.service_name(name))}.conf",
      Platform.watchdog_restart_command
    )
  end

  def service_enable
    Shell.run(enable_cmd)
  end

  def service_disable
    Shell.run(disable_cmd)
  end

  def before_save_hook
    if monitored_changed?
      monitored ? monit_file_add : monit_file_remove
    end
    if start_at_boot_changed?
      start_at_boot ? service_enable : service_disable
    end
  end

  def create_hook
    Shell.run(enable_cmd, start_cmd)
    monit_file_add
  end

  def estimate_pids
    pf = pid_file
    ret = []
    begin
      if File.exist?(pf) && File.readable?(pf)
        File.open(pf) do |p|
          list = p.readlines.map{ |line| line.gsub(/\n/, '').split(' ') }.flatten
          ret = list.map{|pid| File.exist?("/proc/#{pid}") ? pid : nil }.compact
        end
      end
    rescue => e
      # something went wrong
    end
    return ret unless ret.empty?

    begin
      IO.popen("pgrep #{Platform.service_name name}") do |p|
        ret = p.readlines.map {|pid| pid.gsub(/\n/, '')}
      end
      return ret unless ret.empty?
      IO.popen("pgrep #{name}") do |p|
        ret = p.readlines.map {|pid| pid.gsub(/\n/, '')}
      end
    rescue => e
      []
    end
    ret
  end

end
