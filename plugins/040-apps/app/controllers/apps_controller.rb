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

class AppsController < ApplicationController

	before_action :admin_required

	# make the JSON calls much more efficient by not invoking these filters
	skip_before_action :before_action_hook, except: [:index, :installed, :docker_apps]

	def index
		set_title t('apps')
		@apps = App.available
	end

	def installed
		set_title t('apps')
		@apps = App.latest_first
	end

	# Init app installation after user clicks on install button
	def install
		identifier = params[:id]
		@app = App.where(:identifier=>identifier).first
		App.install identifier unless @app # Check app/models/app.rb for App.install function
	end

	# Used to serve ajax calls for showing app installation progress progress
	def install_progress
		identifier = params[:id]
		@app = App.where(:identifier=>identifier).first

		if @app
			@app.reload
			@progress = @app.install_status
			@message = @app.install_message
		else
			@progress = App.installation_status identifier
			@message = App.installation_message @progress
		end
		# we may send HTML if there app is installed or it errored out
		# Installation errors out if @progress>100 and succedes if @progress=100
		before_action_hook if @progress >= 100
	end

	# Init app uninstall after user clicks on uninstall button
	def uninstall
		identifier = params[:id]
		@app = App.where(:identifier=>identifier).first
		@app.uninstall if @app
	end

	# Used to serve ajax calls for showing app uninstallation progress progress
	def uninstall_progress
		identifier = params[:id]
		@app = App.where(:identifier=>identifier).first
		if @app
			@app.reload
			@progress = @app.install_status
			@message = @app.uninstall_message
		else
			@message = t('application_uninstalled')
			@progress = 0
		end
	end

	def toggle_in_dashboard
		identifier = params[:id]
		app = App.where(:identifier=>identifier).first
		if app.installed
			app.show_in_dashboard = ! app.show_in_dashboard
			app.save
			@saved = true
		end
		render :json => { :status => @saved ? :ok : :not_acceptable }
	end

	# ─── Docker Apps ──────────────────────────────────────────

	def docker_apps
		set_title t('docker_apps', default: 'Docker Apps')
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
	rescue => e
		Rails.logger.error("Docker apps error: #{e.message}")
		@docker_apps = []
		@categories = []
	end

	def docker_install
		identifier = params[:id]
		entry = load_catalog.find { |e| e[:identifier] == identifier }

		unless entry
			render json: { status: :not_found, message: "App not found in catalog" }, status: :not_found
			return
		end

		# Create or find the DockerApp record
		docker_app = DockerApp.find_or_initialize_by(identifier: identifier)
		docker_app.assign_attributes(
			name: entry[:name],
			description: entry[:description],
			image: entry[:image],
			category: entry[:category],
			logo_url: entry[:logo_url],
			port_mappings: entry[:ports],
			volume_mappings: entry[:volumes],
			environment: entry[:environment],
			status: 'installing'
		)
		docker_app.save!

		# Install in background
		docker_app.install_async!

		redirect_to '/tab/apps/docker_apps', notice: "Installing #{entry[:name]}..."
	rescue => e
		redirect_to '/tab/apps/docker_apps', alert: "Install failed: #{e.message}"
	end

	def docker_uninstall
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.uninstall!
		redirect_to '/tab/apps/docker_apps', notice: "#{docker_app.name} uninstalled."
	rescue => e
		redirect_to '/tab/apps/docker_apps', alert: "Uninstall failed: #{e.message}"
	end

	def docker_start
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.start!
		redirect_to '/tab/apps/docker_apps', notice: "#{docker_app.name} started."
	rescue => e
		redirect_to '/tab/apps/docker_apps', alert: "Start failed: #{e.message}"
	end

	def docker_stop
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.stop!
		redirect_to '/tab/apps/docker_apps', notice: "#{docker_app.name} stopped."
	rescue => e
		redirect_to '/tab/apps/docker_apps', alert: "Stop failed: #{e.message}"
	end

	def docker_restart
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.restart!
		redirect_to '/tab/apps/docker_apps', notice: "#{docker_app.name} restarted."
	rescue => e
		redirect_to '/tab/apps/docker_apps', alert: "Restart failed: #{e.message}"
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
		@_catalog ||= begin
			if defined?(AppCatalog)
				AppCatalog.all
			else
				[]
			end
		end
	end
end
