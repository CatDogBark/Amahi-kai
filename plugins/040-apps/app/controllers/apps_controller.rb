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

	skip_before_action :before_action_hook, except: [:docker_apps, :installed_apps]

	# ─── Docker Engine Installation ───────────────────────────

	def install_docker_stream
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

			sse_send.call("Starting Docker installation...")

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
					sse_send.call(line)
				end
				sse_send.call("success", "done")
			else
				# Production — real install with streamed output
				success = true
				steps = [
					{ label: "Adding Docker's official GPG key...", commands: [
						{ cmd: "curl -fsSL #{DockerService::GPG_URL} | sudo gpg --dearmor -o #{DockerService::KEYRING_PATH} 2>&1", run: !File.exist?(DockerService::KEYRING_PATH) },
					]},
					{ label: "Adding Docker apt repository...", commands: [
						{ cmd: "echo 'deb [arch=#{`dpkg --print-architecture`.strip} signed-by=#{DockerService::KEYRING_PATH}] https://download.docker.com/linux/ubuntu #{`lsb_release -cs`.strip} stable' | sudo tee #{DockerService::SOURCES_PATH} 2>&1", run: !File.exist?(DockerService::SOURCES_PATH) },
					]},
					{ label: "Updating package lists...", commands: [
						{ cmd: "sudo apt-get update 2>&1", run: true }
					]},
					{ label: "Installing Docker Engine...", commands: [
						{ cmd: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io 2>&1", run: true }
					]},
					{ label: "Setting up user permissions...", commands: [
						{ cmd: "sudo usermod -aG docker amahi 2>&1", run: true }
					]},
					{ label: "Enabling Docker service...", commands: [
						{ cmd: "sudo systemctl enable docker 2>&1", run: true }
					]},
					{ label: "Starting Docker service...", commands: [
						{ cmd: "sudo systemctl start docker 2>&1", run: true }
					]},
				]

				steps.each do |step|
					sse_send.call(step[:label])
					step[:commands].each do |c|
						next unless c[:run]
						IO.popen(c[:cmd]) do |io|
							io.each_line do |line|
								sse_send.call("  #{line.chomp}")
							end
						end
						unless $?.success?
							sse_send.call("✗ Command failed: #{c[:cmd]}")
							success = false
							break
						end
					end
					break unless success
				end

				if success
					sse_send.call("")
					sse_send.call("✓ Docker installed successfully!")
					sse_send.call("success", "done")
				else
					sse_send.call("")
					sse_send.call("✗ Docker installation failed. Check logs above.")
					sse_send.call("error", "done")
				end
			end
		end
	end

	def start_docker
		if Rails.env.production?
			DockerService.start!
		end
		redirect_to apps_engine.docker_apps_path, notice: "Docker service started."
	rescue => e
		redirect_to apps_engine.docker_apps_path, alert: "Failed to start Docker: #{e.message}"
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
		@docker_installed = DockerService.installed?
		@docker_running = DockerService.running?
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
			redirect_to '/tab/apps', alert: "App not found"
			return
		end
		# Just redirect — actual install happens via streaming terminal
		redirect_to '/tab/apps'
	end

	def docker_install_stream
		identifier = params[:id]
		entry = load_catalog.find { |e| e[:identifier] == identifier }
		proxy_base = "#{request.scheme}://#{request.host_with_port}"

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

			unless entry
				sse_send.call("App not found in catalog")
				sse_send.call("error", "done")
				next
			end

			app_name = entry[:name]
			image = entry[:image]

			sse_send.call("Installing #{app_name}...")
			sse_send.call("")

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
				lines.each { |l| sleep(0.4); sse_send.call(l) }

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
				sse_send.call("success", "done")
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

					# Create init files (config files that must exist before container starts)
					# Always overwrite on reinstall to ensure correct config
					(entry[:init_files] || []).each do |init|
						host_path = init[:host] || init['host']
						content = init[:content] || init['content']
						sse_send.call("Creating config #{host_path}...")
						system("sudo mkdir -p #{Shellwords.escape(File.dirname(host_path))}")
						staged = "/tmp/amahi-staging/#{File.basename(host_path)}"
						FileUtils.mkdir_p('/tmp/amahi-staging')
						File.write(staged, content)
						system("sudo cp #{Shellwords.escape(staged)} #{Shellwords.escape(host_path)}")
					end

					# Create volume directories (world-writable so containers with non-root users can write)
					# Also fix permissions on existing dirs from previous installs
					(entry[:volumes] || []).each do |mapping|
						host_path = mapping.is_a?(String) ? mapping.split(':').first : mapping.values.first
						next if host_path.start_with?('/var/run/') # skip system paths
						sse_send.call("Creating directory #{host_path}...")
						system("sudo mkdir -p #{Shellwords.escape(host_path)}")
						system("sudo chmod -R 777 #{Shellwords.escape(host_path)}")
						# chown to match container user if specified
						if entry[:user].present?
							sse_send.call("  Setting ownership to UID #{entry[:user]}...")
							system("sudo chown -R #{Shellwords.escape(entry[:user].to_s)}:#{Shellwords.escape(entry[:user].to_s)} #{Shellwords.escape(host_path)}")
						end
					end

					# Pull image with progress
					sse_send.call("Pulling image #{image}...")
					IO.popen("sudo docker pull #{image} 2>&1") do |io|
						io.each_line { |line| sse_send.call("  #{line.chomp}") }
					end
					unless $?.success?
						raise "Failed to pull image #{image}"
					end
					sse_send.call("  ✓ Pull complete")

					# Remove old container if it exists (from a previous failed install)
					docker_app.update!(status: 'installing')
					container_name = "amahi-#{identifier}"
					system("sudo docker rm -f #{Shellwords.escape(container_name)} 2>/dev/null")

					cmd_parts = ["sudo", "docker", "create", "--name", container_name, "--restart", "unless-stopped"]

					# Port mappings
					(entry[:ports] || {}).each do |container_port, host_port|
						cmd_parts += ["-p", "#{host_port}:#{container_port}"]
					end

					# Volume mappings
					(entry[:volumes] || []).each do |mapping|
						if mapping.is_a?(String)
							cmd_parts += ["-v", mapping]
						else
							mapping.each { |cp, hp| cmd_parts += ["-v", "#{hp}:#{cp}"] }
						end
					end

					# Init file bind mounts (only if container path is specified)
					(entry[:init_files] || []).each do |init|
						host_path = init[:host] || init['host']
						container_path = init[:container] || init['container']
						next unless container_path.present?
						cmd_parts += ["-v", "#{host_path}:#{container_path}"]
					end

					# Environment
					(entry[:environment] || {}).each do |key, val|
						cmd_parts += ["-e", "#{key}=#{val}"]
					end

					# Extra docker args (e.g., --user, --network)
					(entry[:docker_args] || []).each do |arg|
						cmd_parts << arg.to_s
					end

					# Labels
					cmd_parts += ["-l", "amahi.managed=true", "-l", "amahi.app=#{identifier}"]
					cmd_parts << image

					sse_send.call("Creating container #{container_name}...")
					create_cmd = cmd_parts.map { |p| Shellwords.escape(p) }.join(' ')
					result = `#{create_cmd} 2>&1`
					sse_send.call("  #{result.strip}") if result.present?

					unless $?.success?
						raise "Failed to create container"
					end

					sse_send.call("Starting container...")
					system("sudo docker start #{container_name} 2>/dev/null")

					first_port = (entry[:ports] || {}).values.first
					docker_app.update!(
						status: 'running',
						container_name: container_name,
						host_port: first_port
					)

					sse_send.call("")
					sse_send.call("✓ #{app_name} installed and running!")
					sse_send.call("  Access at #{proxy_base}/app/#{identifier}") if first_port
					sse_send.call("success", "done")

				rescue => e
					docker_app&.update(status: 'error', error_message: e.message)
					sse_send.call("✗ #{e.message}")
					sse_send.call("error", "done")
				end
			end
		end
	end

	def docker_uninstall
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.uninstall!
		render json: { status: 'ok', app_status: 'available', name: docker_app.name }
	rescue => e
		render json: { status: 'error', message: e.message }, status: 500
	end

	def docker_start
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.start!
		render json: { status: 'ok', app_status: 'running', host_port: docker_app.host_port, name: docker_app.name }
	rescue => e
		render json: { status: 'error', message: e.message }, status: 500
	end

	def docker_stop
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.stop!
		render json: { status: 'ok', app_status: 'stopped', name: docker_app.name }
	rescue => e
		render json: { status: 'error', message: e.message }, status: 500
	end

	def docker_restart
		docker_app = DockerApp.find_by!(identifier: params[:id])
		docker_app.restart!
		render json: { status: 'ok', app_status: 'running', host_port: docker_app.host_port, name: docker_app.name }
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
		@_catalog ||= AppCatalog.all
	end
end
