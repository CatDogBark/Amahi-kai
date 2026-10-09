# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

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

class AppsController < ApplicationController
  include SseStreaming

  before_action :admin_required


  # ─── Docker Engine Installation ───────────────────────────

  def install_docker_stream
    stream_sse do |sse|
      sse.emit("Starting Docker installation...")

      unless Rails.env.production?
        # Dev/test mode — simulate install
        lines = [
          "Adding Docker's official GPG key...",
          "  Downloading signing key...",
          "  Adding apt repository...",
          "Updating package lists...",
          "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
          "  Get:2 https://download.docker.com/linux/ubuntu noble stable InRelease",
          "  Fetched 18.2 kB in 1s (12,100 B/s)",
          "Installing Docker Engine...",
          "  Reading package lists...",
          "  Building dependency tree...",
          "  The following NEW packages will be installed:",
          "    containerd.io docker-ce docker-ce-cli",
          "  0 upgraded, 3 newly installed, 0 to remove.",
          "  Need to get 98.4 MB of archives.",
          "  Get:1 https://download.docker.com/linux/ubuntu noble/stable amd64 containerd.io amd64 1.7.24-1 [29.5 MB]",
          "  Get:2 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce-cli amd64 5:27.4.1-1 [14.9 MB]",
          "  Get:3 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce amd64 5:27.4.1-1 [25.6 MB]",
          "  Unpacking containerd.io (1.7.24-1) ...",
          "  Unpacking docker-ce-cli (5:27.4.1-1) ...",
          "  Unpacking docker-ce (5:27.4.1-1) ...",
          "  Setting up containerd.io (1.7.24-1) ...",
          "  Setting up docker-ce-cli (5:27.4.1-1) ...",
          "  Setting up docker-ce (5:27.4.1-1) ...",
          "Enabling Docker service...",
          "  Created symlink /etc/systemd/system/multi-user.target.wants/docker.service",
          "Starting Docker service...",
          "",
          "✓ Docker installed successfully!"
        ]
        lines.each do |line|
          sleep(0.3)
          sse.emit(line)
        end
        sse.done
      else
        begin
          DockerService.install! { |line| sse.emit(line) }
          sse.emit("")
          sse.emit("✓ Docker installed successfully!")
          sse.done
        rescue DockerService::DockerError => e
          sse.emit("  ✗ #{e.message}")
          sse.emit("")
          sse.emit("✗ Docker installation failed. Check logs above.")
          sse.done("error")
        end
      end
    end
  end

  def start_docker
    DockerService.start! if Rails.env.production?
    respond_to do |format|
      format.json { render json: { status: 'ok', running: true } }
      format.html { redirect_to apps_index_path, notice: "Docker service started." }
    end
  rescue DockerService::DockerError => e
    respond_to do |format|
      format.json { render json: { status: 'error', message: e.message }, status: 500 }
      format.html { redirect_to apps_index_path, alert: "Failed to start Docker: #{e.message}" }
    end
  end

  def stop_docker
    DockerService.stop! if Rails.env.production?
    respond_to do |format|
      format.json { render json: { status: 'ok', running: false } }
      format.html { redirect_to apps_index_path, notice: "Docker service stopped." }
    end
  rescue DockerService::DockerError => e
    respond_to do |format|
      format.json { render json: { status: 'error', message: e.message }, status: 500 }
      format.html { redirect_to apps_index_path, alert: "Failed to stop Docker: #{e.message}" }
    end
  end

  # ─── Docker Apps (docs/plans/apps.md: the root helper installs and runs them) ───

  def installed_apps
    set_title t('apps')
    @docker_installed, @docker_running = docker_state
    DockerApp.refresh_statuses! if @docker_running
    @docker_apps = DockerApp.order(:name)
    @shares = Share.by_name
  end

  def docker_apps
    set_title t('apps')
    @docker_installed, @docker_running = docker_state
    DockerApp.refresh_statuses! if @docker_running
    @current_category = params[:category]
    installed = DockerApp.all.index_by(&:identifier)
    catalog = AppCatalog.all
    catalog = catalog.select { |app| app[:category] == @current_category } if @current_category.present?
    @docker_apps = catalog.map { |entry| installed[entry[:identifier]] || entry }
    @categories = AppCatalog.categories
    @shares = Share.by_name
  end

  # Check now: the update check, as the timer runs it every 6 hours (Amahi-kai and the app
  # catalog's repo), and the page says what it found. It never installs anything.
  def refresh_catalog
    Privileged.call('system.check_update')
    AppCatalog.reload!
    status = AppCatalog.status
    if status&.dig(:error)
      redirect_back fallback_location: apps_index_path, alert: "Couldn't refresh the app catalog: #{status[:error]}"
    else
      redirect_back fallback_location: apps_index_path, notice: 'Checked Amahi-kai and the apps for updates.'
    end
  rescue Privileged::Error => e
    redirect_back fallback_location: apps_index_path, alert: "Couldn't refresh the app catalog: #{e.message}"
  end

  def docker_install_stream
    entry = AppCatalog.find(params[:id])
    host = request.host
    shares = entry ? chosen_shares(entry) : []
    stream_sse do |sse|
      unless entry
        sse.emit("That app isn't in the catalog")
        sse.done('error')
        next
      end
      install_app(entry, host, sse, shares)
    end
  end

  # Update (P4.5): the helper copies the app's data, starts the catalog's version, and goes back
  # to the old one if it isn't healthy within 5 minutes.
  def docker_update_stream
    app_stream('apps.update') do |app, entry, reply, sse|
      if reply['updated']
        sse.emit("✓ #{entry[:name]} is updated to #{AppCatalog.tag(reply['image'])} and running")
        sse.emit("  Undo update, on its row, goes back to #{AppCatalog.tag(reply['from'])} for #{AppCatalog::BACKUP_DAYS} days.")
        true
      else
        sse.emit("✗ #{AppCatalog.tag(entry[:image])} didn't come up healthy: #{reply['problem']}")
        sse.emit("  #{entry[:name]} is back on #{app.version}, with its data as it was before.")
        false
      end
    end
  end

  # Undo update: the version and data from before the last update come back.
  def docker_undo_update_stream
    app_stream('apps.undo_update') do |app, entry, _reply, sse|
      sse.emit("✓ #{entry[:name]} is back on #{app.version}, with its data from before the update")
      true
    end
  end

  def docker_uninstall
    unless AppCatalog.find(params[:id])
      return render json: { status: 'error', message: "That app isn't in the catalog" }, status: :not_found
    end

    DockerApp.uninstall(params[:id], delete_data: ActiveModel::Type::Boolean.new.cast(params[:delete_data]) == true)
    render json: { status: 'ok' }
  rescue DockerApp::ContainerError => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_content
  end

  def docker_start
    app_action(&:start!)
  end

  def docker_stop
    app_action(&:stop!)
  end

  private

  # Installs +entry+ through the root helper (apps.install), streaming its progress. Changing an
  # app's shares installs it again with the new ones.
  def install_app(entry, host, sse, shares)
    sse.emit("Installing #{entry[:name]}...")
    app = DockerApp.find_or_initialize_by(identifier: entry[:identifier])
    app.update!(name: entry[:name], description: entry[:description], image: app.image.presence || entry[:image],
                category: entry[:category], logo_url: entry[:logo_url], host_port: entry[:web_port],
                container_name: "amahi-#{entry[:identifier]}", status: 'installing', error_message: nil,
                shares: shares)
    reply = Privileged.call('apps.install', app: entry[:identifier], shares: shares) { |line| sse.emit("  #{line}") }
    ports = DockerApp.assigned_ports(entry, reply['ports'])
    web = ports.find { |port| port[:label] == 'web' }
    # A reinstall keeps the version the app runs (only Update changes it): the reply says which.
    app.update!(status: 'running', host_port: web&.dig(:host), ports: ports, image: reply['image'].presence || entry[:image])
    sse.emit('')
    sse.emit("✓ #{entry[:name]} is installed and running")
    sse.emit("  Open it at #{app.url(host)} (on your LAN or Tailscale)") if web
    sse.done
  rescue Privileged::Error => e
    app&.update(status: 'error', error_message: e.message)
    sse.emit("✗ #{e.message}")
    sse.done('error')
  end

  # [{ name:, write: }] from the share dialog (share[]=Movies&write[]=Downloads): only shares that
  # exist, and write only where the app writes shares and Greyhole doesn't pool the share. The
  # helper checks the same against smb.conf.
  def chosen_shares(entry)
    names = Array(params[:share]).map(&:to_s)
    writes = Array(params[:write]).map(&:to_s)
    Share.by_name.where(name: names).map do |share|
      write = entry[:writes_shares] && writes.include?(share.name) && share.disk_pool_copies.to_i.zero?
      { name: share.name, write: write }
    end
  end

  # Runs +operation+ on an installed app with its shares, streaming the helper's progress, then
  # records the version (and ports) it runs. The block writes the outcome and returns whether
  # it worked.
  def app_stream(operation)
    app = DockerApp.find_by(identifier: params[:id])
    entry = AppCatalog.find(params[:id])
    host = request.host
    stream_sse do |sse|
      unless app && entry
        sse.emit("That app isn't installed")
        sse.done('error')
        next
      end
      begin
        reply = Privileged.call(operation, app: app.identifier, shares: app.shares) { |line| sse.emit("  #{line}") }
        ports = reply['ports'] ? DockerApp.assigned_ports(entry, reply['ports']) : app.ports
        app.update!(image: reply['image'].presence || app.image, status: 'running', error_message: nil,
                    ports: ports, host_port: ports.find { |port| port[:label] == 'web' }&.dig(:host) || app.host_port)
        sse.emit('')
        worked = yield app, entry, reply, sse
        sse.emit("  Open it at #{app.url(host)} (on your LAN or Tailscale)") if app.url(host)
        worked ? sse.done : sse.done('error')
      rescue Privileged::Error => e
        DockerApp.refresh_statuses!
        sse.emit("✗ #{e.message}")
        sse.done('error')
      end
    end
  end

  # Start, stop or restart an installed app; the page reloads on { status: 'ok' }.
  def app_action
    app = DockerApp.find_by(identifier: params[:id])
    return render json: { status: 'error', message: "That app isn't installed" }, status: :not_found unless app

    yield app
    render json: { status: 'ok' }
  rescue DockerApp::ContainerError => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_content
  end

  # [installed, running]. A failing check shows Docker as not installed instead of
  # breaking the Apps page.
  def docker_state
    [DockerService.installed?, DockerService.running?]
  rescue StandardError => e
    Rails.logger.warn("AppsController: couldn't check Docker: #{e.message}")
    [false, false]
  end
end
