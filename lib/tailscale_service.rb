# Tailscale VPN. Installing it and changing its state go through the root helper:
# packages.add_repository and packages.install (Tailscale's apt repository, key fingerprint
# pinned; it replaces the downloaded install script run as root), tailscale.start (the
# daemon), tailscale.up, tailscale.down and tailscale.logout. Reading its status needs no
# root.

require 'json'
require 'open3'

module TailscaleService
  class TailscaleError < StandardError; end

  BINARY = '/usr/bin/tailscale'
  LOGIN_URL = %r{https://login\.tailscale\.com/\S+}

  class << self
    def installed?
      File.exist?(BINARY)
    end

    def running?
      status_data&.dig('BackendState') == 'Running'
    end

    def status
      return { installed: false, running: false } unless installed?

      data = status_data
      return { installed: true, running: false } unless data

      backend_state = data['BackendState']
      self_node = data['Self']

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
      result[:magic_dns] = result[:hostname] if result[:hostname].present?

      result
    end

    # Installs Tailscale from its apt repository and starts the daemon; apt's output goes
    # to the block. Raises TailscaleError.
    def install!(&progress)
      privileged('packages.add_repository', repository: 'tailscale')
      privileged('packages.install', packages: ['tailscale']) { |line| progress&.call(line) }
      privileged('tailscale.start')
      true
    end

    # Starts the daemon and brings Tailscale up. `tailscale up` prints a login URL when
    # this device isn't in a tailnet yet; its output goes to the block.
    # Returns { success: true, auth_url: "https://..." or nil } or { success: false, error: }.
    def start!(&progress)
      privileged('tailscale.start')
      return { success: true, auth_url: nil } if running?

      auth_url = nil
      privileged('tailscale.up') do |line|
        auth_url ||= line[LOGIN_URL]
        progress&.call(line)
      end
      { success: true, auth_url: auth_url }
    rescue TailscaleError => e
      { success: false, error: e.message }
    end

    def stop!
      privileged('tailscale.down')
      true
    rescue TailscaleError
      false
    end

    def logout!
      privileged('tailscale.logout')
      true
    rescue TailscaleError
      false
    end

    private

    # `tailscale status --json`, which any user may read; nil if it can't be read.
    def status_data
      return nil unless installed?
      out, _err, status = Open3.capture3(BINARY, 'status', '--json')
      return nil unless status.success? && out.present?
      JSON.parse(out)
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      Rails.logger.error("Tailscale: #{operation} failed: #{e.message}")
      raise TailscaleError, e.message
    end
  end
end
