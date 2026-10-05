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

  skip_before_action :before_action_hook, except: [:docker_apps, :installed_apps]

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
  end

  # The install itself runs in the stream (the page opens it in the install window).
  def docker_install
    redirect_to apps_index_path
  end

  def docker_install_stream
    entry = AppCatalog.find(params[:id])
    host = request.host
    stream_sse do |sse|
      unless entry
        sse.emit("That app isn't in the catalog")
        sse.done('error')
        next
      end
      install_app(entry, host, sse)
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

  def docker_restart
    app_action(&:restart!)
  end

  def docker_status
    docker_app = DockerApp.find_by!(identifier: params[:id])
    render json: { status: docker_app.status, host_port: docker_app.host_port, error_message: docker_app.error_message }
  rescue ActiveRecord::RecordNotFound
    render json: { status: 'available' }
  end

  private

  # Installs +entry+ through the root helper (apps.install), streaming its progress.
  def install_app(entry, host, sse)
    sse.emit("Installing #{entry[:name]}...")
    app = DockerApp.find_or_initialize_by(identifier: entry[:identifier])
    app.update!(name: entry[:name], description: entry[:description], image: entry[:image],
                category: entry[:category], logo_url: entry[:logo_url], host_port: entry[:web_port],
                container_name: "amahi-#{entry[:identifier]}", status: 'installing', error_message: nil)
    Privileged.call('apps.install', app: entry[:identifier]) { |line| sse.emit("  #{line}") }
    app.update!(status: 'running')
    sse.emit('')
    sse.emit("✓ #{entry[:name]} is installed and running")
    sse.emit("  Open it at http://#{host}:#{entry[:web_port]}/") if entry[:web_port]
    sse.done
  rescue Privileged::Error => e
    app&.update(status: 'error', error_message: e.message)
    sse.emit("✗ #{e.message}")
    sse.done('error')
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
