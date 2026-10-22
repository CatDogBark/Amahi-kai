# Amahi-kai's DNS server (Network → DNS): Unbound, answering the LAN and Tailscale. Lookups go
# out over TLS to a provider the owner picks, answers are checked with DNSSEC, and the NAS, the
# fixed hosts and the DNS aliases have local names. The root helper installs the config
# (dns.write_config: only lines this module writes, checked with unbound-checkconf) and starts
# and stops Unbound (services.*). docs/plans/networking.md has the design.
#
# The NAS itself keeps asking the DNS server it had (systemd-resolved, and the router behind it):
# if Unbound breaks, the NAS can still reach the internet to update itself.

require 'ipaddr'
require 'resolv'
require 'socket'

module DnsService
  KIND = Setting::NETWORK
  UNBOUND = '/usr/sbin/unbound'
  PACKAGES = %w[unbound dns-root-data].freeze
  MODES = %w[off dns].freeze
  DEFAULT_DOMAIN = 'home.arpa'
  DEFAULT_PROVIDER = 'quad9'
  CA_CERTS = '/etc/ssl/certs/ca-certificates.crt'
  LABEL = /\A[a-z][a-z0-9-]{0,62}\z/
  DOMAIN = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  TLS_NAME = /\A[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\z/

  # Open, no account needed, DNS-over-TLS on port 853, DNSSEC checked. Addresses and TLS names
  # from each provider's own page, checked 2026-10-22; each answered over TLS in a test.
  PROVIDERS = {
    'quad9' => { name: 'Quad9', tls_name: 'dns.quad9.net',
                 addresses: %w[9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9],
                 about: 'Swiss nonprofit. Keeps no record of your address, and blocks known malware domains.' },
    'cloudflare' => { name: 'Cloudflare', tls_name: 'one.one.one.one',
                      addresses: %w[1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001],
                      about: 'Fast and widely used. Never stores your address on disk, and deletes its logs within 25 hours.' },
    'adguard' => { name: 'AdGuard DNS (unfiltered)', tls_name: 'unfiltered.adguard-dns.com',
                   addresses: %w[94.140.14.140 94.140.14.141 2a10:50c0::1:ff 2a10:50c0::2:ff],
                   about: "AdGuard's public service, without its blocking. Keeps no personal data." },
    'dnssb' => { name: 'DNS.SB', tls_name: 'dot.sb',
                 addresses: %w[185.222.222.222 45.11.45.11 2a09:: 2a11::],
                 about: 'Small independent service. Logs no lookups and no addresses.' }
  }.freeze

  # Answers from outside naming an address inside a home network are dropped (DNS rebinding:
  # a website reaching the devices in the house through its own name). Local names are exempt.
  PRIVATE_ADDRESSES = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 fd00::/8 fe80::/10 ::ffff:0:0/96].freeze
  # Firefox turns its own encrypted DNS off on networks whose DNS says this name doesn't exist,
  # so it uses the house's DNS.
  FIREFOX_CANARY = 'use-application-dns.net'

  class << self
    def installed?
      File.exist?(UNBOUND)
    end

    def running?
      installed? && Shell.output('systemctl', 'is-active', 'unbound').strip == 'active'
    end

    def mode
      value = Setting.get('dns_mode')
      MODES.include?(value) ? value : 'off'
    end

    def on?
      mode != 'off'
    end

    # 'quad9', a key of PROVIDERS, or 'custom'.
    def provider
      value = Setting.get('dns_provider')
      PROVIDERS.key?(value) || value == 'custom' ? value : DEFAULT_PROVIDER
    end

    def custom_addresses
      Setting.get('dns_custom_addresses').to_s.split
    end

    def custom_tls_name
      Setting.get('dns_custom_tls_name').to_s
    end

    # [[address, TLS name]] for the provider in use.
    def upstream
      if provider == 'custom'
        custom_addresses.map { |address| [address, custom_tls_name] }
      else
        entry = PROVIDERS.fetch(provider)
        entry[:addresses].map { |address| [address, entry[:tls_name]] }
      end
    end

    # Why the custom provider can't be used ([] when it can): 1 to 4 addresses and a TLS name.
    def custom_problems(addresses, tls_name)
      problems = []
      list = addresses.to_s.split(/[\s,]+/).reject(&:empty?)
      problems << 'Give one to four addresses' unless list.size.between?(1, 4)
      bad = list.reject { |address| ip_address?(address) }
      problems << "#{bad.join(', ')} #{bad.one? ? "isn't an address" : "aren't addresses"}" if bad.any?
      problems << 'Give the TLS name its certificate is for (like dns.quad9.net)' unless tls_name.to_s.strip.downcase.match?(TLS_NAME)
      problems
    end

    # The interface DNS serves: the one chosen, while it's still there, or the one the default
    # route leaves by.
    def interface
      name = Setting.get('dns_interface').presence
      name && NetworkInterfaces.lan.key?(name) ? name : NetworkInterfaces.default_name
    end

    # The NAS's IPv4 addresses on that interface: what devices are pointed at.
    def server_addresses
      NetworkInterfaces.addresses(interface.to_s).select(&:ipv4?).map(&:to_s)
    end

    # The name local names end in: the domain setting, unless it's .local (mDNS's).
    def domain
      value = Setting.get('domain').to_s.downcase
      value.match?(DOMAIN) && value != 'local' ? value : DEFAULT_DOMAIN
    end

    def config
      own = NetworkInterfaces.addresses(interface.to_s)
      tailscale = NetworkInterfaces.addresses(NetworkInterfaces::TAILSCALE)
      lines = ['# Amahi-kai DNS (Network → DNS): written by Amahi-kai, changes here are lost', 'server:']
      lines.concat(listening(own, tailscale).map { |address| "  interface: #{address}" })
      lines << '  ip-freebind: yes'
      lines.concat(allowed(own, tailscale).map { |network| "  access-control: #{network} allow" })
      lines.concat(['  hide-identity: yes', '  hide-version: yes', '  qname-minimisation: yes', '  prefetch: yes',
                    # Answers past their time are still given (and refreshed) if the provider can't
                    # be reached: names keep working through a short outage.
                    '  serve-expired: yes', '  serve-expired-ttl: 86400', '  serve-expired-client-timeout: 1800'])
      lines.concat(PRIVATE_ADDRESSES.map { |network| "  private-address: #{network}" })
      lines << %(  local-zone: "#{domain}." static)
      lines.concat(local_data(own))
      lines << %(  local-zone: "#{FIREFOX_CANARY}." always_nxdomain)
      lines << %(  tls-cert-bundle: "#{CA_CERTS}")
      lines.concat(['forward-zone:', '  name: "."', '  forward-tls-upstream: yes'])
      lines.concat(upstream.map { |address, name| "  forward-addr: #{address}@853##{name}" })
      "#{lines.join("\n")}\n"
    end

    # Writes the config and starts (or restarts) Unbound, or stops it and removes the config.
    # dnsmasq hands out the NAS as the DNS server while DNS is on, the router while it's off.
    # Raises Privileged::Error with the reason if the helper refuses or fails.
    def apply!
      if on?
        Privileged.call('dns.write_config', content: config)
        Privileged.call(running? ? 'services.restart' : 'services.enable', service: 'unbound')
      elsif installed?
        Privileged.call('services.disable', service: 'unbound')
        Privileged.call('dns.remove_config')
      end
      DnsmasqService.rewrite_config!
    end

    # Rewrites the config for changes made elsewhere (fixed hosts, DNS aliases). Does nothing
    # while DNS is off.
    def rewrite!
      return false unless on? && installed?

      Privileged.call('dns.write_config', content: config)
      Privileged.call('services.restart', service: 'unbound') if running?
      true
    end

    # Asks Unbound for the NAS's own name and for an outside one:
    # { local: milliseconds or nil, outside: milliseconds or nil }.
    def check(timeout: 2)
      resolver = Resolv::DNS.new(nameserver_port: [['127.0.0.1', 53]])
      resolver.timeouts = timeout
      { local: timed { resolver.getaddress("#{hostname}.#{domain}") }, outside: timed { resolver.getaddress('example.com') } }
    ensure
      resolver&.close
    end

    # The NAS's name, without a domain ("kai").
    def hostname
      Socket.gethostname.split('.').first.to_s.downcase
    end

    private

    # The NAS's own (127.0.0.1, ::1), the interface's IPv4 addresses and ULAs, and Tailscale's.
    def listening(own, tailscale)
      lan = own.select { |address| address.ipv4? || address.ula? }
      (%w[127.0.0.1 ::1] + (lan + tailscale.reject(&:link_local?)).map(&:to_s)).uniq
    end

    # The networks on the interface, and Tailscale's when it's on. (Unbound always answers the
    # NAS itself.)
    def allowed(own, tailscale)
      networks = own.reject(&:link_local?).map(&:network)
      networks << 'fe80::/10' if own.any?(&:link_local?)
      networks.concat(NetworkInterfaces::TAILSCALE_NETS) if tailscale.any?
      networks.uniq
    end

    # Each name both as name.<domain> and on its own, first come first served: the NAS, then
    # the fixed hosts, then the DNS aliases. The NAS and the fixed hosts answer reverse lookups.
    def local_data(own)
      nas = own.select { |address| address.ipv4? || address.ula? }.map(&:to_s)
      records = {}
      add = lambda do |name, addresses, reverse|
        name = name.to_s.downcase
        next if records.key?(name) || !name.match?(LABEL) || name == 'localhost' || addresses.empty?
        records[name] = [addresses, reverse]
      end
      add.call(hostname, nas, true)
      net = Setting.get('net')
      Host.order(:name).each { |host| add.call(host.name, ["#{net}.#{host.address}"], true) } if net.present?
      DnsAlias.order(:name).each do |entry|
        add.call(entry.name, entry.address.present? ? [entry.address.strip] : nas, false)
      end
      records.flat_map do |name, (addresses, reverse)|
        addresses.select { |address| ip_address?(address) }.flat_map do |address|
          type = IPAddr.new(address).ipv4? ? 'A' : 'AAAA'
          lines = ["#{name}.#{domain}.", "#{name}."].map { |fqdn| %(  local-data: "#{fqdn} IN #{type} #{address}") }
          lines << %(  local-data-ptr: "#{address} #{name}.#{domain}.") if reverse
          lines
        end
      end
    end

    def ip_address?(value)
      value.match?(/\A[0-9a-f.:]{2,39}\z/i) && IPAddr.new(value) && true
    rescue IPAddr::Error
      false
    end

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    rescue Resolv::ResolvError, Resolv::ResolvTimeout, SystemCallError
      nil
    end
  end
end
