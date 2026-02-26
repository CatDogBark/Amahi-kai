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

class SettingsController < ApplicationController

  before_action :admin_required

  def index
    @page_title = t 'settings'
    @available_locales = locales_implemented
    @advanced_settings = Setting.where(:name=>'advanced').first
    @version = Platform.platform_versions
  end

  def system_status
    @page_title = t('settings')
    @system_info = gather_system_info
    @resources = gather_resources
    @services = gather_services
    @managed_users = User.all_users rescue []
    @managed_shares = Share.all rescue []
    @managed_aliases = DnsAlias.all rescue []
    @indexed_files_count = ShareFile.count rescue 0
  end

  def servers
    @page_title = t 'settings'
    unless @advanced
      redirect_to settings_index_path
    else
      @servers = Server.all rescue []
    end
  end

  def change_language
    
    l = params[:locale]
    if params[:locale] && I18n.available_locales.include?(params[:locale].to_sym)
      cookies['locale'] = { :value => params[:locale], :expires => 1.year.from_now }
    end
    render json: { status: 'ok' }
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
    c = Command.new("reboot")
    c.execute
    render plain: t('rebooting')
  end

  def poweroff
    c = Command.new("poweroff")
    c.execute
    render plain: t('powering_off')
  end

  def refresh
    @server = Server.find(params[:id])
    render 'server_status'
  end

  def start
    @server = Server.find(params[:id])
    @server.do_start
    render 'server_status'
  end

  def stop
    @server = Server.find(params[:id])
    @server.do_stop
    render 'server_status'
  end

  def restart
    @server = Server.find(params[:id])
    @server.do_restart
    render 'server_status'
  end

  def toggle_monitored
    @server = Server.find(params[:id])
    @server.toggle!(:monitored)
    render 'server_status'
  end

  def toggle_start_at_boot
    @server = Server.find(params[:id])
    @server.toggle!(:start_at_boot)
    render 'server_status'
  end

  # index of all themes
  def themes
    @page_title = t 'settings'
    @themes = Theme.available
  end

  def activate_theme
    s = Setting.where(:name=> "theme").first
    s.value = params[:id]
    s.save!
    # redirect rather than render, so that it re-displays with the new theme
    redirect_to settings_themes_path
  end

  def update_system
    redirect_to settings_system_status_path
  end

  def update_system_stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    self.response_body = Enumerator.new do |yielder|
      sse_send = ->(data, event = nil) {
        msg = ""
        msg += "event: #{event}\n" if event
        msg += "data: #{data}\n\n"
        yielder << msg
      }

      sse_send.call("Starting system update...")

      unless Rails.env.production?
        # Dev/test simulation
        ["Pulling latest code...", "  Already up to date.",
         "Installing dependencies...", "  Bundle complete!",
         "Running database migrations...", "  No pending migrations.",
         "Precompiling assets...", "  Assets precompiled.",
         "Fixing file ownership...", "Restarting Amahi-kai...",
         "✓ Amahi-kai updated and running!"].each do |line|
          sleep(0.3)
          sse_send.call(line)
        end
        sse_send.call("success", "done")
      else
        success = true
        IO.popen("sudo /opt/amahi-kai/bin/amahi-update --stream 2>&1") do |io|
          io.each_line do |line|
            sse_send.call(line.chomp)
            if line.include?("✗")
              success = false
            end
          end
        end

        if success && $?.success?
          sse_send.call("success", "done")
        else
          sse_send.call("error", "done")
        end
      end
    end
  end

  private

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
      app_version: 'amahi-kai',
      dummy_mode: ENV['AMAHI_DUMMY_MODE'] == 'true'
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
    rescue StandardError
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
    services = [
      { name: 'Amahi-kai (Puma)', unit: 'amahi-kai' },
      { name: 'MariaDB', unit: 'mariadb' },
      { name: 'Samba (smbd)', unit: 'smbd' },
      { name: 'Samba (nmbd)', unit: 'nmbd' },
    ]

    # Optional services — only show if installed
    optional = [
      { name: 'dnsmasq', unit: 'dnsmasq', check: '/usr/sbin/dnsmasq' },
      { name: 'Greyhole', unit: 'greyhole', check: '/usr/bin/greyhole' },
      { name: 'Docker', unit: 'docker', check: '/usr/bin/docker' },
      { name: 'Cloudflare Tunnel', unit: 'cloudflared', check: '/usr/bin/cloudflared' },
    ]
    optional.each { |svc| services << svc if File.exist?(svc[:check]) }

    services.map do |svc|
      running = false
      detail = 'unknown'
      begin
        result = `systemctl is-active #{Shellwords.escape(svc[:unit])} 2>/dev/null`.strip
        running = result == 'active'
        if running
          # Get brief status
          status = `systemctl show #{Shellwords.escape(svc[:unit])} --property=ActiveEnterTimestamp --no-pager 2>/dev/null`.strip
          timestamp = status.split('=', 2).last
          detail = "since #{timestamp}" if timestamp.present?
        else
          detail = result  # 'inactive', 'failed', etc.
        end
      rescue StandardError
        detail = 'cannot check'
      end
      svc.merge(running: running, detail: detail)
    end
  end

end
