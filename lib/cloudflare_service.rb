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
      # systemctl is-active doesn't need sudo — don't use Shell.run
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
        # Download key then pipe to sudo gpg (matching sudoers entry exactly)
        result = system("curl -fsSL #{GPG_URL} | sudo gpg --dearmor -o #{KEYRING_PATH} 2>&1")
        raise CloudflareError, 'Failed to add Cloudflare signing key' unless result
      end

      unless File.exist?(SOURCES_PATH)
        # Use tee with sudo (matching sudoers entry)
        result = system("echo '#{REPO_LINE}' | sudo tee #{SOURCES_PATH} > /dev/null 2>&1")
        raise CloudflareError, 'Failed to add Cloudflare apt source' unless result
      end

      Shell.run('apt-get update')

      result = Shell.run('DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared')
      raise CloudflareError, 'Failed to install cloudflared package' unless result

      true
    end

    # Hold a token entered on the Remote Access page until the setup stream picks it up,
    # so it travels in a POST body rather than the stream's URL (and the logs).
    def stage_token(token)
      path = staged_token_path
      FileUtils.rm_f(path)
      File.write(path, token.to_s.strip, perm: 0600)
    end

    # The staged token, removed as it's read; nil if none was staged.
    def take_staged_token
      path = staged_token_path
      return nil unless File.exist?(path)
      File.read(path).strip.presence
    ensure
      FileUtils.rm_f(path) if path
    end

    def staged_token_path
      File.join(AMAHI_TMP_DIR, 'pending-tunnel.token')
    end

    def configure!(token)
      return true unless production?

      # The token only lives in TOKEN_FILE, readable by root alone; cloudflared reads it
      # with --token-file. It used to sit in the world-readable unit file and on
      # cloudflared's command line, where any account on the NAS could see it.
      tmp_path = File.join(AMAHI_TMP_DIR, 'tunnel.token')
      FileUtils.mkdir_p(File.dirname(tmp_path))
      FileUtils.rm_f(tmp_path)
      File.write(tmp_path, token.strip, perm: 0600)
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
        ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token-file #{TOKEN_FILE}
        Restart=on-failure
        RestartSec=5s
        TimeoutStartSec=0
        LimitNOFILE=65536

        [Install]
        WantedBy=multi-user.target
      UNIT

      tmp_path = File.join(AMAHI_TMP_DIR, 'cloudflared.service')
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
