require 'shell'

class DockerService
  class DockerError < StandardError; end

  KEYRING_PATH = '/usr/share/keyrings/docker-archive-keyring.gpg'
  SOURCES_PATH = '/etc/apt/sources.list.d/docker.list'
  GPG_URL = 'https://download.docker.com/linux/ubuntu/gpg'

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
      Shell.run('systemctl is-active --quiet docker')
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

    def install!
      return true unless production?

      unless File.exist?(KEYRING_PATH)
        result = Shell.run("sh -c 'curl -fsSL #{GPG_URL} | gpg --dearmor -o #{KEYRING_PATH}'")
        raise DockerError, 'Failed to add Docker signing key' unless result
      end

      unless File.exist?(SOURCES_PATH)
        arch = `dpkg --print-architecture`.strip
        codename = `lsb_release -cs`.strip
        repo_line = "deb [arch=#{arch} signed-by=#{KEYRING_PATH}] https://download.docker.com/linux/ubuntu #{codename} stable"
        result = Shell.run("sh -c \"echo '#{repo_line}' > #{SOURCES_PATH}\"")
        raise DockerError, 'Failed to add Docker apt source' unless result
      end

      Shell.run('apt-get update')

      result = Shell.run('DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io')
      raise DockerError, 'Failed to install Docker packages' unless result

      Shell.run('usermod -aG docker amahi')
      Shell.run('systemctl enable docker')
      Shell.run('systemctl start docker')

      true
    end

    def start!
      return true unless production?
      Shell.run('systemctl start docker')
    end

    def stop!
      return true unless production?
      Shell.run('systemctl stop docker')
    end

    def restart!
      return true unless production?
      Shell.run('systemctl restart docker')
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
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
