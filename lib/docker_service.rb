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
      system('systemctl is-active --quiet docker')
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
        result = system("curl -fsSL #{GPG_URL} | sudo gpg --dearmor -o #{KEYRING_PATH}")
        raise DockerError, 'Failed to add Docker signing key' unless result
      end

      unless File.exist?(SOURCES_PATH)
        arch = `dpkg --print-architecture`.strip
        codename = `lsb_release -cs`.strip
        repo_line = "deb [arch=#{arch} signed-by=#{KEYRING_PATH}] https://download.docker.com/linux/ubuntu #{codename} stable"
        result = system("echo '#{repo_line}' | sudo tee #{SOURCES_PATH} > /dev/null")
        raise DockerError, 'Failed to add Docker apt source' unless result
      end

      system('sudo apt-get update')

      result = system('sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io')
      raise DockerError, 'Failed to install Docker packages' unless result

      system('sudo usermod -aG docker amahi')
      system('sudo systemctl enable docker')
      system('sudo systemctl start docker')

      true
    end

    def start!
      return true unless production?
      system('sudo systemctl start docker')
    end

    def stop!
      return true unless production?
      system('sudo systemctl stop docker')
    end

    def restart!
      return true unless production?
      system('sudo systemctl restart docker')
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
