# Manages Tailscale VPN service lifecycle.
# No domain required — mesh VPN via Tailscale's coordination server.

require 'shell'
require 'json'

module TailscaleService
  class << self
    def installed?
      File.exist?('/usr/bin/tailscale')
    end

    def running?
      return false unless installed?
      status = `tailscale status --json 2>/dev/null`.strip
      return false if status.empty?
      data = JSON.parse(status)
      data['BackendState'] == 'Running'
    rescue JSON::ParserError, StandardError
      false
    end

    def status
      return { installed: false, running: false } unless installed?

      raw = `tailscale status --json 2>/dev/null`.strip
      return { installed: true, running: false } if raw.empty?

      data = JSON.parse(raw)
      backend_state = data['BackendState']
      self_node = data.dig('Self')

      result = {
        installed: true,
        running: backend_state == 'Running',
        state: backend_state,
        tailscale_ip: self_node&.dig('TailscaleIPs')&.first,
        hostname: self_node&.dig('DNSName')&.chomp('.'),
        os: self_node&.dig('OS'),
        online: self_node&.dig('Online'),
        peers: (data['Peer'] || {}).size
      }

      # MagicDNS hostname (e.g., amahi-kai.tail1234.ts.net)
      if result[:hostname].present?
        result[:magic_dns] = result[:hostname]
      end

      result
    rescue JSON::ParserError, StandardError => e
      { installed: true, running: false, error: e.message }
    end

    def install!
      # Official Tailscale install script — download then run with sudo bash
      script_path = '/tmp/tailscale-install.sh'
      system("curl -fsSL https://tailscale.com/install.sh -o #{script_path} 2>&1")
      return false unless $?.success? && File.exist?(script_path)

      # Run as root so the script's internal sudo/apt calls work without a terminal
      success = system("sudo bash #{script_path} 2>&1")
      FileUtils.rm_f(script_path)
      success
    end

    # Start Tailscale and return the auth URL if not yet authenticated.
    # Returns { success: true, auth_url: nil } if already authenticated.
    # Returns { success: true, auth_url: "https://..." } if auth needed.
    def start!
      # Try starting the daemon
      Shell.run("systemctl enable tailscaled 2>/dev/null")
      Shell.run("systemctl start tailscaled 2>/dev/null")

      # Check if already logged in — if so, just bring it up
      status_check = `tailscale status 2>&1`.strip
      needs_login = status_check.include?('Logged out') || status_check.include?('NeedsLogin')

      if needs_login
        # Request a login URL without blocking
        output = `timeout 15 tailscale login 2>&1`.strip
        auth_url = output[/https:\/\/login\.tailscale\.com\/[^\s]+/]
        return { success: true, auth_url: auth_url, needs_login: true }
      end

      # Already authenticated — just bring it up
      `timeout 10 tailscale up 2>&1`
      { success: true, auth_url: nil }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def stop!
      Shell.run("tailscale down 2>/dev/null")
    end

    def logout!
      Shell.run("tailscale logout 2>/dev/null")
      Shell.run("systemctl stop tailscaled 2>/dev/null")
    end
  end
end
