# Manages dnsmasq DHCP/DNS service lifecycle and configuration.
# Extracted from NetworkController to keep Shell.run out of controllers.
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
        domain: Setting.get('domain') || 'local',
        dhcp_enabled: Setting.get('dnsmasq_dhcp') == '1',
        dns_enabled: Setting.get('dnsmasq_dns') == '1'
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
    # Options: net, dyn_lo, dyn_hi, gateway, lease_time, domain, dhcp_enabled, dns_enabled
    def write_config!(options = {})
      net = options[:net] || '192.168.1'
      dyn_lo = options[:dyn_lo].to_i
      dyn_hi = options[:dyn_hi].to_i
      gateway = options[:gateway] || '1'
      lease_time = options[:lease_time].to_i
      domain = options[:domain] || 'local'
      dhcp_enabled = options[:dhcp_enabled]
      dns_enabled = options[:dns_enabled]

      config_lines = [
        "# Amahi-kai dnsmasq configuration",
        "# Auto-generated — do not edit manually",
        ""
      ]

      if dhcp_enabled
        config_lines << "dhcp-range=#{net}.#{dyn_lo},#{net}.#{dyn_hi},#{lease_time}s"
        config_lines << "dhcp-option=option:router,#{net}.#{gateway}"
        config_lines << "dhcp-authoritative"
        # Static addresses (Network → Hosts): this MAC always gets this address and name.
        Host.order(:name).each do |host|
          config_lines << "dhcp-host=#{host.mac.downcase},#{net}.#{host.address},#{host.name.downcase}"
        end
      end

      if dns_enabled
        config_lines << "local=/#{domain}/"
        config_lines << "expand-hosts"
        config_lines << "domain=#{domain}"
      end

      config_lines << "bind-interfaces"
      config_lines << "except-interface=lo"

      # Raises Privileged::Error with the reason if the helper refuses or fails.
      Privileged.call('network.write_dnsmasq_config', content: config_lines.join("\n") + "\n")
      restart!
    end

    private

    def privileged(operation)
      Privileged.call(operation, service: 'dnsmasq')
      true
    rescue Privileged::Error => e
      Rails.logger.error("DnsmasqService: #{operation} failed: #{e.message}")
      false
    end
  end
end
