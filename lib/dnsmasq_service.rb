# dnsmasq hands out addresses (DHCP) while Network → DNS & DHCP is in the mode "DNS + DHCP",
# on the interface DNS serves, and nowhere else. It answers no DNS (port=0): Unbound does that
# (DnsService), and dnsmasq hands out the NAS as the DNS server.
#
# The root helper writes the config (network.write_dnsmasq_config, only lines this module
# generates; it also lets DHCP through the firewall on that interface, and gives the devices'
# names to Unbound) and starts, stops and restarts the service (services.*).

module DnsmasqService
  CONFIG_PATH = '/etc/dnsmasq.d/amahi.conf'
  PACKAGES = %w[dnsmasq].freeze
  # How long a device keeps its address before it asks again.
  LEASE_TIMES = { '1 hour' => 3600, '4 hours' => 14_400, '12 hours' => 43_200, '1 day' => 86_400, '1 week' => 604_800 }.freeze
  DEFAULT_LEASE_TIME = 14_400
  # The fewest addresses a range may hold.
  MIN_RANGE = 10

  class << self
    def installed?
      File.exist?('/usr/sbin/dnsmasq')
    end

    def running?
      installed? && Shell.output('systemctl', 'is-active', 'dnsmasq').strip == 'active'
    end

    # The saved DHCP settings: the range's first and last addresses and the router's (the last
    # part of each), and the lease time in seconds.
    def settings
      { first: (Setting.get('dyn_lo') || '100').to_i, last: (Setting.get('dyn_hi') || '254').to_i,
        router: (Setting.get('gateway') || '1').to_i, lease_time: (Setting.get('lease_time') || DEFAULT_LEASE_TIME).to_i }
    end

    # Why these DHCP settings can't be used ([] when they can), on a network where the NAS is
    # +own+ (the last part of its address).
    def settings_problems(first, last, router, lease_time, own)
      problems = []
      problems << 'The range runs from 2 to 254, first to last' unless first.between?(2, 254) && last.between?(2, 254) && first < last
      problems << "The range needs at least #{MIN_RANGE} addresses" if last - first + 1 < MIN_RANGE
      problems << "The range takes in the NAS's own address (.#{own})" if own && own.between?(first, last)
      problems << "The router's address is 1 to 254" unless router.between?(1, 254)
      problems << 'Choose a lease time' unless LEASE_TIMES.value?(lease_time)
      problems
    end

    # The options write_config! takes, from the saved settings and DNS's mode and interface. While
    # the NAS is the router, devices are given the NAS as their router, not the Router setting.
    def options
      settings.merge(net: DnsService.lan_prefix, interface: DnsService.interface, dhcp_enabled: DnsService.dhcp?,
                     router_is_nas: DnsService.router?)
    end

    # Writes the config, and starts dnsmasq while it hands out addresses or stops it otherwise.
    # Does nothing unless dnsmasq is installed. Raises Privileged::Error with the reason.
    def apply!
      return false unless installed?

      write_config!(options)
      if DnsService.dhcp?
        Privileged.call('services.enable', service: 'dnsmasq') unless running?
      else
        Privileged.call('services.disable', service: 'dnsmasq')
      end
      true
    end

    # Rewrites the config from the saved settings, for changes made elsewhere (fixed hosts).
    # Does nothing unless dnsmasq is installed.
    def rewrite_config!
      return false unless installed?

      write_config!(options)
      true
    end

    # The addresses of other DHCP servers answering on +interface+ (the helper asks, the way a
    # device would).
    def other_servers(interface)
      Privileged.call('dhcp.check_servers', interface: interface)['servers'] || []
    end

    # Write dnsmasq config and restart if running.
    # Options: net, first, last, router, lease_time, interface, dhcp_enabled
    def write_config!(options = {})
      net = options[:net].presence || '192.168.1'

      config_lines = [
        "# Amahi-kai dnsmasq configuration",
        "# Auto-generated — do not edit manually",
        "",
        "port=0"
      ]

      if options[:dhcp_enabled] && options[:interface].present?
        config_lines << "interface=#{options[:interface]}"
        config_lines << "bind-interfaces"
        config_lines << "dhcp-range=#{net}.#{options[:first]},#{net}.#{options[:last]},#{options[:lease_time].to_i}s"
        config_lines << "dhcp-option=option:router,#{router_address(net, options)}"
        config_lines << "dhcp-option=option:dns-server,#{dns_server(net, options[:router])}"
        config_lines << "domain=#{DnsService.domain}"
        config_lines << "dhcp-authoritative"
        # Static addresses (Network → Hosts): this MAC always gets this address and name.
        Host.order(:name).each do |host|
          config_lines << "dhcp-host=#{host.mac.downcase},#{net}.#{host.address},#{host.name.downcase}"
        end
      else
        config_lines << "bind-interfaces"
        config_lines << "except-interface=lo"
      end

      # Raises Privileged::Error with the reason if the helper refuses or fails.
      Privileged.call('network.write_dnsmasq_config', content: config_lines.join("\n") + "\n")
      restart!
    end

    # Restarts dnsmasq so it reads new settings; does nothing if it isn't running.
    # Returns true, or false with the reason logged.
    def restart!
      return true unless running?
      privileged('services.restart')
    end

    private

    # The NAS itself while it's the router (and has an address on the LAN), else the Router setting.
    def router_address(net, options)
      (options[:router_is_nas] && DnsService.server_addresses.first) || "#{net}.#{options[:router]}"
    end

    # The NAS while its DNS is on (and it has an address on DNS's interface), else the router.
    def dns_server(net, router)
      (DnsService.on? && DnsService.server_addresses.first) || "#{net}.#{router}"
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
