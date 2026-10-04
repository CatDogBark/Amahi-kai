# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'shell'
require 'docker_app_installer'
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
          "Setting up user permissions...",
          "  Adding amahi to docker group...",
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

  # ─── Docker Apps ──────────────────────────────────────────

  def installed_apps
    set_title t('apps')
    @docker_installed = DockerService.installed?
    @docker_running = DockerService.running?
    @docker_apps = DockerApp.where.not(status: 'available').order(:name)
  end

  def docker_apps
    set_title t('apps')
    @docker_installed, @docker_running = docker_state
    @current_category = params[:category]

    # Merge catalog with installed docker apps
    catalog = load_catalog
    installed = DockerApp.all.index_by(&:identifier)

    @docker_apps = catalog.map do |entry|
      installed[entry[:identifier]] || entry
    end

    # Add any installed apps not in catalog (manually installed)
    installed.each do |id, app|
      @docker_apps << app unless catalog.any? { |e| e[:identifier] == id }
    end

    # Filter by category if specified
    if @current_category.present?
      @docker_apps.select! do |app|
        cat = app.is_a?(DockerApp) ? app.category : app[:category]
        cat == @current_category
      end
    end

    @categories = catalog.map { |e| e[:category] }.compact.uniq.sort
  rescue JSON::ParserError, Errno::ENOENT, IOError => e
    Rails.logger.error("Docker apps error: #{e.message}")
    @docker_apps = []
    @categories = []
  end

  def docker_install
    identifier = params[:id]
    entry = load_catalog.find { |e| e[:identifier] == identifier }
    unless entry
      redirect_to '/apps', alert: "App not found"
      return
    end
    # Just redirect — actual install happens via streaming terminal
    redirect_to '/apps'
  end

  def docker_install_stream
    identifier = params[:id]
    entry = load_catalog.find { |e| e[:identifier] == identifier }
    proxy_base = "#{request.scheme}://#{request.host_with_port}"

    stream_sse do |sse|
      unless entry
        sse.emit("App not found in catalog")
        sse.done("error")
        next
      end

      app_name = entry[:name]
      image = entry[:image]

      sse.emit("Installing #{app_name}...")
      sse.emit("")

      unless Rails.env.production?
        # Dev/test simulation
        lines = [
          "Creating app record...",
          "Pulling image #{image}...",
          "  Pulling from library/#{image}",
          "  Downloading layer 1/5...",
          "  Downloading layer 2/5...",
          "  Downloading layer 3/5...",
          "  Downloading layer 4/5...",
          "  Downloading layer 5/5...",
          "  Pull complete",
          "Creating container amahi-#{identifier}...",
          "  Port mapping: #{entry[:ports].map { |c,h| "#{h} -> #{c}" }.join(', ')}",
          "Starting container...",
          "",
          "✓ #{app_name} installed and running!",
          "  Access at #{proxy_base}/app/#{identifier}"
        ]
        lines.each { |l| sleep(0.4); sse.emit(l) }

        # Create the DB record
        docker_app = DockerApp.find_or_initialize_by(identifier: identifier)
        docker_app.assign_attributes(
          name: entry[:name], description: entry[:description],
          image: image, category: entry[:category],
          logo_url: entry[:logo_url], port_mappings: entry[:ports],
          volume_mappings: entry[:volumes], environment: entry[:environment],
          status: 'running', container_name: "amahi-#{identifier}",
          host_port: entry[:ports].values.first
        )
        docker_app.save!
        sse.done
      else
        begin
          # Create DB record
          docker_app = DockerApp.find_or_initialize_by(identifier: identifier)
          docker_app.assign_attributes(
            name: entry[:name], description: entry[:description],
            image: image, category: entry[:category],
            logo_url: entry[:logo_url], port_mappings: entry[:ports],
            volume_mappings: entry[:volumes], environment: entry[:environment],
            status: 'pulling'
          )
          docker_app.save!

          reporter = ->(msg) { sse.emit(msg) }

          DockerAppInstaller.create_init_files(entry[:init_files], reporter: reporter)
          DockerAppInstaller.create_volumes(entry[:volumes], user: entry[:user], reporter: reporter)
          DockerAppInstaller.pull_image(image, reporter: reporter)

          docker_app.update!(status: 'installing')
          container_name = DockerAppInstaller.create_container(
            identifier: identifier,
            image: image,
            entry: entry,
            reporter: reporter
          )
          DockerAppInstaller.start_container(container_name, reporter: reporter)

          first_port = (entry[:ports] || {}).values.first
          docker_app.update!(
            status: 'running',
            container_name: container_name,
            host_port: first_port
          )

          sse.emit("")
          sse.emit("✓ #{app_name} installed and running!")
          sse.emit("  Access at #{proxy_base}/app/#{identifier}") if first_port
          sse.done

        rescue DockerApp::ContainerError, Shell::CommandError, DockerService::DockerError, Errno::ENOENT, IOError => e
          docker_app&.update(status: 'error', error_message: e.message)
          sse.emit("✗ #{e.message}")
          sse.done("error")
        end
      end
    end
  end

  def docker_uninstall
    docker_app = DockerApp.find_by!(identifier: params[:id])
    docker_app.uninstall!
    render json: { status: 'ok', app_status: 'available', name: docker_app.name }
  rescue DockerApp::ContainerError, Shell::CommandError, ActiveRecord::RecordNotFound => e
    render json: { status: 'error', message: e.message }, status: 500
  end

  def docker_start
    docker_app = DockerApp.find_by!(identifier: params[:id])
    docker_app.start!
    render json: { status: 'ok', app_status: 'running', host_port: docker_app.host_port, name: docker_app.name }
  rescue DockerApp::ContainerError, Shell::CommandError, ActiveRecord::RecordNotFound => e
    render json: { status: 'error', message: e.message }, status: 500
  end

  def docker_stop
    docker_app = DockerApp.find_by!(identifier: params[:id])
    docker_app.stop!
    render json: { status: 'ok', app_status: 'stopped', name: docker_app.name }
  rescue DockerApp::ContainerError, Shell::CommandError, ActiveRecord::RecordNotFound => e
    render json: { status: 'error', message: e.message }, status: 500
  end

  def docker_restart
    docker_app = DockerApp.find_by!(identifier: params[:id])
    docker_app.restart!
    render json: { status: 'ok', app_status: 'running', host_port: docker_app.host_port, name: docker_app.name }
  rescue DockerApp::ContainerError, Shell::CommandError, ActiveRecord::RecordNotFound => e
    redirect_to '/apps/docker_apps', alert: "Restart failed: #{e.message}"
  end

  def docker_status
    docker_app = DockerApp.find_by!(identifier: params[:id])
    render json: {
      status: docker_app.status,
      host_port: docker_app.host_port,
      error_message: docker_app.error_message
    }
  rescue ActiveRecord::RecordNotFound
    render json: { status: 'available' }
  end

  private

  def load_catalog
    @_catalog ||= AppCatalog.all
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
