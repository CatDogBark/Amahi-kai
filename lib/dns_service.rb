# Amahi-kai's DNS server (Network → DNS, DHCP and Internet): Unbound, answering the LAN and Tailscale. Lookups go
# out over TLS to a provider the owner picks, answers are checked with DNSSEC, and the NAS, the
# fixed hosts and the DNS aliases have local names. The root helper installs the config
# (dns.write_config: only lines this module writes, checked with unbound-checkconf) and starts
# and stops Unbound (services.*). In the mode "DNS + DHCP", dnsmasq also hands out addresses
# on the same interface (DnsmasqService). docs/plans/networking.md has the design.
#
# The NAS itself keeps asking the DNS server it had (systemd-resolved, and the router behind it):
# if Unbound breaks, the NAS can still reach the internet to update itself.

require 'ipaddr'
require 'json'
require 'resolv'
require 'securerandom'
require 'socket'

module DnsService
  KIND = Setting::NETWORK
  UNBOUND = '/usr/sbin/unbound'
  PACKAGES = %w[unbound dns-root-data].freeze
  # Off; DNS for my network; DNS + DHCP; Router (DNS + DHCP, and the NAS between the LAN and the
  # internet).
  MODES = %w[off dns dns_dhcp router].freeze
  # What the root helper has in place while the NAS is the router (root writes it; anyone may read).
  ROUTER_STATE = '/var/lib/amahi-kai-dns/router.json'
  UFW_CONF = '/etc/ufw/ufw.conf'
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

  # The blocklists to choose from: the root helper downloads them (its BLOCKLISTS has their
  # addresses; a spec checks the keys match), every day, while blocking is on.
  BLOCKLISTS = {
    'hagezi-normal' => { name: 'HaGeZi Multi NORMAL', default: true,
                         about: "Ads, trackers and malware. Made for networks nobody watches over: sites rarely break. About 170,000 domains." },
    'hagezi-tif-mini' => { name: 'HaGeZi Threat Intelligence (mini)', default: true,
                           about: 'Malware, phishing and scam sites, the most active ones. About 210,000 domains.' },
    'hagezi-light' => { name: 'HaGeZi Multi LIGHT', default: false,
                        about: 'The worst ads and trackers only; next to nothing breaks. About 70,000 domains.' },
    'hagezi-pro' => { name: 'HaGeZi Multi PRO', default: false,
                      about: 'Stricter than NORMAL: more trackers, and now and then a site needs the allowlist. About 210,000 domains.' },
    'hagezi-tif-medium' => { name: 'HaGeZi Threat Intelligence (medium)', default: false,
                             about: 'More malware, phishing and scam sites than mini: about 710,000 domains. With NORMAL, ' \
                                    'Unbound needs about 370 MB of memory (about 160 MB with mini).' },
    'oisd-small' => { name: 'OISD small', default: false,
                      about: "Another project's list of the most common ads and trackers; rarely blocks too much. About 60,000 domains." },
    'oisd-big' => { name: 'OISD big', default: false,
                    about: "OISD's full list: ads, trackers, malware and phishing. It covers what HaGeZi NORMAL does, so pick one. " \
                           'About 240,000 domains.' },
    'hagezi-doh' => { name: 'Encrypted DNS providers', default: false,
                      about: "The known DNS-over-HTTPS services, so a device can't go around the NAS's DNS by name. Ticked for you " \
                             'while every device uses the NAS\'s DNS (Router). About 3,300 domains.' },
    'hagezi-native-samsung' => { name: 'Samsung TVs and phones', default: false, vendor: true,
                                 about: "Samsung's own telemetry hosts, with what its devices need left out. About 200 domains." },
    'hagezi-native-lgwebos' => { name: 'LG TVs (webOS)', default: false, vendor: true,
                                 about: "LG's own telemetry hosts, with what its TVs need left out. About 230 domains." },
    'hagezi-native-roku' => { name: 'Roku', default: false, vendor: true,
                              about: "Roku's own telemetry and ad-measurement hosts, with what its players need left out. About 60 domains." },
    'hagezi-native-amazon' => { name: 'Amazon devices (Fire TV, Echo, Kindle)', default: false, vendor: true,
                                about: "Amazon's own telemetry hosts, with what its devices need left out." },
    'hagezi-native-apple' => { name: 'Apple devices', default: false, vendor: true,
                               about: "Apple's own telemetry hosts, with what its devices need left out." },
    'hagezi-native-winoffice' => { name: 'Windows and Office', default: false, vendor: true,
                                   about: "Microsoft's telemetry hosts for Windows and Office, with what they need left out." },
    'hagezi-native-tiktok' => { name: 'TikTok', default: false, vendor: true,
                                about: "TikTok's tracking hosts, with what the app needs left out." },
    'hagezi-native-xiaomi' => { name: 'Xiaomi devices', default: false, vendor: true,
                                about: "Xiaomi's own telemetry hosts, with what its devices need left out." }
  }.freeze
  # The list the Router's "every device uses the NAS's DNS" adds.
  DOH_LIST = 'hagezi-doh'
  # What the helper found at its last refresh (root writes it; anyone may read it).
  BLOCKLIST_STATUS = '/var/lib/amahi-kai-dns/status.json'
  BLOCKLIST_SERVICE = 'amahi-kai-blocklists.service'
  # A name the allowlist may hold (the helper's BLOCK_DOMAIN).
  BLOCK_DOMAIN = /\A(?=.{4,253}\z)(?:[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]\z/
  ALLOWLIST_MAX = 1000

  # IPv6: the NAS can announce itself as the network's IPv6 DNS server (radvd), at an address of
  # its own in a unique local range (RFC 4193) it makes once, so it stays whatever the ISP hands out.
  RADVD = '/usr/sbin/radvd'
  RADVD_CONF = '/etc/radvd.conf'
  ULA_UNIT = '/etc/systemd/system/amahi-kai-ula.service'
  ULA_PREFIX = /\Afd[0-9a-f]{2}(?::[0-9a-f]{1,4}){2}\z/

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

    # dnsmasq hands out addresses too.
    def dhcp?
      %w[dns_dhcp router].include?(mode)
    end

    # The NAS is the router: between the LAN and the internet.
    def router?
      mode == 'router'
    end

    # The internet interface chosen for router mode, while the NAS has it.
    def wan_interface
      name = Setting.get('dns_wan_interface').presence
      name if name && NetworkInterfaces.lan.key?(name)
    end

    # The firewall is on (the security audit's fix); router mode needs it.
    def firewall_on?
      File.read(UFW_CONF).match?(/^ENABLED=yes$/)
    rescue SystemCallError
      false
    end

    # What the helper has in place: { 'lan', 'wan', 'forwards' }, or nil while the NAS isn't the
    # router.
    def router_state
      JSON.parse(File.read(ROUTER_STATE))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # The helper's router rules follow the LAN and internet interfaces and the port forwards.
    def apply_router!
      if on? && router? && wan_interface
        Privileged.call('network.router_on', **router_args)
      elsif router_state
        Privileged.call('network.router_off')
      end
    end

    # Rewrites the router's rules for a change made elsewhere (a port forward). Does nothing while
    # the NAS isn't the router.
    def rewrite_router!
      return false unless on? && router? && installed? && wan_interface

      Privileged.call('network.router_on', **router_args)
      true
    end

    def router_args
      { lan: interface, wan: wan_interface, forwards: PortForward.for_helper(lan_prefix),
        dns: (force_dns? ? server_addresses.first : nil) }
    end

    def tailscale_installed?
      File.exist?('/usr/bin/tailscale')
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

    # The NAS's IPv4 address on the interface, when its network is a /24: the one DHCP's range
    # and the fixed hosts' addresses are in. nil otherwise.
    def lan_address
      NetworkInterfaces.addresses(interface.to_s).find { |address| address.ipv4? && address.prefix == 24 }
    end

    # The first three parts of that address ("192.168.1"), or the net setting without one.
    def lan_prefix
      address = lan_address
      address ? address.to_s.split('.').first(3).join('.') : Setting.get('net').to_s
    end

    # The NAS announces itself as the IPv6 DNS server.
    def ipv6_advertise?
      Setting.get('dns_ipv6_advertise') == '1'
    end

    def radvd_installed?
      File.exist?(RADVD)
    end

    # The NAS's own unique local /48 ("fdab:cdef:1234"): made at random the first time, then kept.
    def ula_prefix
      saved = Setting.get('dns_ula_prefix').to_s
      return saved if saved.match?(ULA_PREFIX)

      prefix = "fd#{SecureRandom.hex(5)}".scan(/.{4}/).join(':')
      Setting.set('dns_ula_prefix', prefix, KIND)
      prefix
    end

    # The NAS's own IPv6 address for DNS ("fdab:cdef:1234::53"), on its own range's first /64.
    def own_ipv6_address
      IPAddr.new("#{ula_prefix}::53").to_s
    end

    def own_ipv6_network
      "#{IPAddr.new("#{ula_prefix}::")}/64"
    end

    # Where devices ask over IPv6: the NAS's own address while it announces it, else a unique
    # local address it has on the interface (from a router that hands one out), else nil.
    def ipv6_server_address
      return own_ipv6_address if ipv6_advertise?

      NetworkInterfaces.addresses(interface.to_s).find(&:ula?)&.to_s
    end

    def radvd_config
      <<~CONF
        # Amahi-kai (Network → DNS, DHCP and Internet): announces the NAS as the IPv6 DNS server, never as a router
        interface #{interface} {
          AdvSendAdvert on;
          AdvDefaultLifetime 0;
          prefix #{own_ipv6_network} {
            AdvOnLink on;
            AdvAutonomous on;
          };
          RDNSS #{own_ipv6_address} {
          };
          DNSSL #{domain} {
          };
        };
      CONF
    end

    # Asks the routers on the interface what they announce, and keeps the answer for the page.
    def check_routers!
      reply = Privileged.call('dns.check_routers', interface: interface)
      Setting.set('dns_ipv6_check', JSON.generate('checked_at' => Time.now.to_i, 'interface' => interface,
                                                  'advertisers' => reply['advertisers'] || []), KIND)
    end

    # The last check: { 'checked_at', 'interface', 'advertisers' => [{ 'router', 'lifetime',
    # 'prefixes', 'dns', 'domains' }] }, or nil.
    def ipv6_check
      JSON.parse(Setting.get('dns_ipv6_check').to_s)
    rescue JSON::ParserError
      nil
    end

    # The IPv6 DNS servers the routers announce that aren't the NAS: devices may ask those
    # instead, going around it. [[router, address]]
    def other_ipv6_dns(check = ipv6_check)
      own = [ipv6_server_address, *NetworkInterfaces.addresses(interface.to_s).reject(&:ipv4?).map(&:to_s)].compact
      Array(check&.dig('advertisers')).flat_map do |advert|
        Array(advert['dns']).reject { |address| own.include?(address) }.map { |address| [advert['router'], address] }
      end
    end

    # The name local names end in: the domain setting, unless it's .local (mDNS's).
    def domain
      value = Setting.get('domain').to_s.downcase
      value.match?(DOMAIN) && value != 'local' ? value : DEFAULT_DOMAIN
    end

    def config
      own = interface_addresses
      tailscale = NetworkInterfaces.addresses(NetworkInterfaces::TAILSCALE)
      lines = ['# Amahi-kai DNS (Network → DNS, DHCP and Internet): written by Amahi-kai, changes here are lost', 'server:']
      lines.concat(listening(own, tailscale).map { |address| "  interface: #{address}" })
      lines << '  ip-freebind: yes'
      lines.concat(allowed(own, tailscale).map { |network| "  access-control: #{network} allow" })
      lines.concat(['  hide-identity: yes', '  hide-version: yes', '  qname-minimisation: yes', '  prefetch: yes',
                    # Counts of DNSSEC's answers too, for the page's totals (no names, no devices).
                    '  extended-statistics: yes',
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

    # Writes the config and starts (or restarts) Unbound with blocking as chosen, or stops it and
    # removes the config (blocking too); then dnsmasq starts handing out addresses, or stops; then
    # the router's rules go in, or out. Raises Privileged::Error with the
    # reason if the helper refuses or fails.
    def apply!
      if on?
        Privileged.call('dns.set_own_address', interface: interface, address: own_ipv6_address) if ipv6_advertise?
        Privileged.call('dns.write_config', content: config)
        Privileged.call(running? ? 'services.restart' : 'services.enable', service: 'unbound')
        apply_blocking!
      elsif installed?
        Privileged.call('services.disable', service: 'unbound')
        Privileged.call('dns.remove_config')
      end
      apply_ipv6_advertising!
      DnsmasqService.apply!
      apply_router!
    end

    # radvd announces the NAS while DNS is on and that's chosen; otherwise it stops, and the NAS's
    # own address goes. (Nothing to undo where neither was ever set up.)
    def apply_ipv6_advertising!
      if on? && ipv6_advertise?
        Privileged.call('dns.write_radvd_config', content: radvd_config)
        Privileged.call(radvd_running? ? 'services.restart' : 'services.enable', service: 'radvd')
      else
        if radvd_installed? && File.exist?(RADVD_CONF)
          Privileged.call('services.disable', service: 'radvd')
          Privileged.call('dns.remove_radvd_config')
        end
        Privileged.call('dns.remove_own_address') if File.exist?(ULA_UNIT)
      end
    end

    def radvd_running?
      radvd_installed? && Shell.output('systemctl', 'is-active', 'radvd').strip == 'active'
    end

    # Rewrites the config for changes made elsewhere (fixed hosts, DNS aliases). Does nothing
    # while DNS is off.
    def rewrite!
      return false unless on? && installed?

      Privileged.call('dns.write_config', content: config)
      Privileged.call('services.restart', service: 'unbound') if running?
      true
    end

    # Blocking, while DNS is on: the lists chosen and the allowlist go to the helper, which
    # downloads the lists in the background; or blocking stops.
    def apply_blocking!
      if blocking?
        Privileged.call('dns.set_blocklists', lists: blocklists_in_force, allow: allowlist)
      else
        Privileged.call('dns.blocking_off')
      end
    end

    # The lists chosen, plus the encrypted-DNS providers while every device uses the NAS's DNS.
    def blocklists_in_force
      lists = blocklists
      lists |= [DOH_LIST] if router? && force_dns?
      lists
    end

    # Router mode: lookups devices send elsewhere come to the NAS, and their own encrypted DNS
    # doesn't get out. On unless turned off.
    def force_dns?
      Setting.get('dns_force_nas') != '0'
    end

    def blocking?
      Setting.get('dns_blocking') == '1'
    end

    # The lists chosen; those ticked by default until a choice is saved.
    def blocklists
      saved = Setting.get('dns_blocklists')
      return BLOCKLISTS.select { |_key, list| list[:default] }.keys if saved.nil?

      saved.split & BLOCKLISTS.keys
    end

    def allowlist
      Setting.get('dns_allowlist').to_s.split
    end

    # The allowlist from what was typed (a domain a line, or separated by spaces or commas; a
    # leading "*." or a final dot is let go), and why it can't be used ([] when it can).
    def parse_allowlist(text)
      names = text.to_s.downcase.split(/[\s,]+/).map { |name| name.delete_prefix('*.').delete_suffix('.') }.reject(&:empty?).uniq
      bad = names.grep_v(BLOCK_DOMAIN)
      problems = []
      problems << "#{bad.first(3).join(', ')} #{bad.one? ? "isn't a domain" : "aren't domains"}" if bad.any?
      problems << "The allowlist holds at most #{ALLOWLIST_MAX} domains" if names.size > ALLOWLIST_MAX
      [names, problems]
    end

    # The helper's last refresh: when, how many domains, and each list's count or error. nil
    # before the first.
    def blocking_status
      JSON.parse(File.read(BLOCKLIST_STATUS))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    def blocklists_refreshing?
      Shell.output('systemctl', 'is-active', BLOCKLIST_SERVICE).strip == 'activating'
    end

    # When a pause ends, while blocking is paused; else nil.
    def paused_until
      time = Setting.get('dns_blocking_paused_until').to_i
      Time.at(time) if time > Time.now.to_i
    end

    # Unbound's totals (the helper's dns.stats): { 'since', 'queries', 'answered_here', 'secure',
    # 'bogus' }, or nil when they can't be read.
    def totals
      reply = Privileged.call('dns.stats')
      reply if reply['queries']
    rescue Privileged::Error
      nil
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

    # The interface's addresses, but the NAS's own announced range only while it announces it:
    # when announcing stops, the address leaves the interface only after this config is written.
    def interface_addresses
      addresses = NetworkInterfaces.addresses(interface.to_s)
      return addresses if ipv6_advertise?

      range = IPAddr.new(own_ipv6_network)
      addresses.reject { |address| address.ula? && range.include?(address.ip) }
    end

    # The NAS's own (127.0.0.1, ::1), the interface's IPv4 addresses and ULAs, the address it
    # announces (on the interface once its unit runs: ip-freebind lets Unbound start first), and
    # Tailscale's.
    def listening(own, tailscale)
      lan = own.select { |address| address.ipv4? || address.ula? }.map(&:to_s)
      lan << own_ipv6_address if ipv6_advertise?
      (%w[127.0.0.1 ::1] + lan + tailscale.reject(&:link_local?).map(&:to_s)).uniq
    end

    # The networks on the interface, and Tailscale's when it's on. (Unbound always answers the
    # NAS itself.)
    def allowed(own, tailscale)
      networks = own.reject(&:link_local?).map(&:network)
      networks << own_ipv6_network if ipv6_advertise?
      networks << 'fe80::/10' if own.any?(&:link_local?)
      networks.concat(NetworkInterfaces::TAILSCALE_NETS) if tailscale.any?
      networks.uniq
    end

    # Each name both as name.<domain> and on its own, first come first served: the NAS, then
    # the fixed hosts, then the DNS aliases. The NAS and the fixed hosts answer reverse lookups.
    def local_data(own)
      nas = own.select { |address| address.ipv4? || address.ula? }.map(&:to_s)
      nas << own_ipv6_address if ipv6_advertise?
      nas.uniq!
      records = {}
      add = lambda do |name, addresses, reverse|
        name = name.to_s.downcase
        next if records.key?(name) || !name.match?(LABEL) || name == 'localhost' || addresses.empty?
        records[name] = [addresses, reverse]
      end
      add.call(hostname, nas, true)
      net = lan_prefix
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
