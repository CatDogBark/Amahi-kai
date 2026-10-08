require 'open3'

# Docker Engine: installed and started through the root helper. The web app never talks to
# Docker itself: the helper runs the apps (apps.*, docs/plans/apps.md).
class DockerService
  class DockerError < StandardError; end

  PACKAGES = %w[docker-ce docker-ce-cli containerd.io].freeze

  class << self
    def installed?
      return false unless production?
      %w[docker-ce docker.io].any? { |package| SystemInfo.package_installed?(package) }
    end

    # Docker's service is up (systemctl answers any user; the web app can't reach Docker's
    # socket).
    def running?
      return false unless production?
      out, _err, _status = Open3.capture3('systemctl', 'is-active', 'docker')
      out.strip == 'active'
    rescue SystemCallError
      false
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
      Shell.output('docker', '--version').strip
    end

    # Installs Docker Engine from Docker's apt repository (key fingerprint pinned) and starts
    # it, through the root helper. apt's output goes to the block. Raises DockerError.
    def install!(&progress)
      return true unless production?
      progress&.call("Adding Docker's apt repository...")
      privileged('packages.add_repository', repository: 'docker')
      progress&.call('Installing Docker Engine...')
      privileged('packages.install', packages: PACKAGES) { |line| progress&.call("  #{line}") }
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
