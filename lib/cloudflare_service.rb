class CloudflareService
  class CloudflareError < StandardError; end

  CLOUDFLARED_CONFIG = '/etc/cloudflared/config.yml'
  TOKEN_FILE = '/etc/amahi-kai/tunnel.token'
  KEYRING_PATH = '/usr/share/keyrings/cloudflare-archive-keyring.gpg'
  SOURCES_PATH = '/etc/apt/sources.list.d/cloudflared.list'
  GPG_URL = 'https://pkg.cloudflare.com/cloudflare-main.gpg'
  REPO_LINE = "deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main"

  class << self
    def installed?
      return false unless production?
      output = `dpkg-query -W -f='${Status}' cloudflared 2>/dev/null`.strip
      output == 'install ok installed'
    end

    def running?
      return false unless production?
      system('systemctl is-active --quiet cloudflared')
    end

    def enabled?
      installed? && running?
    end

    def status
      return dummy_status unless production?
      {
        installed: installed?,
        running: running?,
        tunnel_url: tunnel_url,
        token_configured: token_configured?,
        connected_since: connected_since
      }
    end

    def tunnel_url
      return 'https://demo-tunnel.example.com' unless production?
      return nil unless running?
      output = `cloudflared tunnel info 2>/dev/null`.strip rescue nil
      return nil if output.nil? || output.empty?
      output[/https?:\/\/\S+/]
    end

    def connected_since
      return nil unless production?
      return nil unless running?
      output = `systemctl show cloudflared --property=ActiveEnterTimestamp 2>/dev/null`.strip rescue nil
      return nil if output.nil?
      timestamp = output.sub('ActiveEnterTimestamp=', '').strip
      timestamp.empty? ? nil : timestamp
    end

    def install!
      return true unless production?

      unless File.exist?(KEYRING_PATH)
        result = system("curl -L #{GPG_URL} | sudo gpg --dearmor -o #{KEYRING_PATH}")
        raise CloudflareError, 'Failed to add Cloudflare signing key' unless result
      end

      unless File.exist?(SOURCES_PATH)
        result = system("echo '#{REPO_LINE}' | sudo tee #{SOURCES_PATH} > /dev/null")
        raise CloudflareError, 'Failed to add Cloudflare apt source' unless result
      end

      system('sudo apt-get update')

      result = system('sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared')
      raise CloudflareError, 'Failed to install cloudflared package' unless result

      true
    end

    def configure!(token)
      return true unless production?

      # Write token to temp, then copy to secure location
      tmp_path = '/var/hda/tmp/tunnel.token'
      FileUtils.mkdir_p(File.dirname(tmp_path))
      File.write(tmp_path, token.strip)
      system("sudo cp #{tmp_path} #{TOKEN_FILE}")
      FileUtils.rm_f(tmp_path)

      # Install as systemd service with token
      result = system("sudo cloudflared service install #{Shellwords.escape(token.strip)}")
      raise CloudflareError, 'Failed to configure cloudflared service' unless result

      true
    end

    def start!
      return true unless production?
      system('sudo systemctl start cloudflared')
    end

    def stop!
      return true unless production?
      system('sudo systemctl stop cloudflared')
    end

    def restart!
      return true unless production?
      system('sudo systemctl restart cloudflared')
    end

    def token_configured?
      return true unless production?
      File.exist?(TOKEN_FILE) || ENV['CLOUDFLARE_TUNNEL_TOKEN'].present?
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end

    def dummy_status
      {
        installed: false,
        running: false,
        tunnel_url: nil,
        token_configured: false,
        connected_since: nil
      }
    end
  end
end
