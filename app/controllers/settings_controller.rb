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

require 'shell'
require 'open3'

class SettingsController < ApplicationController
  include SseStreaming

  before_action :admin_required

  def index
    @page_title = t 'settings'
    @advanced_settings = Setting.where(:name=>'advanced').first
    @version = Platform.platform_versions
  end

  def system_status
    @page_title = t('settings')
    @system_info = gather_system_info
    @resources = gather_resources
    @services = gather_services
    @managed_users = User.all_users rescue []
    @managed_shares = Share.by_name rescue []
    @managed_aliases = DnsAlias.all rescue []
    @indexed_files_count = ShareFile.count rescue 0
    @update = UpdateStatus.load
  end

  def servers
    @page_title = t 'settings'
    unless @advanced
      redirect_to settings_index_path
    else
      @services = SystemServices.all(versions: true)
    end
  end

  def toggle_setting
    
    id = params[:id]
    s = Setting.find id
    s.value = (1 - s.value.to_i).to_s
    if s.save
      render json: { status: 'ok' }
    else
      render json: { status: 'error' }
    end
  end

  def reboot
    if Platform.reboot!
      render plain: t('rebooting')
    else
      render plain: 'Reboot failed (details in the Amahi-kai log)', status: :internal_server_error
    end
  end

  def poweroff
    if Platform.poweroff!
      render plain: t('powering_off')
    else
      render plain: 'Power off failed (details in the Amahi-kai log)', status: :internal_server_error
    end
  end

  # Start, stop or restart a service on Settings → Servers. Only the actions
  # SystemServices lists for that service are accepted.
  def service_action
    service = SystemServices.find(params[:key])
    verb = params[:verb]
    return head(:not_found) unless service&.actions&.include?(verb)

    if service.perform(verb)
      flash[:notice] = "#{service.name}: #{verb} done"
    else
      flash[:error] = "#{service.name}: #{verb} failed (details in the Amahi-kai log)"
    end
    redirect_to settings_servers_path
  end

  # index of all themes
  # The jobs that run on their own (ScheduledJobs): what each does, when it last ran and how
  # that went, and when it runs next.
  def jobs
    @page_title = t 'settings'
    @jobs = ScheduledJobs.all
  end

  def themes
    @page_title = t 'settings'
    @themes = Theme.available
  end

  def activate_theme
    unless Theme.installed?(params[:id])
      flash[:error] = "Unknown theme"
      redirect_to settings_themes_path
      return
    end
    s = Setting.where(:name=> "theme").first_or_create
    s.value = params[:id]
    s.save!
    # redirect rather than render, so that it re-displays with the new theme
    redirect_to settings_themes_path
  end

  # System Update runs as its own job (amahi-kai-update.service, started by the root
  # helper), so it outlives the restart of this app and can roll back. The page starts it
  # here, then follows its log with update_system_stream.
  UPDATE_LOG = '/var/log/amahi-kai/update.log'
  UPDATE_JOB = 'amahi-kai-update.service'
  UPDATE_STREAM_LIMIT = 70.minutes

  # "Check now" on System Status: the helper fetches main and rewrites the update status.
  def check_updates
    Privileged.call('system.check_update')
    render json: { status: 'ok' }
  rescue Privileged::Error => e
    render json: { status: 'error', error: e.message }, status: :unprocessable_entity
  end

  # repair=1 runs every step even when there's nothing new (System Status's Repair).
  def update_system
    error = start_update_job(repair: params[:repair] == '1')
    respond_to do |format|
      format.json do
        if error
          render json: { status: :error, error: error }, status: :unprocessable_entity
        else
          render json: { status: :ok }
        end
      end
      format.html { redirect_to settings_system_status_path, (error ? :alert : :notice) => error || 'System Update started' }
    end
  end

  # The update's log from line +from+ on, until the job ends. The app restarts during an
  # update, which ends this stream; the page reconnects with the number of lines it has.
  def update_system_stream
    from = params[:from].to_i.clamp(0, 1_000_000)
    stream_sse do |sse|
      if Rails.env.production?
        follow_update_log(sse, from)
      else
        simulate_update(sse, from)
      end
    end
  end

  private

  # nil if the job started (or was already running), else why not.
  def start_update_job(repair: false)
    return nil unless Rails.env.production?
    repair ? Privileged.call('system.update', repair: true) : Privileged.call('system.update')
    nil
  rescue Privileged::Error => e
    e.message
  end

  def follow_update_log(sse, from)
    sent = from
    deadline = Time.current + UPDATE_STREAM_LIMIT
    loop do
      running = update_running? != false # before reading, so the last lines are never missed
      lines = File.exist?(UPDATE_LOG) ? File.readlines(UPDATE_LOG, chomp: true) : []
      lines.drop(sent).each { |line| sse.emit(line.scrub) }
      sent = [sent, lines.size].max
      # The update is restarting the app: end without "done" and the page reconnects to the
      # new version, which says how it ended. Puma finishes open requests before it stops, so
      # a stream that waited for the update would hold the restart until systemd killed Puma
      # (90 seconds). This comes before deciding the update is over: the restart also stops
      # the check below, and a check stopped halfway says nothing about the update.
      return if server_stopping?
      return sse.done(lines.last.to_s.start_with?('✓') ? 'success' : 'error') unless running
      return sse.done('error') if Time.current > deadline
      sleep 0.5
    end
  end

  # true or false from systemd, or nil when the check gave no answer. Stopping amahi-kai.service
  # signals every process in it, so a check running at that moment is killed: that's no answer,
  # not a finished update (System Update once said it failed when it hadn't, #52).
  def update_running?
    out, _err, status = Open3.capture3('systemctl', 'is-active', UPDATE_JOB)
    state = out.strip
    return nil if state.empty? || status.signaled?
    %w[active activating reloading].include?(state)
  rescue SystemCallError
    nil
  end

  # True once Puma has been told to stop or restart. The stream's body runs in a Puma
  # thread, which knows its server.
  def server_stopping?
    server = Puma::Server.current if defined?(Puma::Server)
    server ? server.shutting_down? : false
  end

  def simulate_update(sse, from)
    lines = ["Setting file ownership...", "Pulling latest code...", "  Already up to date.",
             "Installing dependencies...", "  Bundle complete!",
             "Backing up the database...", "Running database migrations...",
             "Precompiling assets...", "Restarting Amahi-kai...",
             "✓ Amahi-kai updated and running!"]
    lines.drop(from).each do |line|
      sleep(0.3)
      sse.emit(line)
    end
    sse.done
  end

  def gather_system_info
    hostname = `hostname`.strip rescue 'unknown'
    ip = `hostname -I`.strip.split.first rescue 'unknown'
    os = if File.exist?('/etc/os-release')
      File.readlines('/etc/os-release').find { |l| l.start_with?('PRETTY_NAME=') }&.split('=', 2)&.last&.tr('"', '')&.strip || 'Unknown'
    else
      'Unknown'
    end
    kernel = `uname -r`.strip rescue 'unknown'
    uptime_raw = `uptime -p`.strip rescue 'unknown'

    {
      hostname: hostname,
      ip_address: ip,
      os: os,
      kernel: kernel,
      uptime: uptime_raw,
      ruby_version: RUBY_VERSION,
      rails_version: Rails::VERSION::STRING,
      app_version: SystemServices.app_commit || 'unknown'
    }
  end

  def gather_resources
    # CPU load average
    cpu = 0
    cpu_detail = 'unavailable'
    if File.exist?('/proc/loadavg')
      load1, load5, load15 = File.read('/proc/loadavg').split[0..2].map(&:to_f)
      cores = `nproc`.strip.to_i rescue 1
      cores = 1 if cores < 1
      cpu = ((load1 / cores) * 100).round
      cpu_detail = "Load: #{load1} / #{load5} / #{load15} (#{cores} cores)"
    end

    # Memory
    mem_percent = 0
    mem_detail = 'unavailable'
    if File.exist?('/proc/meminfo')
      meminfo = File.read('/proc/meminfo')
      total = meminfo[/MemTotal:\s+(\d+)/, 1].to_i
      available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_i
      if total > 0
        used = total - available
        mem_percent = ((used.to_f / total) * 100).round
        mem_detail = "#{(used / 1024.0).round} MB / #{(total / 1024.0).round} MB"
      end
    end

    # Disk
    disk_percent = 0
    disk_detail = 'unavailable'
    begin
      df = `df -h / 2>/dev/null`.lines.last
      if df
        parts = df.split
        disk_percent = parts[4].to_i  # "42%" -> 42
        disk_detail = "#{parts[2]} used / #{parts[1]} total (#{parts[3]} free)"
      end
    rescue Errno::ENOENT, IOError
    end

    {
      cpu_percent: [cpu, 100].min,
      cpu_detail: cpu_detail,
      memory_percent: mem_percent,
      memory_detail: mem_detail,
      disk_percent: disk_percent,
      disk_detail: disk_detail
    }
  end

  def gather_services
    SystemServices.all.map do |svc|
      detail = svc.running? && svc.since ? "since #{l(svc.since, format: :long)}" : (svc.idle_detail || svc.state)
      { name: svc.name, unit: svc.unit, running: svc.running?, idle: svc.idle?, detail: detail }
    end
  end

end
