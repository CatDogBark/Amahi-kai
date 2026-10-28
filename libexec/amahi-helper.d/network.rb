# frozen_string_literal: true

# The network: the hostname, the server's address, router mode and its firewall, port forwards,
# Tailscale and the Cloudflare Tunnel.
module AmahiHelper
  HOSTS = '/etc/hosts'

  # Router mode (Network → DNS, DHCP and Internet): the NAS between the LAN and the internet. The internet
  # interface gets its address by DHCP (WAN_NETPLAN), the kernel forwards, UFW's before.rules
  # get a NAT block (ROUTER_BEGIN..ROUTER_END: masquerade out, and the port forwards in), and
  # UFW's rules let the LAN out, the forwards in, and nothing else in on the internet side.
  # ROUTER_STATE holds what's in place, for the way back and for lan_subnets.
  NETPLAN = '/usr/sbin/netplan'

  # The netplan files as the helper last applied them (a digest): a save that changes none of
  # them doesn't apply them again. An apply has networkd set up every interface it manages
  # again, so the internet side asks its provider for its lease again and addresses networkd
  # didn't make (the NAS's own IPv6 one for DNS, ULA_UNIT) go.
  NETPLAN_APPLIED = "#{BLOCKLIST_DIR}/netplan-applied".freeze

  # The LAN interface's own default route (to the router the NAS replaces) goes behind the
  # internet interface's (50). Its netplan file is kept as it was, for the way back.
  LAN_ROUTE_METRIC = 200

  NETPLAN_BACKUP_SUFFIX = '.amahi-kai-before-router'

  ROUTER_SYSCTL = '/etc/sysctl.d/90-amahi-kai-router.conf'

  UFW_CONF = '/etc/ufw/ufw.conf'

  UFW_BEFORE_RULES = '/etc/ufw/before.rules'

  UFW_BEFORE6_RULES = '/etc/ufw/before6.rules'

  # The NAT block's rules live in chains of the NAS's own, which the block flushes before
  # refilling: UFW's reload re-reads before.rules without clearing the nat table, so rules put
  # straight in PREROUTING and POSTROUTING pile up, a copy per reload (found 2026-10-24: an old
  # copy kept redirecting DNS to the NAS's previous address).
  NAT_PREROUTING = 'amahi-kai-prerouting'

  NAT_POSTROUTING = 'amahi-kai-postrouting'

  # The block's filter part, in front of UFW's own before rules: those accept ICMP (pings among
  # them) ahead of any rule added through ufw, so a kept-off device could still ping out and
  # the NAS answered pings from the internet.
  ROUTER_FILTER_BEGIN = '# BEGIN amahi-kai router filter'

  ROUTER_FILTER_END = '# END amahi-kai router filter'

  # Service discovery (mDNS, SSDP), which UFW's before rules accept in from anywhere, for IPv4
  # and IPv6 (before6.rules gets a filter part of its own): dropped in on the internet side,
  # where Avahi would answer whoever shares the provider's network.
  DISCOVERY_PORTS = %w[5353 1900].freeze

  # The shape of the router's rules, kept in ROUTER_STATE: bumped whenever it changes, so the
  # app's resync after an update (DnsService.resync!) puts the new shape in place.
  ROUTER_RULES_VERSION = 4

  # The router's kernel settings besides forwarding, for all interfaces and for the internet
  # side: strict reverse-path filtering there (Ubuntu sets every interface loose, 2, and the
  # kernel takes the stricter of all and the interface's own, so all goes to 1 and only the
  # internet interface's own 1 bites); ICMP redirects neither taken nor sent there (a redirect
  # would move the NAS's routes; accepting is AND of all and the interface's while forwarding,
  # sending is OR, so both go to 0 on all as well); and martians, packets with an impossible
  # source, logged on the internet side.
  ROUTER_SYSCTL_ALL = { 'rp_filter' => '1', 'accept_redirects' => '0', 'send_redirects' => '0' }.freeze

  ROUTER_SYSCTL_WAN = { 'rp_filter' => '1', 'accept_redirects' => '0', 'send_redirects' => '0', 'log_martians' => '1' }.freeze

  PORT_FORWARD_MAX = 50

  # Devices kept off the internet (Network → Devices, LAN only), by address.
  LAN_ONLY_MAX = 200

  # Tailscale's own port: let in on the internet side so its connections stay direct.
  TAILSCALE_PORT = '41641'

  # The NAS's own address on an interface (Network → Devices, This NAS): the IPv4 part of the
  # interface's netplan entry is rewritten, automatic (DHCP) or a fixed address with its router
  # and DNS servers, each file changed kept as it was beside it (ADDRESS_BACKUP_SUFFIX). A change
  # to the interface the admin is connected through (guard) is applied ADDRESS_APPLY_WAIT seconds
  # after the reply, so the reply gets out, and kept only once something reaches the NAS at the
  # new address within ADDRESS_KEEP_WAIT seconds (network.keep_address); otherwise the revert
  # timer puts the files back. ADDRESS_STATE says where that stands.
  ADDRESS_STATE = "#{BLOCKLIST_DIR}/address.json".freeze

  ADDRESS_APPLY_UNIT = 'amahi-kai-address-apply'

  ADDRESS_REVERT_UNIT = 'amahi-kai-address-revert'

  # A change left waiting this long (the NAS rebooted meanwhile, and its timers with it) is
  # taken as kept: whoever asks for the next one reached the NAS as it is.
  ADDRESS_STALE = 600

  # Addresses an interface can't have.
  UNUSABLE_NETS = %w[0.0.0.0/8 127.0.0.0/8 224.0.0.0/3].map { |net| IPAddr.new(net) }.freeze

  # Cloudflare Tunnel: the token sits in a file only root can read, and cloudflared reads
  # it with --token-file, so it is in no unit file or command line.
  CLOUDFLARED = '/usr/bin/cloudflared'

  TUNNEL_TOKEN = '/etc/amahi-kai/tunnel.token'

  TUNNEL_TOKEN_FORMAT = %r{\A[A-Za-z0-9+/=_-]{32,4096}\z}

  TUNNEL_UNIT = '/etc/systemd/system/cloudflared.service'

  TUNNEL_UNIT_CONTENT = <<~UNIT
    [Unit]
    Description=Cloudflare Tunnel
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=notify
    ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token-file #{TUNNEL_TOKEN}
    Restart=on-failure
    RestartSec=5s
    TimeoutStartSec=0
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target
  UNIT

  # A port's light, to find it on the NAS (Network → Devices, This NAS).
  ETHTOOL = '/usr/sbin/ethtool'

  PRIVATE_NETS = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16].map { |net| IPAddr.new(net) }.freeze

  NOT_LAN_INTERFACES = /\A(lo|docker|br-|veth|tailscale)/

  # systemctl <verb> for one fixed unit, once its program is installed.
  def self.unit_operation(verb, unit, program)
    {
      params: [],
      validate: ->(_a) { installed!(program) && {} },
      plan: ->(_v) { [['/usr/bin/systemctl', verb, unit]] }
    }
  end


  add_operations(
    # The hostname, and the 127.0.1.1 line in /etc/hosts that names it (Ubuntu's way). Without
    # that line, sudo (the helper's own calls too) and anything else that looks up the
    # machine's name waits on DNS and warns "unable to resolve host".
    'network.set_hostname' => {
      params: %w[hostname],
      validate: ->(a) { { hostname: hostname(a['hostname']) } },
      plan: ->(v) { [['/usr/bin/hostnamectl', 'set-hostname', v[:hostname]], [:install, HOSTS, hosts_naming(v[:hostname]), nil]] }
    },
    # dnsmasq's DHCP settings (Network → DNS, DHCP and Internet), checked with dnsmasq --test. While it
    # hands out addresses, UFW lets DHCP in on its interface, and the devices' names go to
    # Unbound (dns.sync_leases).
    'network.write_dnsmasq_config' => {
      params: %w[content],
      validate: ->(a) { { content: dnsmasq_conf(a['content'], DNSMASQ_LINES) } },
      plan: ->(v) { [[:dnsmasq_config, v[:content]]] }
    },
    # Router mode on: +lan+ is the interface DNS and DHCP serve, +wan+ the internet's, +forwards+
    # the ports let in from the internet to devices. Needs UFW on (the security audit's firewall
    # fix): without it nothing would stand between the internet and the NAS's services.
    # +dns+: the NAS's own address on the LAN; lookups devices send elsewhere are redirected to
    # it and their encrypted DNS out is blocked (null: left alone).
    'network.router_on' => {
      params: %w[lan wan forwards dns lan_only],
      validate: lambda { |a|
        lan = network_interface(a['lan'])
        wan = network_interface(a['wan'])
        raise Refused, 'the LAN and the internet interfaces must differ' if lan == wan
        raise Refused, "the firewall must be on first (Network → Security, the firewall's Fix)" unless ufw_enabled?
        dns = a['dns']
        raise Refused, "#{dns.inspect} isn't an IPv4 address of the NAS's" unless dns.nil? || own_ipv4?(dns)
        installed!(NETPLAN) && { lan: lan, wan: wan, forwards: port_forwards(a['forwards']), dns: dns, lan_only: lan_only_addresses(a['lan_only']) }
      },
      plan: ->(v) { [[:router_on, v[:lan], v[:wan], v[:forwards], v[:dns], v[:lan_only]]] }
    },
    # What the internet side has dropped (Network → Internet).
    'network.wan_drops' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:wan_drops]] }
    },
    # +keep_lan+: DHCP stays on, so the LAN keeps the fixed address router mode gave it.
    'network.router_off' => {
      params: %w[keep_lan],
      validate: ->(a) { { keep_lan: a.key?('keep_lan') ? boolean(a, 'keep_lan') : false } },
      plan: ->(v) { [[:router_off, v[:keep_lan]]] }
    },
    # The NAS's own IPv4 address on an interface (Network → Devices, This NAS). +guard+: the
    # admin is connected through this interface, so the change is applied after the reply and
    # kept only once the NAS is reached at the new address (the three operations below).
    'network.set_address' => {
      params: %w[interface mode address gateway dns guard],
      validate: lambda { |a|
        interface = network_interface(a['interface'])
        raise Refused, "#{interface} isn't a LAN interface" if interface.match?(NOT_LAN_INTERFACES)
        if interface == read_json(ROUTER_STATE)&.dig('wan')
          raise Refused, "#{interface} is the internet side while the NAS is the router (Network → Internet)"
        end
        raise Refused, 'guard must be true or false' unless [true, false, nil].include?(a['guard'])
        values = { interface: interface, mode: listed(a['mode'], 'mode', %w[automatic fixed]), guard: a['guard'] == true }
        if values[:mode] == 'fixed'
          values[:address] = ipv4_cidr(a['address'])
          values[:gateway] = a['gateway'].nil? ? nil : ipv4_in(a['gateway'], 'gateway', values[:address])
          values[:dns] = dns_servers(a['dns'])
        end
        installed!(NETPLAN) && values
      },
      plan: ->(v) { [[:set_address, v[:interface], v[:mode], v[:address], v[:gateway], v[:dns] || [], v[:guard]]] }
    },
    'network.apply_address' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:apply_address]] }
    },
    'network.keep_address' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:keep_address]] }
    },
    'network.revert_address' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:revert_address]] }
    },
    # A port's light blinks for five seconds, to find its socket on the NAS.
    'network.blink_port' => {
      params: %w[interface],
      validate: ->(a) { installed!(ETHTOOL) && { interface: network_interface(a['interface']) } },
      plan: ->(v) { [[ETHTOOL, '--identify', v[:interface], '5']] }
    },
    # Saves the tunnel token (root-only file), writes cloudflared's unit, and (re)starts it.
    'tunnel.configure' => {
      params: %w[token],
      validate: ->(a) { installed!(CLOUDFLARED) && { token: tunnel_token(a['token']) } },
      plan: lambda { |v|
        [[:make_dir, File.dirname(TUNNEL_TOKEN), '0755'],
         [:install, TUNNEL_TOKEN, v[:token], nil, '0600'],
         [:install, TUNNEL_UNIT, TUNNEL_UNIT_CONTENT, nil],
         %w[/usr/bin/systemctl daemon-reload],
         %w[/usr/bin/systemctl enable cloudflared.service],
         %w[/usr/bin/systemctl restart cloudflared.service]]
      }
    },
    'tunnel.start' => unit_operation('start', 'cloudflared.service', CLOUDFLARED),
    'tunnel.stop' => unit_operation('stop', 'cloudflared.service', CLOUDFLARED),
    'tunnel.restart' => unit_operation('restart', 'cloudflared.service', CLOUDFLARED),
    # tailscaled on now and at boot.
    'tailscale.start' => {
      params: [],
      validate: ->(_a) { installed!(TAILSCALE) && {} },
      plan: ->(_v) { [%w[/usr/bin/systemctl enable --now tailscaled.service]] }
    },
    # `tailscale up`, given 10 seconds: enough to connect a logged-in node, or to print
    # the login URL (streamed) for one that isn't.
    'tailscale.up' => {
      params: [],
      validate: ->(_a) { installed!(TAILSCALE) && {} },
      plan: ->(_v) { [['/usr/bin/timeout', '10', TAILSCALE, 'up', { stream: true, allow_failure: true }]] }
    },
    'tailscale.down' => {
      params: [],
      validate: ->(_a) { installed!(TAILSCALE) && {} },
      plan: ->(_v) { [[TAILSCALE, 'down']] }
    },
    'tailscale.logout' => {
      params: [],
      validate: ->(_a) { installed!(TAILSCALE) && {} },
      plan: ->(_v) { [[TAILSCALE, 'logout', { allow_failure: true }], %w[/usr/bin/systemctl stop tailscaled.service]] }
    },
  )

  class << self
    # One DNS label (RFC 1123): letters, digits and hyphens, at most 63 characters.
    def hostname(value)
      value = string(value, 'hostname', max: 63)
      raise Refused, "hostname #{value.inspect} must be letters, digits and hyphens, not starting or ending with a hyphen" unless value.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/i)
      value
    end

    def ufw_enabled?
      File.executable?(UFW) && File.read(UFW_CONF).match?(/^ENABLED=yes$/)
    rescue SystemCallError
      false
    end

    # The port forwards: [{ protocol: 'tcp', port: 8080, address: '10.99.0.60', to_port: 80 }],
    # to devices on a private network only.
    def port_forwards(value)
      raise Refused, 'forwards must be a list' unless value.is_a?(Array)
      raise Refused, "at most #{PORT_FORWARD_MAX} port forwards" if value.size > PORT_FORWARD_MAX
      value.map do |forward|
        raise Refused, 'a forward must be an object' unless forward.is_a?(Hash)
        address = forward['address'].to_s
        raise Refused, "#{address.inspect} isn't an IPv4 address" unless ip_address?(address, :ipv4?)
        raise Refused, "#{address} isn't on a private network" unless PRIVATE_NETS.any? { |net| net.include?(IPAddr.new(address)) }
        { protocol: listed(forward['protocol'], 'protocol', %w[tcp udp]), port: port_number(forward['port'], 'port'),
          address: address, to_port: port_number(forward['to_port'], 'to_port') }
      end
    end

    # An IPv4 address this machine has.
    def own_ipv4?(value)
      value.is_a?(String) && ip_address?(value, :ipv4?) && Socket.getifaddrs.any? { |i| i.addr&.ipv4? && i.addr.ip_address == value }
    end

    # "192.168.1.10/24": an IPv4 address an interface can have, with its network's prefix length.
    def ipv4_cidr(value)
      value = string(value, 'address', max: 18)
      address, prefix = value.split('/', 2)
      unless ip_address?(address.to_s, :ipv4?) && prefix.to_s.match?(/\A\d{1,2}\z/) && prefix.to_i.between?(8, 30)
        raise Refused, "#{value.inspect} isn't an IPv4 address with its network's size (like 192.168.1.10/24)"
      end
      ip = IPAddr.new(address)
      raise Refused, "#{address} isn't an address an interface can have" if UNUSABLE_NETS.any? { |net| net.include?(ip) }
      network = ip.mask(prefix.to_i)
      raise Refused, "#{address} is the network's own address" if ip == network
      raise Refused, "#{address} is the network's broadcast address" if ip.to_i == network.to_i | (0xffffffff >> prefix.to_i)
      "#{ip}/#{prefix.to_i}"
    end

    # An IPv4 address on the network of +cidr+, other than its own address.
    def ipv4_in(value, what, cidr)
      value = string(value, what, max: 15)
      address, prefix = cidr.split('/')
      network = IPAddr.new(cidr)
      unless ip_address?(value, :ipv4?) && network.include?(IPAddr.new(value))
        raise Refused, "#{what} #{value.inspect} isn't an IPv4 address on #{network}/#{prefix}"
      end
      raise Refused, "#{what} #{value} is the NAS's own address" if value == address
      value
    end

    # The devices kept off the internet: up to LAN_ONLY_MAX private IPv4 addresses.
    def lan_only_addresses(value)
      value = [] if value.nil?
      raise Refused, "lan_only must be a list of up to #{LAN_ONLY_MAX} addresses" unless value.is_a?(Array) && value.size <= LAN_ONLY_MAX
      value.map do |address|
        unless address.is_a?(String) && ip_address?(address, :ipv4?) && PRIVATE_NETS.any? { |net| net.include?(IPAddr.new(address)) }
          raise Refused, "#{address.inspect} isn't a private IPv4 address"
        end
        address
      end.uniq
    end

    # Up to three IPv4 DNS servers.
    def dns_servers(value)
      value = [] if value.nil?
      raise Refused, 'dns must be a list of up to 3 IPv4 addresses' unless value.is_a?(Array) && value.size <= 3
      value.map do |server|
        raise Refused, "DNS server #{server.inspect} isn't an IPv4 address" unless server.is_a?(String) && ip_address?(server, :ipv4?)
        IPAddr.new(server).to_s
      end
    end

    def port_number(value, name)
      raise Refused, "#{name} must be a port number (1 to 65535)" unless value.is_a?(Integer) && value.between?(1, 65_535)
      value
    end

    # A network interface this machine has, by name ("ens18").
    def network_interface(value)
      value = string(value, 'interface', max: 15)
      raise Refused, "#{value.inspect} isn't a network interface here" unless value.match?(/\A#{IFNAME}\z/o) &&
                                                                          File.exist?("/sys/class/net/#{value}")
      value
    end

    # dnsmasq hands out addresses and answers no DNS (port=0): Unbound does, and without the
    # line dnsmasq would answer on port 53 too.
    def dnsmasq_conf(value, allowed)
      value = string(value, 'content', max: 64 * 1024)
      value.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        raise Refused, "dnsmasq line #{line.inspect} is not one Amahi-kai writes" unless allowed.any? { |re| line.match?(re) }
      end
      raise Refused, "dnsmasq's config must answer no DNS (port=0)" unless value.each_line.any? { |line| line.strip == 'port=0' }
      value
    end

    # A plain IPv4 or IPv6 address (+family+ :ipv4? or :ipv6?), with no prefix or zone.
    def ip_address?(value, family = nil)
      return false unless value.match?(/\A[0-9a-f.:]{2,39}\z/i)
      ip = IPAddr.new(value)
      family ? ip.public_send(family) : true
    rescue IPAddr::Error
      false
    end

    # /etc/hosts with its 127.0.1.1 line naming +name+, added after 127.0.0.1's when it has none.
    def hosts_naming(name)
      lines = (File.exist?(HOSTS) ? File.read(HOSTS) : "127.0.0.1 localhost\n").lines.map { |l| l.end_with?("\n") ? l : "#{l}\n" }
      line = "127.0.1.1 #{name}\n"
      if (i = lines.index { |l| l.match?(/\A127\.0\.1\.1\s/) })
        lines[i] = line
      else
        at = lines.index { |l| l.match?(/\A127\.0\.0\.1\s/) }
        lines.insert(at ? at + 1 : 0, line)
      end
      lines.join
    end

    def tunnel_token(value)
      value = string(value, 'token', max: 4096).strip
      raise Refused, "the tunnel token doesn't look like one Cloudflare gives" unless value.match?(TUNNEL_TOKEN_FORMAT)
      value
    end

    # Router mode on. The internet side is shut first, before its interface gets an address and
    # before any rule from a previous state goes, so a save never leaves it open, not for a
    # moment and not after a failure partway. Then the internet interface's address (checked
    # by netplan generate before it's applied, and applied only when a netplan file changed),
    # forwarding, the NAT block, and UFW's other rules: the LAN out, each forward in, the denies
    # in front of the LAN's way out. Only the rules a previous state had and this one doesn't are
    # deleted; the rest stay where they are (UFW skips adding a rule it has).
    def do_router_on(lan, wan, forwards, dns = nil, lan_only = [])
      previous = read_json(ROUTER_STATE)
      tailscale = File.executable?(TAILSCALE)
      shield_router(wan, tailscale)
      previous_pinned = previous && previous['pinned'].is_a?(Hash) ? previous['pinned'] : {}
      pinned = pin_lan_netplan(lan, wan, previous_pinned.keys)
      working = File.exist?(WAN_NETPLAN) ? File.read(WAN_NETPLAN) : nil
      do_install(WAN_NETPLAN, wan_netplan(wan), nil, '0600') unless working == wan_netplan(wan)
      unless netplan_applied?
        begin
          run_command([NETPLAN, 'generate'])
        rescue Failed
          # A save keeps the file that worked; a first try leaves nothing behind.
          working ? do_install(WAN_NETPLAN, working, nil, '0600') : do_remove_files(WAN_NETPLAN)
          restore_lan_netplan(pinned)
          unshield_router(wan, tailscale) unless previous
          raise
        end
        netplan_apply
      end
      # The kernel settings from before router mode, kept across its saves, for the way back.
      sysctl_before = sysctl_before(previous, wan)
      do_install(ROUTER_SYSCTL, router_sysctl(wan), nil)
      run_command(['/usr/sbin/sysctl', '-q', '-w', *router_sysctl_settings(wan).map { |key, value| "#{key}=#{value}" }])
      state = { 'lan' => lan, 'wan' => wan, 'forwards' => forwards.map { |f| f.transform_keys(&:to_s) },
                'dns' => dns, 'tailscale' => tailscale, 'lan_only' => lan_only }
      (router_rules(previous || {}) - router_rules(state)).each { |words| ufw_delete(words) }
      write_router_nat(wan, forwards, lan, dns, lan_only)
      write_router_filter6(wan)
      run_command([UFW, 'route', 'allow', 'in', 'on', lan, 'out', 'on', wan])
      forwards.each do |f|
        run_command([UFW, 'route', 'allow', 'in', 'on', wan, 'out', 'on', lan, 'to', f[:address], 'port', f[:to_port].to_s, 'proto', f[:protocol]])
      end
      if dns
        # Devices' own encrypted DNS (DNS over TLS, 853; QUIC too) doesn't get out; the NAS's
        # lookups aren't forwarded traffic, so they do.
        %w[tcp udp].each { |proto| run_command([UFW, 'route', 'insert', '1', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'to', 'any', 'port', '853', 'proto', proto]) }
      end
      # Devices kept off the internet: no forwarding out for them, ahead of the LAN's allow.
      lan_only.each { |address| run_command([UFW, 'route', 'insert', '1', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'from', address]) }
      run_command([UFW, 'reload'])
      settle_router_nat(lan, wan)
      state.merge!('pinned' => previous_pinned.merge(pinned), 'sysctl' => sysctl_before, 'since' => Time.now.to_i,
                   'rules' => ROUTER_RULES_VERSION)
      state_dir!(ROUTER_STATE)
      do_install(ROUTER_STATE, "#{JSON.generate(state)}\n", nil, '0644')
      refresh_app_firewall
    end

    # Router mode off. The internet interface goes first (its file, then its address), so
    # nothing reaches the NAS from that side once its deny is gone; then the rules, the NAT
    # block and forwarding (as it was before router mode), each on its own so one failing
    # doesn't keep the rest. +keep_lan+: DHCP stays on, so the LAN keeps the fixed address
    # router mode gave it (a NAS handing out addresses can't take its own from DHCP).
    def do_router_off(keep_lan = false)
      return nil unless router_in_place?
      state = read_json(ROUTER_STATE)
      pinned = state && state['pinned']
      notes = keep_lan ? forget_lan_backups(pinned) : restore_lan_netplan(pinned)
      if File.exist?(WAN_NETPLAN)
        wan = File.read(WAN_NETPLAN)[/^    (#{IFNAME}):$/o, 1]
        do_remove_files(WAN_NETPLAN)
        netplan_apply(allow_failure: true)
        # netplan apply leaves an interface it no longer knows as it was; its address goes too.
        run_command([IP, '-4', 'addr', 'flush', 'dev', wan, { allow_failure: true }]) if wan
      end
      if File.executable?(UFW)
        ufw_router_rules_off(state) if state
        write_router_nat(nil, [])
        write_router_filter6(nil)
        run_command([UFW, 'reload', { allow_failure: true }]) if ufw_enabled?
        clear_router_nat(state)
      end
      do_remove_files(ROUTER_SYSCTL, ROUTER_STATE)
      run_command(['/usr/sbin/sysctl', '-q', '-w', "net.ipv4.ip_forward=#{forwarding_before(state)}", *sysctl_restore(state), { allow_failure: true }])
      [notes, refresh_app_firewall].compact.join('; ').then { |text| text.empty? ? nil : text }
    end

    # The app firewall lets in the LAN's subnets (lan_subnets), which router mode and This NAS
    # change: it's rebuilt after them, where Docker runs. Left as it was, devices on a new subnet
    # couldn't reach the apps, and an old one stayed let in. A failure is a note, not the change's.
    def refresh_app_firewall
      return nil unless File.executable?(DOCKER) && File.executable?(IPTABLES) && docker_output('info', '--format', '{{.ServerVersion}}')

      do_app_firewall
      nil
    rescue Failed => e
      "the app firewall wasn't rebuilt for the network's change: #{e.message}"
    end

    # Forwarding as it was before router mode: Docker turns it on for its apps, and turning it
    # off would cut them off. A state from before this was kept says nothing: off.
    def forwarding_before(state)
      value = Hash(state && state['sysctl'])['net.ipv4.ip_forward'].to_s
      value.match?(/\A[01]\z/) ? value : '0'
    end

    # Router mode's UFW rules, each as the words that name it (what ufw delete takes): the
    # internet side's deny and Tailscale's port, the LAN's way out, each forward in, devices'
    # own encrypted DNS kept in, and devices kept off the internet.
    def router_rules(state)
      lan, wan = state.values_at('lan', 'wan')
      return [] unless lan && wan
      rules = [['deny', 'in', 'on', wan]]
      rules << ['allow', 'in', 'on', wan, 'to', 'any', 'port', TAILSCALE_PORT, 'proto', 'udp'] if state['tailscale']
      rules << ['route', 'allow', 'in', 'on', lan, 'out', 'on', wan]
      Array(state['forwards']).each do |f|
        rules << ['route', 'allow', 'in', 'on', wan, 'out', 'on', lan, 'to', f['address'].to_s, 'port', f['to_port'].to_s, 'proto', f['protocol'].to_s]
      end
      %w[tcp udp].each { |proto| rules << ['route', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'to', 'any', 'port', '853', 'proto', proto] } if state['dns']
      Array(state['lan_only']).each { |address| rules << ['route', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'from', address.to_s] }
      rules
    end

    def ufw_delete(words)
      command = words.first == 'route' ? ['route', 'delete', *words.drop(1)] : ['delete', *words]
      run_command([UFW, *command, { allow_failure: true }])
    end

    # A rule at the top of UFW's list (insert 1), or appended when the list is empty (insert
    # refuses position 1 then). A copy UFW has already is skipped where it stands.
    def ufw_insert_first(words)
      result = run_command([UFW, 'insert', '1', *words, { allow_failure: true }])
      return unless result
      raise Failed, result.delete_prefix('ignored: ') unless result.include?('Invalid position')
      run_command([UFW, *words])
    end

    # Nothing in on the internet side, except Tailscale's port, which goes back on top of the
    # deny so the deny never stands in front of it.
    def shield_router(wan, tailscale)
      ufw_insert_first(['deny', 'in', 'on', wan])
      return unless tailscale
      allow = ['allow', 'in', 'on', wan, 'to', 'any', 'port', TAILSCALE_PORT, 'proto', 'udp']
      ufw_delete(allow)
      ufw_insert_first(allow)
    end

    def unshield_router(wan, tailscale)
      ufw_delete(['allow', 'in', 'on', wan, 'to', 'any', 'port', TAILSCALE_PORT, 'proto', 'udp']) if tailscale
      ufw_delete(['deny', 'in', 'on', wan])
    end

    # The LAN files router mode pinned stay as they are; their copies from before go, so a
    # later router session doesn't bring back an address from before this one.
    def forget_lan_backups(pinned)
      (pinned.is_a?(Hash) ? pinned.keys : []).each { |path| do_remove_files(path + NETPLAN_BACKUP_SUFFIX) }
      nil
    end

    # The netplan files made to fit router mode: the LAN interface keeps an address (one from the
    # router the NAS replaces would run out), and every interface but the internet's has its
    # default route, if it has one, put behind the internet's (a third interface, a management
    # one say, would otherwise take the devices' traffic). A file changed is kept as it was
    # beside it (NETPLAN_BACKUP_SUFFIX), once: a copy is kept from one save to the next only for
    # the files +kept+ lists (those this router session changed), and one an earlier session left
    # behind is out of date, so it's made again. Comments in it don't survive (it's read and
    # written as YAML); the installer's file has none. Returns { path => sha256 of what was
    # written }, for the way back.
    def pin_lan_netplan(lan, wan, kept = [])
      Dir.glob(File.join(NETPLAN_DIR, '*.yaml')).sort.each_with_object({}) do |path, pinned|
        data = netplan_yaml(path) or next
        before = File.read(path)
        original = Marshal.load(Marshal.dump(data))
        %w[ethernets bridges bonds vlans].each do |kind|
          next unless data['network'][kind].is_a?(Hash)
          data['network'][kind].each do |name, entry|
            next if name == wan || !entry.is_a?(Hash)
            pin_lan_entry(entry, name, name == lan)
          end
        end
        next if data == original # nothing to change: the file stays as it is, comments and all
        content = YAML.dump(data)
        backup = path + NETPLAN_BACKUP_SUFFIX
        do_install(backup, before, nil, '0600') unless File.exist?(backup) && kept.include?(path)
        do_install(path, content, nil, '0600')
        pinned[path] = Digest::SHA256.hexdigest(content)
      end
    end

    # +lan+: the interface DNS and DHCP serve, whose address is pinned; the others only have their
    # default route put behind.
    def pin_lan_entry(entry, name, lan)
      if lan && [true, 'yes', 'true'].include?(entry['dhcp4'])
        entry['dhcp4'] = false
        current = Socket.getifaddrs.select { |i| i.name == name && i.addr&.ipv4? && i.netmask }.map do |i|
          "#{i.addr.ip_address}/#{IPAddr.new(i.netmask.ip_address).to_i.to_s(2).count('1')}"
        end
        entry['addresses'] = (Array(entry['addresses']) + current).uniq
      end
      if (gateway = entry.delete('gateway4'))
        entry['routes'] = Array(entry['routes']) + [{ 'to' => 'default', 'via' => gateway }]
      end
      Array(entry['routes']).each do |route|
        next unless route.is_a?(Hash) && %w[default 0.0.0.0/0].include?(route['to'].to_s) && route['via']
        route['metric'] = LAN_ROUTE_METRIC if route['metric'].to_i <= 50
      end
    end

    def netplan_yaml(path)
      data = YAML.safe_load(File.read(path))
      data.is_a?(Hash) && data['network'].is_a?(Hash) ? data : nil
    rescue Psych::SyntaxError, SystemCallError
      nil
    end

    # netplan apply, recorded in NETPLAN_APPLIED, and the NAS's own IPv6 address for DNS put back
    # on its interface after it, whatever came of it (networkd takes it off). Raises, or with
    # +allow_failure+ returns the note.
    def netplan_apply(allow_failure: false)
      note = run_command([NETPLAN, 'apply', { allow_failure: allow_failure }])
      unless note
        state_dir!(NETPLAN_APPLIED)
        do_install(NETPLAN_APPLIED, "#{netplan_digest}\n", nil, '0644')
      end
      note
    ensure
      run_command(['/usr/bin/systemctl', 'try-restart', File.basename(ULA_UNIT), { allow_failure: true }]) if File.exist?(ULA_UNIT)
    end

    # The netplan files are as the helper last applied them.
    def netplan_applied?
      File.exist?(NETPLAN_APPLIED) && File.read(NETPLAN_APPLIED).strip == netplan_digest
    end

    def netplan_digest
      Digest::SHA256.hexdigest(Dir.glob(File.join(NETPLAN_DIR, '*.yaml')).sort.map { |path| "#{path}\n#{File.read(path)}\n" }.join)
    end

    # Puts back the files pin_lan_netplan changed, each only while it's still what the helper
    # wrote: one changed since is left, and said so, and its copy from before goes (put back
    # later, it would undo that change too). Returns the notes, or nil.
    def restore_lan_netplan(pinned)
      notes = []
      (pinned || {}).each do |path, sha|
        backup = path + NETPLAN_BACKUP_SUFFIX
        next unless File.exist?(backup)
        if File.exist?(path) && Digest::SHA256.hexdigest(File.read(path)) != sha
          notes << "#{path} was changed since router mode set it up, so it's left as it is"
        else
          do_install(path, File.read(backup), nil, '0600')
        end
        do_remove_files(backup)
      end
      notes.empty? ? nil : notes.join('; ')
    end

    # Any of router mode's files, or its block in UFW's rules (before6.rules has only the filter
    # part, whose marker begins with ROUTER_BEGIN too).
    def router_in_place?
      [ROUTER_STATE, WAN_NETPLAN, ROUTER_SYSCTL].any? { |path| File.exist?(path) } ||
        [UFW_BEFORE_RULES, UFW_BEFORE6_RULES].any? { |path| File.exist?(path) && File.read(path).include?(ROUTER_BEGIN) }
    end

    def ufw_router_rules_off(state)
      lan, wan = state.values_at('lan', 'wan')
      return unless lan && wan
      run_command([UFW, 'delete', 'allow', 'in', 'on', wan, 'to', 'any', 'port', TAILSCALE_PORT, 'proto', 'udp', { allow_failure: true }]) if state['tailscale']
      run_command([UFW, 'delete', 'deny', 'in', 'on', wan, { allow_failure: true }])
      if state['dns']
        %w[tcp udp].each { |proto| run_command([UFW, 'route', 'delete', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'to', 'any', 'port', '853', 'proto', proto, { allow_failure: true }]) }
      end
      run_command([UFW, 'route', 'delete', 'allow', 'in', 'on', lan, 'out', 'on', wan, { allow_failure: true }])
      Array(state['lan_only']).each do |address|
        run_command([UFW, 'route', 'delete', 'deny', 'in', 'on', lan, 'out', 'on', wan, 'from', address.to_s, { allow_failure: true }])
      end
      Array(state['forwards']).each do |f|
        run_command([UFW, 'route', 'delete', 'allow', 'in', 'on', wan, 'out', 'on', lan, 'to', f['address'].to_s, 'port', f['to_port'].to_s,
                     'proto', f['protocol'].to_s, { allow_failure: true }])
      end
    end

    # The internet interface takes an address from the provider; its route beats any other
    # default route the NAS has (DHCP's usual metric is 100). IPv6 waits for its own slice.
    def wan_netplan(wan)
      <<~YAML
        # Amahi-kai (Network → DNS, DHCP and Internet, router): the internet interface, with an address from the provider
        network:
          version: 2
          ethernets:
            #{wan}:
              dhcp4: true
              dhcp6: false
              accept-ra: false
              dhcp4-overrides:
                route-metric: 50
      YAML
    end

    # The NAS's own address on +interface+: the last netplan file naming it (netplan lets a later
    # file override an earlier one) gets the new IPv4 part, and any earlier one loses its IPv4
    # part, so nothing older can win; a new file when none names it. Checked by netplan generate
    # before anything is applied. With +guard+, the apply waits for the reply to get out
    # (ADDRESS_APPLY_UNIT) and the change is kept only once the NAS is reached; without, it's
    # applied and kept here and now.
    def do_set_address(interface, mode, address, gateway, dns, guard)
      state = read_json(ADDRESS_STATE)
      if state && state['state'] == 'pending'
        raise Refused, "a change to #{state['interface']} is still waiting; try again in a minute" if Time.now.to_i - state['since'].to_i < ADDRESS_STALE
        do_keep_address(stale: true)
      end
      files = netplan_files_naming(interface)
      files = ["#{NETPLAN_DIR}/80-amahi-kai-#{interface}.yaml"] if files.empty?
      created = []
      files.each_with_index do |path, i|
        if File.exist?(path)
          data = netplan_yaml(path) or raise Failed, "#{path} can't be read as netplan YAML"
          # A copy from before, kept across a failed try (the file may already be half changed)
          do_install(path + ADDRESS_BACKUP_SUFFIX, File.read(path), nil, '0600') unless File.exist?(path + ADDRESS_BACKUP_SUFFIX)
        else
          data = { 'network' => { 'version' => 2, 'ethernets' => {} } }
          created << path
        end
        set_ipv4_entry(netplan_entry(data, interface), interface, i == files.size - 1 ? mode : nil, address, gateway, dns)
        do_install(path, YAML.dump(data), nil, '0600')
      end
      begin
        run_command([NETPLAN, 'generate'])
        before = Socket.getifaddrs.filter_map { |i| i.addr.ip_address if i.name == interface && i.addr&.ipv4? }
        write_address_state('state' => 'pending', 'interface' => interface, 'mode' => mode, 'address' => address, 'files' => files,
                            'created' => created, 'before' => before, 'guard' => guard, 'applied' => false, 'since' => Time.now.to_i, 'until' => nil)
        if guard
          arm_timer(ADDRESS_APPLY_UNIT, ADDRESS_APPLY_WAIT, 'network.apply_address')
        else
          do_apply_address
        end
      rescue Failed, Refused
        # Nothing of it stays when a step fails before the change is in place.
        restore_address_files(files, created)
        do_remove_files(ADDRESS_STATE) if (state = read_json(ADDRESS_STATE)) && state['state'] == 'pending' && !state['applied']
        raise
      end
      nil
    end

    # netplan apply for the change waiting, the revert timer armed first where the change is
    # guarded: one that can't be reached is put back whatever happens to the apply. Without a
    # guard it's kept at once.
    def do_apply_address
      state = read_json(ADDRESS_STATE)
      return 'no address change is waiting' unless state && state['state'] == 'pending' && !state['applied']
      arm_timer(ADDRESS_REVERT_UNIT, ADDRESS_KEEP_WAIT, 'network.revert_address') if state['guard']
      write_address_state(state.merge('applied' => true, 'until' => state['guard'] ? Time.now.to_i + ADDRESS_KEEP_WAIT : nil))
      begin
        netplan_apply
      rescue Failed
        do_revert_address
        raise
      end
      do_keep_address unless state['guard']
      refresh_app_firewall
    end

    # The change waiting is kept: the revert timer goes, and the copies from before.
    def do_keep_address(stale: false)
      state = read_json(ADDRESS_STATE)
      raise Refused, 'no address change is waiting' unless state && state['state'] == 'pending'
      raise Refused, "the change isn't applied yet" unless state['applied'] || stale
      stop_timer(ADDRESS_APPLY_UNIT) if stale
      stop_timer(ADDRESS_REVERT_UNIT)
      do_remove_files(*Array(state['files']).map { |path| path + ADDRESS_BACKUP_SUFFIX })
      write_address_state(state.merge('state' => 'kept', 'applied' => true, 'until' => nil))
      nil
    end

    # The change waiting is put back: the files as they were, applied again where the change had
    # been. A fixed address netplan no longer knows stays on the interface, so it goes too,
    # unless it was there before.
    def do_revert_address
      state = read_json(ADDRESS_STATE)
      return 'no address change is waiting' unless state && state['state'] == 'pending'
      stop_timer(ADDRESS_APPLY_UNIT)
      stop_timer(ADDRESS_REVERT_UNIT)
      restore_address_files(state['files'], state['created'])
      if state['applied']
        netplan_apply(allow_failure: true)
        address = state['address'].to_s
        if state['mode'] == 'fixed' && !Array(state['before']).include?(address.split('/').first)
          run_command([IP, '-4', 'addr', 'del', address, 'dev', state['interface'], { allow_failure: true }])
        end
        refresh_app_firewall
      end
      write_address_state(state.merge('state' => 'reverted', 'until' => nil))
      nil
    end

    # The netplan files that name +interface+, in the order netplan reads them.
    def netplan_files_naming(interface)
      Dir.glob(File.join(NETPLAN_DIR, '*.yaml')).sort.select do |path|
        (data = netplan_yaml(path)) && netplan_entry(data, interface, create: false)
      end
    end

    # The interface's entry in a netplan document, under whichever kind it's defined; made under
    # ethernets when asked and missing.
    def netplan_entry(data, interface, create: true)
      %w[ethernets bridges bonds vlans].each do |kind|
        entry = data['network'][kind].is_a?(Hash) && data['network'][kind][interface]
        return entry if entry.is_a?(Hash)
      end
      return nil unless create
      data['network']['ethernets'] = {} unless data['network']['ethernets'].is_a?(Hash)
      data['network']['ethernets'][interface] = {}
    end

    # The IPv4 part of an interface's netplan entry: +mode+ 'automatic' (DHCP), 'fixed' (the
    # address, its router as the default route, its DNS servers), or nil for none at all. The
    # IPv6 settings stay as they are. The default route goes behind the internet's while the NAS
    # is the router, as pin_lan_entry puts it.
    def set_ipv4_entry(entry, interface, mode, address, gateway, dns)
      ipv6 = ->(value) { value.to_s.include?(':') }
      entry.delete('gateway4')
      entry.delete('dhcp4')
      addresses = Array(entry['addresses']).select(&ipv6)
      routes = Array(entry['routes']).reject { |r| r.is_a?(Hash) && %w[default 0.0.0.0/0].include?(r['to'].to_s) && !ipv6.call(r['via']) }
      nameservers = Array(entry.dig('nameservers', 'addresses')).select(&ipv6)
      case mode
      when 'automatic'
        entry['dhcp4'] = true
      when 'fixed'
        entry['dhcp4'] = false
        addresses << address
        if gateway
          route = { 'to' => 'default', 'via' => gateway }
          router = read_json(ROUTER_STATE)
          route['metric'] = LAN_ROUTE_METRIC if router && router['wan'] != interface
          routes << route
        end
        nameservers += dns
      end
      addresses.empty? ? entry.delete('addresses') : entry['addresses'] = addresses
      routes.empty? ? entry.delete('routes') : entry['routes'] = routes
      if nameservers.empty?
        entry['nameservers'].delete('addresses') if entry['nameservers'].is_a?(Hash)
        entry.delete('nameservers') if entry['nameservers'].is_a?(Hash) && entry['nameservers'].empty?
      else
        entry['nameservers'] = {} unless entry['nameservers'].is_a?(Hash)
        entry['nameservers']['addresses'] = nameservers
      end
      entry
    end

    def restore_address_files(files, created)
      Array(files).each do |path|
        backup = path + ADDRESS_BACKUP_SUFFIX
        if File.exist?(backup)
          do_install(path, File.read(backup), nil, '0600')
          do_remove_files(backup)
        elsif Array(created).include?(path)
          do_remove_files(path)
        end
      end
    end

    def write_address_state(state)
      state_dir!(ADDRESS_STATE)
      do_install(ADDRESS_STATE, "#{JSON.generate(state)}\n", nil, '0644')
    end

    # The helper's state folder (BLOCKLIST_DIR), which blocking makes first on most NASes; one
    # that goes straight to an address change or router mode doesn't have it yet.
    def state_dir!(path)
      dir = File.dirname(path)
      Dir.mkdir(dir, 0o755) unless File.directory?(dir)
    rescue SystemCallError => e
      raise Failed, "couldn't make #{dir}: #{e.message}"
    end

    # A one-shot timer that runs one of the helper's operations in +seconds+; a previous one of
    # the same name goes first.
    def arm_timer(unit, seconds, operation)
      stop_timer(unit)
      run_command(['/usr/bin/systemd-run', "--unit=#{unit}", "--on-active=#{seconds}", '--timer-property=AccuracySec=1s',
                   '/usr/local/sbin/amahi-helper', operation])
    end

    def stop_timer(unit)
      run_command(['/usr/bin/systemctl', 'stop', "#{unit}.timer", { allow_failure: true }])
      run_command(['/usr/bin/systemctl', 'reset-failed', "#{unit}.service", { allow_failure: true }])
    end

    # UFW's before.rules with Amahi-kai's NAT block (masquerade out of +wan+, a DNAT in for each
    # forward, and lookups from the LAN sent elsewhere redirected to +dns+) in front of its
    # filter table, or without it, given nil. The rest of the file is UFW's own and isn't touched.
    def write_router_nat(wan, forwards, lan = nil, dns = nil, lan_only = [])
      content = File.read(UFW_BEFORE_RULES)
      content = content.sub(/#{Regexp.escape(ROUTER_BEGIN)}\n.*?#{Regexp.escape(ROUTER_END)}\n/m, '')
      content = content.sub(/#{Regexp.escape(ROUTER_FILTER_BEGIN)}\n.*?#{Regexp.escape(ROUTER_FILTER_END)}\n/m, '')
      if wan
        # In front of UFW's own ICMP and discovery accepts (inserted first, before the filter
        # table's COMMIT): the NAS doesn't answer pings or service discovery from the internet,
        # and a kept-off device can't ping out.
        filter = [ROUTER_FILTER_BEGIN, "-I ufw-before-input 1 -i #{wan} -p icmp --icmp-type echo-request -j DROP",
                  *discovery_drops('ufw-before-input', wan)]
        lan_only.each { |address| filter << "-I ufw-before-forward 1 -i #{lan} -o #{wan} -s #{address} -j DROP" } if lan
        filter << ROUTER_FILTER_END
        content = before_commit(content, filter, UFW_BEFORE_RULES)
        lines = [ROUTER_BEGIN, '*nat', ':PREROUTING ACCEPT [0:0]', ':POSTROUTING ACCEPT [0:0]',
                 ":#{NAT_PREROUTING} - [0:0]", ":#{NAT_POSTROUTING} - [0:0]", "-F #{NAT_PREROUTING}", "-F #{NAT_POSTROUTING}"]
        if dns && lan
          %w[udp tcp].each { |proto| lines << "-A #{NAT_PREROUTING} -i #{lan} ! -d #{dns} -p #{proto} --dport 53 -j DNAT --to-destination #{dns}:53" }
        end
        forwards.each do |f|
          lines << "-A #{NAT_PREROUTING} -i #{wan} -p #{f[:protocol]} --dport #{f[:port]} -j DNAT --to-destination #{f[:address]}:#{f[:to_port]}"
        end
        lines.concat(["-A #{NAT_POSTROUTING} -o #{wan} -j MASQUERADE", "-A PREROUTING -j #{NAT_PREROUTING}", "-A POSTROUTING -j #{NAT_POSTROUTING}",
                      'COMMIT', ROUTER_END])
        raise Failed, "#{UFW_BEFORE_RULES} has no filter table to put the NAT block before" unless content.include?("*filter\n")
        content = content.sub("*filter\n", "#{lines.join("\n")}\n*filter\n")
      end
      do_install(UFW_BEFORE_RULES, content, nil, '0640')
    rescue SystemCallError => e
      raise Failed, "couldn't read #{UFW_BEFORE_RULES}: #{e.message}"
    end

    # UFW's before6.rules with the block's IPv6 filter part (service discovery in on the internet
    # side dropped), or without it, given nil. Nothing to do where UFW has no IPv6 rules.
    def write_router_filter6(wan)
      return unless File.exist?(UFW_BEFORE6_RULES)
      content = File.read(UFW_BEFORE6_RULES).sub(/#{Regexp.escape(ROUTER_FILTER_BEGIN)}\n.*?#{Regexp.escape(ROUTER_FILTER_END)}\n/m, '')
      content = before_commit(content, [ROUTER_FILTER_BEGIN, *discovery_drops('ufw6-before-input', wan), ROUTER_FILTER_END], UFW_BEFORE6_RULES) if wan
      do_install(UFW_BEFORE6_RULES, content, nil, '0640')
    rescue SystemCallError => e
      raise Failed, "couldn't read #{UFW_BEFORE6_RULES}: #{e.message}"
    end

    def discovery_drops(chain, wan)
      DISCOVERY_PORTS.map { |port| "-I #{chain} 1 -i #{wan} -p udp --dport #{port} -j DROP" }
    end

    # +lines+ put in a UFW rules file just before its last COMMIT: the filter table's end.
    def before_commit(content, lines, path)
      commit = content.rindex("COMMIT\n") or raise Failed, "#{path} has no COMMIT to put the filter rules before"
      "#{content[0...commit]}#{lines.join("\n")}\n#{content[commit..]}"
    end

    # The router's kernel settings (ROUTER_SYSCTL_ALL, ROUTER_SYSCTL_WAN), forwarding first, as
    # sysctl names them: { 'net.ipv4.conf.all.rp_filter' => '1', ... }.
    def router_sysctl_settings(wan)
      settings = { 'net.ipv4.ip_forward' => '1' }
      ROUTER_SYSCTL_ALL.each { |name, value| settings[sysctl_key('all', name)] = value }
      ROUTER_SYSCTL_WAN.each { |name, value| settings[sysctl_key(wan, name)] = value }
      settings
    end

    def router_sysctl(wan)
      router_sysctl_settings(wan).map { |key, value| "#{key} = #{value}\n" }.join
    end

    # An interface's setting as sysctl and sysctl.d name it; one with a dot in its name (a
    # VLAN's) takes the slash form throughout.
    def sysctl_key(scope, name)
      scope.include?('.') ? "net/ipv4/conf/#{scope}/#{name}" : "net.ipv4.conf.#{scope}.#{name}"
    end

    # The settings as they were before router mode, for the way back: those a previous state
    # kept, the rest read now. (A state from before the settings beyond rp_filter kept those two
    # under 'rp_filter'.)
    def sysctl_before(previous, wan)
      kept = (previous && previous['sysctl']).is_a?(Hash) ? previous['sysctl'].dup : {}
      Hash(previous && previous['rp_filter']).each { |scope, value| kept[sysctl_key(scope.to_s, 'rp_filter')] ||= value }
      router_sysctl_settings(wan).each_key do |key|
        next if kept.key?(key)
        value = read_sysctl(key) and kept[key] = value
      end
      kept
    end

    def read_sysctl(key)
      File.read("/proc/sys/#{key.include?('/') ? key : key.tr('.', '/')}").strip
    rescue SystemCallError
      nil
    end

    # The sysctl arguments that put the settings back.
    def sysctl_restore(state)
      Hash(state && state['sysctl']).filter_map do |key, value|
        "#{key}=#{value}" if key.to_s.match?(%r{\Anet[./]ipv4[./]conf[./]#{IFNAME}[./][a-z_]+\z}o) && value.to_s.match?(/\A[0-9]\z/)
      end
    end

    # What the internet side dropped: the firewall's count on its "deny in on <wan>" rule
    # (packets, since UFW last loaded its rules), and when router mode's rules went in.
    def do_wan_drops
      state = read_json(ROUTER_STATE) or raise Refused, "the NAS isn't the router"
      wan = state['wan']
      dropped = capture([IPTABLES, '-w', '-L', 'ufw-user-input', '-v', '-n', '-x']).each_line.filter_map do |line|
        packets, _bytes, target, _proto, _opt, input, output, source, destination = line.split
        packets.to_i if target == 'DROP' && input == wan && output == '*' && source == '0.0.0.0/0' && destination == '0.0.0.0/0'
      end.first
      # Pings from the internet, dropped in front of UFW's accept (the block's filter part).
      pings = capture([IPTABLES, '-w', '-L', 'ufw-before-input', '-v', '-n', '-x']).each_line.filter_map do |line|
        packets, _bytes, target, proto, _opt, input = line.split
        packets.to_i if target == 'DROP' && %w[icmp 1].include?(proto) && input == wan
      end.first.to_i
      { 'dropped' => dropped && dropped + pings, 'since' => state['since'] }
    end

    # After UFW's reload: one jump each into the NAS's nat chains (the reload appended another),
    # and any rule put straight in the built-in chains by the block as it was before the chains
    # swept out.
    def settle_router_nat(lan, wan)
      { 'PREROUTING' => NAT_PREROUTING, 'POSTROUTING' => NAT_POSTROUTING }.each do |builtin, own|
        nat_jump_off(builtin, own)
        run_command([IPTABLES, '-w', '-t', 'nat', '-A', builtin, '-j', own])
      end
      sweep_inline_nat(lan, wan)
    end

    # The way back: the jumps, the NAS's chains and any inline rule from before go.
    def clear_router_nat(state)
      { 'PREROUTING' => NAT_PREROUTING, 'POSTROUTING' => NAT_POSTROUTING }.each do |builtin, own|
        nat_jump_off(builtin, own)
        run_command([IPTABLES, '-w', '-t', 'nat', '-F', own, { allow_failure: true }])
        run_command([IPTABLES, '-w', '-t', 'nat', '-X', own, { allow_failure: true }])
      end
      sweep_inline_nat(state['lan'], state['wan']) if state
    end

    # Deletes the jump from +builtin+ into +own+ until none is left (each delete takes one copy).
    def nat_jump_off(builtin, own)
      20.times { break if run_command([IPTABLES, '-w', '-t', 'nat', '-D', builtin, '-j', own, { allow_failure: true }]) }
    end

    # The rules the NAT block put straight in PREROUTING (DNATs in on the two interfaces) and
    # POSTROUTING (the masquerade out) before it had chains of its own, as many copies as reloads
    # made. Docker's rules there (its own chain, a masquerade with a source) are left alone.
    def sweep_inline_nat(lan, wan)
      return unless lan && wan
      { 'PREROUTING' => /\A(?=.*-i (?:#{Regexp.escape(lan)}|#{Regexp.escape(wan)}) ).*-j DNAT /,
        'POSTROUTING' => /\A-o #{Regexp.escape(wan)} -j MASQUERADE\z/ }.each do |builtin, pattern|
        capture([IPTABLES, '-w', '-t', 'nat', '-S', builtin]).each_line do |line|
          spec = line.strip.delete_prefix("-A #{builtin} ")
          next if spec == line.strip || !spec.match?(pattern)
          run_command([IPTABLES, '-w', '-t', 'nat', '-D', builtin, *spec.split(' '), { allow_failure: true }])
        end
      end
    rescue Failed
      nil
    end

    # Installs dnsmasq's config. While it hands out addresses (a dhcp-range), UFW lets DHCP in on
    # its interface and systemd watches its leases for names (DHCP_NAMES_PATH); otherwise the
    # rule, the watch and the names go.
    def do_dnsmasq_config(content)
      before = File.exist?(DNSMASQ_CONF) ? dhcp_interface(File.read(DNSMASQ_CONF)) : nil
      do_install(DNSMASQ_CONF, content, :dnsmasq)
      after = dhcp_interface(content)
      if File.executable?(UFW)
        run_command([UFW, 'delete', 'allow', 'in', 'on', before, 'to', 'any', 'port', '67', 'proto', 'udp', { allow_failure: true }]) if before && before != after
        run_command([UFW, 'allow', 'in', 'on', after, 'to', 'any', 'port', '67', 'proto', 'udp']) if after
      end
      after ? dhcp_names_on : dhcp_names_off
    end

    # ["192.168.1.0/24"]: the private IPv4 subnets of the NAS's own network interfaces, the
    # internet's left out while the NAS is the router (its address is private too behind
    # another router, and the internet side mustn't reach the apps).
    def lan_subnets
      wan = read_json(ROUTER_STATE)&.dig('wan')
      JSON.parse(capture([IP, '-j', '-4', 'addr', 'show'])).flat_map do |interface|
        next [] if interface['ifname'].to_s.match?(NOT_LAN_INTERFACES) || interface['ifname'] == wan
        Array(interface['addr_info']).filter_map do |addr|
          prefix = addr['prefixlen']
          next unless prefix.is_a?(Integer) && prefix.between?(8, 32)
          net = IPAddr.new("#{addr['local']}/#{prefix}")
          "#{net}/#{prefix}" if PRIVATE_NETS.any? { |private_net| private_net.include?(net) }
        rescue IPAddr::Error
          nil
        end
      end.uniq
    rescue JSON::ParserError
      raise Failed, "ip didn't list the network interfaces"
    end
  end
end
