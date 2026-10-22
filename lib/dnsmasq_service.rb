# Manages dnsmasq's DHCP service lifecycle and configuration.
# Extracted from NetworkController to keep the service handling out of controllers.
#
# dnsmasq answers no DNS (port=0): Unbound does that (DnsService, Network → DNS). It hands out
# the NAS as the DNS server while Unbound is on, and the router while it's off.
#
# The root helper writes the config (network.write_dnsmasq_config, only lines this
# module generates) and starts, stops and restarts the service (services.*).

module DnsmasqService
  CONFIG_PATH = '/etc/dnsmasq.d/amahi.conf'

  class << self
    def installed?
      File.exist?('/usr/sbin/dnsmasq')
    end

    def running?
      installed? && Shell.output('systemctl', 'is-active', 'dnsmasq').strip == 'active'
    end

    # The options write_config! takes, from the saved settings (Network → Gateway).
    def settings_options
      {
        net: Setting.get('net') || '192.168.1',
        dyn_lo: (Setting.get('dyn_lo') || '100').to_i,
        dyn_hi: (Setting.get('dyn_hi') || '254').to_i,
        gateway: Setting.get('gateway') || '1',
        lease_time: (Setting.get('lease_time') || '14400').to_i,
        dhcp_enabled: Setting.get('dnsmasq_dhcp') == '1'
      }
    end

    # Rewrites the config from the saved settings, for changes made elsewhere (static
    # hosts). Does nothing unless dnsmasq is installed.
    def rewrite_config!
      return false unless installed?

      write_config!(settings_options)
      true
    end

    # Restarts dnsmasq so it reads new settings; does nothing if it isn't running.
    # Returns true, or false with the reason logged.
    def restart!
      return true unless running?
      privileged('services.restart')
    end

    # Starts dnsmasq now and at boot.
    def start!
      privileged('services.enable')
    end

    # Stops dnsmasq now and at boot.
    def stop!
      privileged('services.disable')
    end

    # Write dnsmasq config and restart if running.
    # Options: net, dyn_lo, dyn_hi, gateway, lease_time, dhcp_enabled
    def write_config!(options = {})
      net = options[:net] || '192.168.1'
      dyn_lo = options[:dyn_lo].to_i
      dyn_hi = options[:dyn_hi].to_i
      gateway = options[:gateway] || '1'
      lease_time = options[:lease_time].to_i
      dhcp_enabled = options[:dhcp_enabled]

      config_lines = [
        "# Amahi-kai dnsmasq configuration",
        "# Auto-generated — do not edit manually",
        "",
        "port=0"
      ]

      if dhcp_enabled
        config_lines << "dhcp-range=#{net}.#{dyn_lo},#{net}.#{dyn_hi},#{lease_time}s"
        config_lines << "dhcp-option=option:router,#{net}.#{gateway}"
        config_lines << "dhcp-option=option:dns-server,#{dns_server(net, gateway)}"
        config_lines << "domain=#{DnsService.domain}" if DnsService.on?
        config_lines << "dhcp-authoritative"
        # Static addresses (Network → Hosts): this MAC always gets this address and name.
        Host.order(:name).each do |host|
          config_lines << "dhcp-host=#{host.mac.downcase},#{net}.#{host.address},#{host.name.downcase}"
        end
      end

      config_lines << "bind-interfaces"
      config_lines << "except-interface=lo"

      # Raises Privileged::Error with the reason if the helper refuses or fails.
      Privileged.call('network.write_dnsmasq_config', content: config_lines.join("\n") + "\n")
      restart!
    end

    private

    # The NAS while its DNS is on (and it has an address on DNS's interface), else the router.
    def dns_server(net, gateway)
      (DnsService.on? && DnsService.server_addresses.first) || "#{net}.#{gateway}"
    end

    def privileged(operation)
      Privileged.call(operation, service: 'dnsmasq')
      true
    rescue Privileged::Error => e
      Rails.logger.error("DnsmasqService: #{operation} failed: #{e.message}")
      false
    end
  end
end
