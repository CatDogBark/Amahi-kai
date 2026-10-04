require 'shell'

# The Cloudflare Tunnel. Installing cloudflared, saving the token and controlling the
# service go through the root helper: packages.add_repository and packages.install
# (Cloudflare's apt repository, key fingerprint pinned), tunnel.configure (token in a
# root-only file, a unit the helper writes itself) and tunnel.start|stop|restart.
class CloudflareService
  class CloudflareError < StandardError; end

  TOKEN_FILE = '/etc/amahi-kai/tunnel.token'

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

    # Installs cloudflared from Cloudflare's apt repository; apt's output goes to the block.
    # Raises CloudflareError.
    def install!(&progress)
      return true unless production?
      privileged('packages.add_repository', repository: 'cloudflared')
      privileged('packages.install', packages: ['cloudflared']) { |line| progress&.call(line) }
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

    # Saves the token (only root can read it; cloudflared reads it with --token-file),
    # writes cloudflared's unit and (re)starts the tunnel. Raises CloudflareError.
    def configure!(token)
      return true unless production?
      privileged('tunnel.configure', token: token.to_s.strip)
      true
    end

    def start!
      service('tunnel.start')
    end

    def stop!
      service('tunnel.stop')
    end

    def restart!
      service('tunnel.restart')
    end

    def token_configured?
      return true unless production?
      File.exist?(TOKEN_FILE) || system('systemctl', 'is-enabled', '--quiet', 'cloudflared', err: File::NULL)
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      raise CloudflareError, e.message
    end

    # A service action; false (with the reason logged) if it failed.
    def service(operation)
      return true unless production?
      Privileged.call(operation)
      true
    rescue Privileged::Error => e
      Rails.logger.error("Cloudflare Tunnel: #{operation} failed: #{e.message}")
      false
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
