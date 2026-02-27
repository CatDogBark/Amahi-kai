# Handles Docker app container installation: init files, volumes, pull, create, start.
# Extracted from AppsController to keep Shell.run out of controllers.

require 'shell'
require 'shellwords'
require 'fileutils'

module DockerAppInstaller
  STAGING_DIR = '/tmp/amahi-staging'

  class << self
    # Prepare init files (config files that must exist before container starts).
    # Overwrites on reinstall.
    def create_init_files(init_files, reporter: nil)
      (init_files || []).each do |init|
        host_path = init[:host] || init['host']
        content = init[:content] || init['content']
        reporter&.call("Creating config #{host_path}...")
        Shell.run("mkdir -p #{Shellwords.escape(File.dirname(host_path))}")
        FileUtils.mkdir_p(STAGING_DIR)
        staged = File.join(STAGING_DIR, File.basename(host_path))
        File.write(staged, content)
        Shell.run("cp #{Shellwords.escape(staged)} #{Shellwords.escape(host_path)}")
      end
    end

    # Create volume directories with appropriate permissions.
    def create_volumes(volumes, user: nil, reporter: nil)
      (volumes || []).each do |mapping|
        host_path = mapping.is_a?(String) ? mapping.split(':').first : mapping.values.first
        next if host_path.start_with?('/var/run/')
        reporter&.call("Creating directory #{host_path}...")
        Shell.run("mkdir -p #{Shellwords.escape(host_path)}")
        Shell.run("chmod -R 777 #{Shellwords.escape(host_path)}")
        if user.present?
          reporter&.call("  Setting ownership to UID #{user}...")
          Shell.run("chown -R #{Shellwords.escape(user.to_s)}:#{Shellwords.escape(user.to_s)} #{Shellwords.escape(host_path)}")
        end
      end
    end

    # Pull a Docker image, streaming output via reporter.
    def pull_image(image, reporter: nil)
      reporter&.call("Pulling image #{image}...")
      IO.popen("sudo docker pull #{image} 2>&1") do |io|
        io.each_line { |line| reporter&.call("  #{line.chomp}") }
      end
      raise "Failed to pull image #{image}" unless $?.success?
      reporter&.call("  ✓ Pull complete")
    end

    # Build the docker create command and run it.
    # Returns the container name.
    def create_container(identifier:, image:, entry:, reporter: nil)
      container_name = "amahi-#{identifier}"

      # Remove old container
      Shell.run("docker rm -f #{Shellwords.escape(container_name)} 2>/dev/null")

      cmd_parts = ["sudo", "docker", "create", "--name", container_name, "--restart", "unless-stopped"]

      (entry[:ports] || {}).each do |container_port, host_port|
        cmd_parts += ["-p", "#{host_port}:#{container_port}"]
      end

      (entry[:volumes] || []).each do |mapping|
        if mapping.is_a?(String)
          cmd_parts += ["-v", mapping]
        else
          mapping.each { |cp, hp| cmd_parts += ["-v", "#{hp}:#{cp}"] }
        end
      end

      (entry[:init_files] || []).each do |init|
        host_path = init[:host] || init['host']
        container_path = init[:container] || init['container']
        next unless container_path.present?
        cmd_parts += ["-v", "#{host_path}:#{container_path}"]
      end

      (entry[:environment] || {}).each do |key, val|
        cmd_parts += ["-e", "#{key}=#{val}"]
      end

      (entry[:docker_args] || []).each do |arg|
        cmd_parts << arg.to_s
      end

      cmd_parts += ["-l", "amahi.managed=true", "-l", "amahi.app=#{identifier}"]
      cmd_parts << image

      reporter&.call("Creating container #{container_name}...")
      create_cmd = cmd_parts.map { |p| Shellwords.escape(p) }.join(' ')
      result = `#{create_cmd} 2>&1`
      reporter&.call("  #{result.strip}") if result.present?
      raise "Failed to create container" unless $?.success?

      container_name
    end

    # Start a container by name.
    def start_container(container_name, reporter: nil)
      reporter&.call("Starting container...")
      Shell.run("docker start #{container_name} 2>/dev/null")
    end
  end
end
