require 'shell'

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
      Shell.run('systemctl is-active --quiet cloudflared')
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
        result = Shell.run("sh -c 'curl -L #{GPG_URL} | gpg --dearmor -o #{KEYRING_PATH}'")
        raise CloudflareError, 'Failed to add Cloudflare signing key' unless result
      end

      unless File.exist?(SOURCES_PATH)
        result = Shell.run("sh -c \"echo '#{REPO_LINE}' > #{SOURCES_PATH}\"")
        raise CloudflareError, 'Failed to add Cloudflare apt source' unless result
      end

      Shell.run('apt-get update')

      result = Shell.run('DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared')
      raise CloudflareError, 'Failed to install cloudflared package' unless result

      true
    end

    def configure!(token)
      return true unless production?

      # Write token to temp, then copy to secure location
      tmp_path = '/var/hda/tmp/tunnel.token'
      FileUtils.mkdir_p(File.dirname(tmp_path))
      File.write(tmp_path, token.strip)
      Shell.run("mkdir -p #{File.dirname(TOKEN_FILE)}")
      Shell.run("cp #{tmp_path} #{TOKEN_FILE}")
      FileUtils.rm_f(tmp_path)

      # Write systemd unit file directly (avoids cloudflared service install TTY issues)
      unit = <<~UNIT
        [Unit]
        Description=Cloudflare Tunnel
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=notify
        ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token #{token.strip}
        Restart=on-failure
        RestartSec=5s
        TimeoutStartSec=0
        LimitNOFILE=65536

        [Install]
        WantedBy=multi-user.target
      UNIT

      tmp_path = '/var/hda/tmp/cloudflared.service'
      File.write(tmp_path, unit)
      result = Shell.run("cp #{tmp_path} /etc/systemd/system/cloudflared.service")
      FileUtils.rm_f(tmp_path)
      raise CloudflareError, 'Failed to write cloudflared service file' unless result

      Shell.run('systemctl daemon-reload')
      Shell.run('systemctl enable cloudflared')

      true
    end

    def start!
      return true unless production?
      Shell.run('systemctl start cloudflared')
    end

    def stop!
      return true unless production?
      Shell.run('systemctl stop cloudflared')
    end

    def restart!
      return true unless production?
      Shell.run('systemctl restart cloudflared')
    end

    def token_configured?
      return true unless production?
      File.exist?(TOKEN_FILE) || ENV['CLOUDFLARE_TUNNEL_TOKEN'].present? || Shell.run('systemctl is-enabled --quiet cloudflared 2>/dev/null')
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
