# Docker Engine: installed and started through the root helper. Docker itself (the
# `docker` command the app pages run) keeps its sudo rule until Phase 4.
class DockerService
  class DockerError < StandardError; end

  PACKAGES = %w[docker-ce docker-ce-cli containerd.io].freeze

  class << self
    def installed?
      return false unless production?
      output = `dpkg-query -W -f='${Status}' docker-ce 2>/dev/null`.strip
      return true if output == 'install ok installed'
      output = `dpkg-query -W -f='${Status}' docker.io 2>/dev/null`.strip
      output == 'install ok installed'
    end

    def running?
      return false unless production?
      # Use docker info instead of systemctl — avoids sudoers restrictions
      system('docker info > /dev/null 2>&1')
    end

    def enabled?
      installed? && running?
    end

    def status
      return dummy_status unless production?
      {
        installed: installed?,
        running: running?,
        version: version
      }
    end

    def version
      return 'Docker 24.0.7 (stub)' unless production?
      return nil unless installed?
      `docker --version 2>/dev/null`.strip
    end

    # Installs Docker Engine from Docker's apt repository (key fingerprint pinned), lets
    # the app's user talk to it and starts it, all through the root helper. apt's output
    # goes to the block. Raises DockerError.
    def install!(&progress)
      return true unless production?
      progress&.call("Adding Docker's apt repository...")
      privileged('packages.add_repository', repository: 'docker')
      progress&.call('Installing Docker Engine...')
      privileged('packages.install', packages: PACKAGES) { |line| progress&.call("  #{line}") }
      progress&.call('Setting up user permissions...')
      privileged('docker.grant_app_user')
      progress&.call('Enabling and starting Docker...')
      privileged('services.enable', service: 'docker')
      true
    end

    def start!
      return true unless production?
      privileged('services.start', service: 'docker')
      true
    end

    def stop!
      return true unless production?
      privileged('services.stop', service: 'docker')
      true
    end

    def restart!
      return true unless production?
      privileged('services.restart', service: 'docker')
      true
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      raise DockerError, e.message
    end

    def dummy_status
      {
        installed: false,
        running: false,
        version: nil
      }
    end
  end
end
