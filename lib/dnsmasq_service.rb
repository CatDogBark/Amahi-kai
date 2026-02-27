# Manages dnsmasq DHCP/DNS service lifecycle and configuration.
# Extracted from NetworkController to keep Shell.run out of controllers.

require 'shell'

module DnsmasqService
  CONFIG_PATH = '/etc/dnsmasq.d/amahi.conf'
  STAGING_DIR = '/tmp/amahi-staging'

  class << self
    def installed?
      File.exist?('/usr/sbin/dnsmasq')
    end

    def running?
      installed? && `systemctl is-active dnsmasq 2>/dev/null`.strip == 'active'
    end

    def restart!
      Shell.run("systemctl restart dnsmasq.service")
    end

    def start!
      Shell.run("systemctl enable dnsmasq.service 2>/dev/null")
      Shell.run("systemctl start dnsmasq.service 2>/dev/null")
    end

    def stop!
      Shell.run("systemctl stop dnsmasq.service 2>/dev/null")
      Shell.run("systemctl disable dnsmasq.service 2>/dev/null")
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
      end

      if dns_enabled
        config_lines << "local=/#{domain}/"
        config_lines << "expand-hosts"
        config_lines << "domain=#{domain}"
      end

      config_lines << "bind-interfaces"
      config_lines << "except-interface=lo"

      FileUtils.mkdir_p(STAGING_DIR)
      staged = File.join(STAGING_DIR, 'dnsmasq-amahi.conf')
      File.write(staged, config_lines.join("\n") + "\n")
      Shell.run("cp #{staged} #{CONFIG_PATH}")

      restart! if running?
    end
  end
end
