# frozen_string_literal: true

# DNS and DHCP: Unbound's and dnsmasq's configs, the blocklists, the leases and device names,
# and IPv6 router advertisements.
module AmahiHelper
  DNSMASQ = '/usr/sbin/dnsmasq'

  DNSMASQ_LEASES = '/var/lib/misc/dnsmasq.leases'

  UNBOUND = '/usr/sbin/unbound'

  UNBOUND_CHECKCONF = '/usr/sbin/unbound-checkconf'

  UNBOUND_CONTROL = '/usr/sbin/unbound-control'

  UNBOUND_LEASES = '/etc/unbound/unbound.conf.d/amahi-kai-leases.conf'

  # Names a device can't take in the NAS's DNS by asking DHCP for them: browsers look for their
  # proxy settings at wpad and Windows for an IPv6 tunnel at isatap (the two Windows' own DNS
  # server blocks), and localhost is every machine's own.
  RESERVED_LEASE_NAMES = %w[localhost wpad isatap].freeze

  CA_CERTS = '/etc/ssl/certs/ca-certificates.crt'

  DHCP_NAMES_PATH_CONTENT = <<~UNIT
    [Unit]
    Description=Amahi-kai: DNS names for the devices DHCP gives addresses to

    [Path]
    PathModified=#{DNSMASQ_LEASES}

    [Install]
    WantedBy=multi-user.target
  UNIT

  DHCP_NAMES_SERVICE = '/etc/systemd/system/amahi-kai-dhcp-names.service'

  DHCP_NAMES_SERVICE_CONTENT = <<~UNIT
    [Unit]
    Description=Amahi-kai: DNS names for the devices DHCP gives addresses to
    # Devices joining at once rewrite the leases several times a second: with systemd's default
    # limit (5 starts in 10 s), a burst stopped this job for good, and the watch with it.
    StartLimitIntervalSec=0

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/amahi-helper dns.sync_leases
    StandardInputText={}
  UNIT

  # How long to listen for another DHCP server's offer. dnsmasq (which many routers run, OpenWrt
  # among them) pings an address for 3 seconds to see it's free before it offers it.
  DHCP_WAIT = 6

  BLOCKLIST_CHOSEN = "#{BLOCKLIST_DIR}/chosen.json".freeze

  BLOCKLIST_STATUS = "#{BLOCKLIST_DIR}/status.json".freeze

  BLOCKLIST_PAUSED = "#{BLOCKLIST_DIR}/blocklist.paused".freeze

  # When the helper last reloaded Unbound: its counters start again then (Network → DNS, DHCP and Internet's
  # totals say since when).
  UNBOUND_RELOADED = "#{BLOCKLIST_DIR}/reloaded_at".freeze

  UNBOUND_BLOCKLIST = '/etc/unbound/unbound.conf.d/amahi-kai-blocklist.conf'

  UNBOUND_MAIN = '/etc/unbound/unbound.conf'

  BLOCKLIST_MAX_BYTES = 64 * 1024 * 1024

  # About 150 MB of Unbound's memory per 300,000 (measured on Unbound 1.19).
  BLOCKLIST_MAX_DOMAINS = 1_000_000

  # A copy downloaded less than this long ago isn't downloaded again.
  BLOCKLIST_FRESH = 20 * 3600

  ALLOWLIST_MAX = 1000

  # A name a list may block: labels, then a top-level domain that isn't a number.
  BLOCK_DOMAIN = /\A(?=.{4,253}\z)(?:[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]\z/

  BLOCKLIST_SERVICE = '/etc/systemd/system/amahi-kai-blocklists.service'

  BLOCKLIST_SERVICE_CONTENT = <<~UNIT
    [Unit]
    Description=Amahi-kai: refresh the DNS blocklists
    Wants=network-online.target
    After=network-online.target unbound.service

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/amahi-helper dns.refresh_blocklists
  UNIT

  BLOCKLIST_TIMER = '/etc/systemd/system/amahi-kai-blocklists.timer'

  BLOCKLIST_TIMER_CONTENT = <<~UNIT
    [Unit]
    Description=Amahi-kai: refresh the DNS blocklists every day

    [Timer]
    OnCalendar=*-*-* 04:00
    RandomizedDelaySec=2h
    Persistent=true

    [Install]
    WantedBy=timers.target
  UNIT

  # Pausing blocking: a transient systemd timer resumes it.
  DNS_RESUME_UNIT = 'amahi-kai-dns-resume'

  BLOCKING_PAUSE = 300

  # IPv6 (Network → DNS, DHCP and Internet): radvd announces the NAS as the network's IPv6 DNS server, at an
  # address of its own in a unique local range (ULA_UNIT puts it on the interface at boot).
  RADVD = '/usr/sbin/radvd'

  RADVD_CONF = '/etc/radvd.conf'

  ULA = IPAddr.new('fc00::/7')

  # How long to listen for routers' announcements (a router waits up to 3 seconds between them).
  RA_WAIT = 4

  # --- Unbound config checks -----------------------------------------------------------

  # Unbound's config can load Python modules, read and write files and open its control
  # port, and the app writes the file whole, so every line must be one Amahi-kai generates
  # (unbound_line?): a clause it uses, or an option with a value it would write.
  UNBOUND_CLAUSES = %w[server: forward-zone:].freeze

  UNBOUND_SWITCHES = %w[ip-freebind hide-identity hide-version prefetch qname-minimisation serve-expired
                        forward-tls-upstream extended-statistics].freeze

  TLS_NAME = '[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?'

  # Never the whole internet, line by line or added up: the networks Unbound answers come to at
  # most this many addresses of each family (a /7's worth of IPv4, room for a /8 LAN beside
  # Tailscale's range; a /32's worth of IPv6, the link-local range aside).
  ACCESS_CONTROL_MAX = { 4 => 2**25, 6 => 2**96 }.freeze

  LINK_LOCAL6 = IPAddr.new('fe80::/10')


  add_operations(
    # Another DHCP server answering on the interface (its addresses), before dnsmasq starts
    # handing out addresses there. The NAS's own offers don't count.
    'dhcp.check_servers' => {
      params: %w[interface],
      validate: ->(a) { { interface: network_interface(a['interface']) } },
      plan: ->(v) { [[:dhcp_servers, v[:interface]]] }
    },
    # Unbound's config (Network → DNS): only lines Amahi-kai writes, checked with
    # unbound-checkconf. UFW lets DNS in to the addresses Unbound listens on.
    'dns.write_config' => {
      params: %w[content],
      validate: ->(a) { installed!(UNBOUND) && { content: unbound_conf(a['content']) } },
      plan: ->(v) { [[:dns_config, v[:content]]] }
    },
    # DNS turned off: the config goes, and so do its firewall rules.
    'dns.remove_config' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:dns_config, nil]] }
    },
    # The names of the devices dnsmasq gave addresses to, for Unbound. Run by systemd when the
    # lease file changes (DHCP_NAMES_PATH).
    'dns.sync_leases' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:sync_leases]] }
    },
    # The watch on the leases (DHCP_NAMES_PATH) as this version writes it, and running: one
    # systemd stopped (before 1.0.2, a burst of leases could) starts again, with the names
    # brought up to date. Run at every System Update; with DHCP off there's no watch to keep.
    'dns.names_setup' => {
      params: [],
      validate: ->(_a) { { on: File.exist?(DNSMASQ_CONF) && !dhcp_interface(File.read(DNSMASQ_CONF)).nil? } },
      plan: ->(v) { v[:on] ? [[:dhcp_names]] : [] }
    },
    # Blocking on, with these lists (keys of BLOCKLISTS) and this allowlist: saved for the daily
    # refresh (BLOCKLIST_TIMER), which also runs now, in the background.
    'dns.set_blocklists' => {
      params: %w[lists allow],
      validate: ->(a) { installed!(UNBOUND) && { lists: blocklist_keys(a['lists']), allow: allowlist(a['allow']) } },
      plan: ->(v) { [[:set_blocklists, v[:lists], v[:allow]]] }
    },
    # Unbound's totals since its counters last started: lookups, those answered on the NAS (its
    # cache, its names, its blocklist), DNSSEC-checked answers and forged ones refused. Totals
    # only: nothing about who asked for what.
    'dns.stats' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:dns_stats]] }
    },
    'dns.blocking_off' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:blocking_off]] }
    },
    # Downloads the chosen lists that are due and rebuilds Unbound's blocklist. Run by
    # BLOCKLIST_TIMER, and started by dns.set_blocklists.
    'dns.refresh_blocklists' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:refresh_blocklists]] }
    },
    # radvd's config: the NAS announces itself as the IPv6 DNS server (RDNSS), and its own range
    # as on the network, never as a router (AdvDefaultLifetime 0); checked with radvd --configtest.
    'dns.write_radvd_config' => {
      params: %w[content],
      validate: ->(a) { installed!(RADVD) && { content: radvd_conf(a['content']) } },
      plan: ->(v) { [[:install, RADVD_CONF, v[:content], :radvd]] }
    },
    'dns.remove_radvd_config' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:remove_files, RADVD_CONF]] }
    },
    # The NAS's own IPv6 address for DNS, a unique local one (fc00::/7), on the interface now and
    # at every boot (ULA_UNIT).
    'dns.set_own_address' => {
      params: %w[interface address],
      validate: ->(a) { { interface: network_interface(a['interface']), address: ula_address(a['address']) } },
      plan: ->(v) { [[:set_ula, v[:interface], v[:address]]] }
    },
    'dns.remove_own_address' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:remove_ula]] }
    },
    # The routers on the interface and what they announce: a router solicitation, and the
    # advertisements for RA_WAIT seconds (the NAS's own left out).
    'dns.check_routers' => {
      params: %w[interface],
      validate: ->(a) { { interface: network_interface(a['interface']) } },
      plan: ->(v) { [[:ipv6_advertisers, v[:interface]]] }
    },
    # Blocking stops for BLOCKING_PAUSE seconds, then systemd resumes it (dns.resume_blocking).
    'dns.pause_blocking' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:pause_blocking]] }
    },
    'dns.resume_blocking' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:resume_blocking]] }
    },
  )

  class << self
    def blocklist_keys(value)
      raise Refused, 'lists must be a list of blocklists' unless value.is_a?(Array) && value.all?(String) && value.any?
      unknown = value - BLOCKLISTS.keys
      raise Refused, "#{unknown.first.inspect} isn't a blocklist Amahi-kai knows" if unknown.any?
      value.uniq
    end

    # Domains never blocked (Network → DNS, DHCP and Internet's allowlist).
    def allowlist(value)
      raise Refused, 'allow must be a list of domains' unless value.is_a?(Array) && value.all?(String)
      raise Refused, "the allowlist holds at most #{ALLOWLIST_MAX} domains" if value.size > ALLOWLIST_MAX
      bad = value.reject { |name| name.match?(BLOCK_DOMAIN) }
      raise Refused, "#{bad.first.inspect} isn't a domain" if bad.any?
      value.uniq
    end

    # A unique local IPv6 address (fc00::/7), with no prefix length.
    def ula_address(value)
      value = string(value, 'address', max: 39)
      raise Refused, "#{value.inspect} isn't a unique local IPv6 address (fc00::/7)" unless ip_address?(value, :ipv6?) && ULA.include?(IPAddr.new(value))
      IPAddr.new(value).to_s
    end

    # radvd's config: only what Amahi-kai writes, with unique local addresses, and every
    # interface's block saying the NAS is no router (radvd announces one by default).
    def radvd_conf(value)
      value = string(value, 'content', max: 4096)
      depth = 0
      no_router = false
      value.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        raise Refused, "radvd line #{line.inspect} is not one Amahi-kai writes" unless radvd_line?(line)
        no_router = false if depth.zero?
        no_router = true if depth == 1 && line == 'AdvDefaultLifetime 0;'
        depth += line == '};' ? -1 : (line.end_with?('{') ? 1 : 0)
        raise Refused, "radvd's config must say for each interface that the NAS is no router (AdvDefaultLifetime 0)" if depth.zero? && !no_router
      end
      raise Refused, "radvd's config leaves a block open" unless depth.zero?
      value
    end

    def radvd_line?(line)
      return true if ['AdvSendAdvert on;', 'AdvDefaultLifetime 0;', 'AdvOnLink on;', 'AdvAutonomous on;', '};'].include?(line)
      return true if line.match?(/\Ainterface #{IFNAME} \{\z/o)
      return true if line.match?(/\ADNSSL #{UNBOUND_NAME.delete_suffix('+')}*[a-z0-9-]+ \{\z/o)
      if (match = line.match(%r{\Aprefix ([0-9a-f:]+)/64 \{\z}))
        return ip_address?(match[1], :ipv6?) && ULA.include?(IPAddr.new(match[1]))
      end
      match = line.match(/\ARDNSS ([0-9a-f:]+) \{\z/)
      !!match && ip_address?(match[1], :ipv6?) && ULA.include?(IPAddr.new(match[1]))
    end

    def unbound_conf(value)
      value = string(value, 'content', max: 256 * 1024)
      allowed = []
      value.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        raise Refused, "Unbound line #{line.inspect} is not one Amahi-kai writes" unless unbound_line?(line)
        key, rest = line.split(/:\s+/, 2)
        allowed << rest.split(' ', 2).first if key == 'access-control'
      end
      access_control_total!(allowed)
      value
    end

    # The networks the access-control lines let in ("10.99.0.0/24"), each counted once and added
    # up per family, the link-local range aside (ACCESS_CONTROL_MAX).
    def access_control_total!(networks)
      totals = Hash.new(0)
      networks.map { |network| IPAddr.new(network) }.uniq { |ip| [ip.to_s, ip.prefix] }.each do |ip|
        next if LINK_LOCAL6.include?(ip)
        family = ip.ipv4? ? 4 : 6
        totals[family] += 2**((family == 4 ? 32 : 128) - ip.prefix)
      end
      return unless totals.any? { |family, total| total > ACCESS_CONTROL_MAX[family] }
      raise Refused, "Unbound's access-control lines add up to too much of the internet: it would answer far more than your networks"
    end

    def unbound_line?(line)
      return true if UNBOUND_CLAUSES.include?(line)
      key, value = line.split(/:\s+/, 2)
      return false unless value
      case key
      when *UNBOUND_SWITCHES then value == 'yes'
      when 'serve-expired-ttl', 'serve-expired-client-timeout' then value.match?(/\A\d{1,6}\z/)
      when 'interface' then ip_address?(value) && !IPAddr.new(value).to_i.zero?
      when 'access-control'
        # Never the whole internet: an open resolver is used against others (amplification).
        network, action = value.split(' ', 2)
        action == 'allow' && ip_network?(network) && network.split('/').last.to_i >= (network.include?(':') ? 10 : 8)
      when 'private-address' then ip_network?(value)
      when 'local-zone' then value.match?(/\A"#{UNBOUND_NAME}" (?:static|always_nxdomain)\z/io)
      when 'local-data'
        match = value.match(/\A"#{UNBOUND_NAME} IN (A|AAAA) ([0-9a-f.:]+)"\z/io)
        match && ip_address?(match[2], match[1] == 'A' ? :ipv4? : :ipv6?)
      when 'local-data-ptr'
        match = value.match(/\A"([0-9a-f.:]+) #{UNBOUND_NAME}"\z/io)
        match && ip_address?(match[1])
      when 'tls-cert-bundle' then value == %("#{CA_CERTS}")
      when 'name' then value == '"."'
      when 'forward-addr'
        match = value.match(/\A([0-9a-f.:]+)@853##{TLS_NAME}\z/io)
        match && ip_address?(match[1])
      else false
      end
    end

    # An IPv4 or IPv6 network with its prefix length ("192.168.1.0/24").
    def ip_network?(value)
      address, prefix = value.split('/', 2)
      return false unless prefix&.match?(/\A\d{1,3}\z/) && ip_address?(address)
      IPAddr.new(value)
      true
    rescue IPAddr::Error
      false
    end

    # Where dnsmasq is installed, it must accept the file too.
    def check_dnsmasq_conf(path)
      return unless File.executable?(DNSMASQ)
      _out, err, status = Open3.capture3(ENV_MIN, [DNSMASQ, DNSMASQ], '--test', "--conf-file=#{path}",
                                         unsetenv_others: true, chdir: '/')
      raise Refused, "dnsmasq rejected the config: #{last_lines(err, 2)}" unless status.success?
    end

    # unbound-checkconf reads the file on its own (it is complete: its clauses and options).
    def check_unbound_conf(path)
      out, err, status = Open3.capture3(ENV_MIN, [UNBOUND_CHECKCONF, UNBOUND_CHECKCONF], path,
                                        unsetenv_others: true, chdir: '/')
      raise Refused, "unbound-checkconf rejected the config: #{last_lines(err.empty? ? out : err, 2)}" unless status.success?
    rescue Errno::ENOENT
      raise Failed, "#{UNBOUND_CHECKCONF} is missing; is Unbound installed?"
    end

    def check_radvd_conf(path)
      _out, err, status = Open3.capture3(ENV_MIN, [RADVD, RADVD], '--configtest', '--config', path, unsetenv_others: true, chdir: '/')
      raise Refused, "radvd rejected the config: #{last_lines(err, 2)}" unless status.success?
    rescue Errno::ENOENT
      raise Failed, "#{RADVD} is missing; is radvd installed?"
    end

    # The NAS's own IPv6 address for DNS on +interface+, now and at every boot: a oneshot unit adds
    # it (replace: running it again changes nothing) and takes it away when stopped. One that was
    # there before is stopped first, so an old address goes. Before adding it, the unit clears a
    # route for its range on the loopback, if there is one: the test VM was left with one (we
    # couldn't reproduce how) and it sent every reply to devices in the range back into the NAS.
    def do_set_ula(interface, address)
      range = "#{IPAddr.new(address).mask(64)}/64"
      content = <<~UNIT
        [Unit]
        Description=Amahi-kai: the NAS's own IPv6 address for DNS
        Wants=network-online.target
        After=network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStartPre=-#{IP} -6 route del #{range} dev lo
        ExecStart=#{IP} -6 addr replace #{address}/64 dev #{interface}
        ExecStop=#{IP} -6 addr del #{address}/64 dev #{interface}

        [Install]
        WantedBy=multi-user.target
      UNIT
      return if File.exist?(ULA_UNIT) && File.read(ULA_UNIT) == content
      run_command(['/usr/bin/systemctl', 'stop', File.basename(ULA_UNIT), { allow_failure: true }]) if File.exist?(ULA_UNIT)
      do_install(ULA_UNIT, content, nil)
      run_command(%w[/usr/bin/systemctl daemon-reload])
      run_command(['/usr/bin/systemctl', 'enable', File.basename(ULA_UNIT)])
      run_command(['/usr/bin/systemctl', 'restart', File.basename(ULA_UNIT)])
    end

    def do_remove_ula
      return unless File.exist?(ULA_UNIT)
      run_command(['/usr/bin/systemctl', 'disable', '--now', File.basename(ULA_UNIT), { allow_failure: true }])
      do_remove_files(ULA_UNIT)
      run_command(%w[/usr/bin/systemctl daemon-reload])
    end

    # What the routers on +interface+ announce (RFC 4861): a router solicitation to all routers,
    # then every advertisement for RA_WAIT seconds, one per router, the NAS's own left out.
    def do_ipv6_advertisers(interface)
      links = Socket.getifaddrs.select { |i| i.name == interface }
      index = links.first&.ifindex or raise Failed, "#{interface} has no index"
      own = links.filter_map { |i| i.addr.ip_address.sub(/%.*/, '') if i.addr&.ipv6? }
      found = {}
      Socket.open(:INET6, :RAW, Socket::IPPROTO_ICMPV6) do |socket|
        socket.setsockopt(:SOCKET, :BINDTODEVICE, interface)
        # Routers only answer a solicitation that comes with a hop limit of 255.
        socket.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_HOPS, [255].pack('i'))
        socket.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_IF, [index].pack('I'))
        socket.send([133, 0, 0, 0].pack('CCnN'), 0, Socket.sockaddr_in(0, "ff02::2%#{interface}"))
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RA_WAIT
        while (left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
          break unless IO.select([socket], nil, nil, left)
          data, sender = socket.recvfrom(4096)
          router = sender.ip_address.sub(/%.*/, '')
          advert = router_advertisement(data)
          found[router] ||= advert.merge('router' => router) if advert && !own.include?(router)
        end
      end
      { 'advertisers' => found.values }
    rescue SystemCallError => e
      raise Failed, "couldn't listen for IPv6 routers on #{interface}: #{e.message}"
    end

    # A router advertisement's router lifetime (0: not a default router), prefixes, DNS servers
    # (RDNSS) and search domains (DNSSL), or nil when +data+ isn't one.
    def router_advertisement(data)
      data = data.b
      return unless data.bytesize >= 16 && data.getbyte(0) == 134
      advert = { 'lifetime' => data.byteslice(6, 2).unpack1('n'), 'prefixes' => [], 'dns' => [], 'domains' => [] }
      i = 16
      while i + 8 <= data.bytesize
        type = data.getbyte(i)
        length = data.getbyte(i + 1) * 8
        break if length.zero? || i + length > data.bytesize
        option = data.byteslice(i, length)
        case type
        when 3 then advert['prefixes'] << "#{IPAddr.new_ntoh(option.byteslice(16, 16))}/#{option.getbyte(2)}" if length == 32
        when 25 then ((length - 8) / 16).times { |n| advert['dns'] << IPAddr.new_ntoh(option.byteslice(8 + (16 * n), 16)).to_s }
        when 31 then advert['domains'].concat(dns_names(option.byteslice(8..)))
        end
        i += length
      end
      advert
    end

    # The domain names in DNSSL's wire format (labels, each name ending in a zero byte).
    def dns_names(bytes)
      names = []
      labels = []
      i = 0
      while i < bytes.bytesize
        length = bytes.getbyte(i)
        i += 1
        if length.zero?
          names << labels.join('.') if labels.any?
          labels = []
        else
          labels << bytes.byteslice(i, length).to_s
          i += length
        end
      end
      names
    end

    # Installs Unbound's config (or, given nil, removes it), then has UFW let DNS in to the
    # addresses Unbound listens on now, and no longer to those it stopped listening on. UFW
    # keeps the rules while it's off, for when it's turned on.
    def do_dns_config(content)
      before = File.exist?(UNBOUND_CONF) ? unbound_listening(File.read(UNBOUND_CONF)) : []
      if content
        do_install(UNBOUND_CONF, content, :unbound)
        # The leases' names give way to the names this config gives (fixed hosts, DNS aliases), and
        # take back one it no longer gives: a device unfixed answers by its name through its lease
        # at once, whichever of dnsmasq's and Unbound's configs is written last.
        do_sync_leases if File.exist?(DNSMASQ_CONF) && dhcp_interface(File.read(DNSMASQ_CONF))
      else
        do_remove_files(UNBOUND_CONF, UNBOUND_LEASES)
        blocking_stop
      end
      after = content ? unbound_listening(content) : []
      # The apps' containers follow when Unbound starts or stops answering on Docker's bridge
      bridge = docker_bridge_address
      follow_dns_apps_later if bridge && before.include?(bridge) != after.include?(bridge)
      return unless File.executable?(UFW)
      (before - after).each { |address| run_command([UFW, 'delete', 'allow', 'to', address, 'port', '53', { allow_failure: true }]) }
      # UFW refuses IPv6 rules when its IPv6 is off; then only IPv4 gets in, which is noted.
      notes = after.filter_map do |address|
        run_command([UFW, 'allow', 'to', address, 'port', '53', { allow_failure: address.include?(':') }])
      end
      notes.empty? ? nil : notes.join('; ')
    end

    # The interface a dnsmasq config hands out addresses on, or nil when it hands out none.
    def dhcp_interface(content)
      return unless content.match?(/^dhcp-range=/)
      content[/^interface=(#{IFNAME})$/o, 1]
    end

    # The watch on the leases, and their names now. A watch systemd stopped stays stopped until
    # it's reset, so a DHCP save (or dns.names_setup) starts it again.
    def dhcp_names_on
      do_install(DHCP_NAMES_SERVICE, DHCP_NAMES_SERVICE_CONTENT, nil)
      do_install(DHCP_NAMES_PATH, DHCP_NAMES_PATH_CONTENT, nil)
      run_command(%w[/usr/bin/systemctl daemon-reload])
      run_command(['/usr/bin/systemctl', 'reset-failed', File.basename(DHCP_NAMES_SERVICE), File.basename(DHCP_NAMES_PATH),
                   { allow_failure: true }])
      run_command(['/usr/bin/systemctl', 'enable', '--now', File.basename(DHCP_NAMES_PATH)])
      do_sync_leases
    end

    # dns.names_setup's one step.
    def do_dhcp_names
      dhcp_names_on
    end

    def dhcp_names_off
      if File.exist?(DHCP_NAMES_PATH)
        run_command(['/usr/bin/systemctl', 'disable', '--now', File.basename(DHCP_NAMES_PATH), { allow_failure: true }])
      end
      return unless File.exist?(UNBOUND_LEASES)
      do_remove_files(UNBOUND_LEASES)
      unbound_reload
    end

    # The names of the devices dnsmasq gave addresses to, as Unbound's local data
    # (UNBOUND_LEASES): name.<domain> and name, with reverse lookups. A device named on Network →
    # Devices (dhcp_named) answers by that name at once, wherever it is, and before any other
    # device's; the others by the name they ask for, an underscore read as a hyphen (Wyze cameras
    # ask for WYZE_CAKP2JFUS-…). Only names that are one label, on IPv4 addresses, and neither
    # reserved (RESERVED_LEASE_NAMES) nor one Amahi-kai's config already gives (the NAS, fixed
    # hosts, DNS aliases). Written, and Unbound reloaded, only when they change.
    def do_sync_leases
      return 'DNS is off' unless File.exist?(UNBOUND_CONF)
      config = File.read(UNBOUND_CONF)
      domain = config[/^\s*local-zone: "(#{UNBOUND_NAME})" static$/o, 1] or return 'DNS has no local domain'
      taken = config.scan(/^\s*local-data: "([a-z0-9-]+)\./).flatten + RESERVED_LEASE_NAMES
      named = dhcp_named
      chosen, asked = dhcp_leases.map { |address, mac, name| [address, named[mac] || name, named.key?(mac)] }.partition(&:last)
      lines = ['# Names of the devices DHCP gave addresses to: written by Amahi-kai, changes here are lost', 'server:']
      (chosen + asked).each do |address, name, _chosen|
        next if name.nil? || taken.include?(name)
        taken << name
        lines << %(  local-data: "#{name}.#{domain} IN A #{address}") << %(  local-data: "#{name}. IN A #{address}")
        lines << %(  local-data-ptr: "#{address} #{name}.#{domain}")
      end
      content = "#{lines.join("\n")}\n"
      return if File.exist?(UNBOUND_LEASES) && File.read(UNBOUND_LEASES) == content
      do_install(UNBOUND_LEASES, content, :unbound)
      unbound_reload
    end

    # [[address, mac, name]] from dnsmasq's leases ("expiry mac address name client-id"), on IPv4
    # addresses; name is nil when the one asked for can't be a DNS label.
    def dhcp_leases(path = DNSMASQ_LEASES)
      return [] unless File.exist?(path)
      File.foreach(path).filter_map do |line|
        _expiry, mac, address, name = line.split
        name = name.to_s.downcase.tr('_', '-')
        [address, mac.to_s.downcase, (name if name.match?(/\A[a-z][a-z0-9-]{0,62}\z/))] if ip_address?(address.to_s, :ipv4?)
      end
    end

    # The devices named on Network → Devices without a fixed address, { mac => name }: dnsmasq's
    # dhcp-host lines with no address (DNSMASQ_LINES).
    def dhcp_named(path = DNSMASQ_CONF)
      return {} unless File.exist?(path)
      File.read(path).scan(/^dhcp-host=((?:[0-9a-f]{2}:){5}[0-9a-f]{2}),(#{DHCP_NAME})$/o).to_h
    end

    # Blocking on: the lists and allowlist saved, the daily refresh set, and a refresh now in
    # the background (it can take a while to download), which the app sees in BLOCKLIST_STATUS.
    def do_set_blocklists(lists, allow)
      Dir.mkdir(BLOCKLIST_DIR, 0o755) unless File.directory?(BLOCKLIST_DIR)
      do_install(BLOCKLIST_CHOSEN, "#{JSON.pretty_generate('lists' => lists, 'allow' => allow)}\n", nil)
      do_install(BLOCKLIST_SERVICE, BLOCKLIST_SERVICE_CONTENT, nil)
      do_install(BLOCKLIST_TIMER, BLOCKLIST_TIMER_CONTENT, nil)
      run_command(%w[/usr/bin/systemctl daemon-reload])
      run_command(['/usr/bin/systemctl', 'enable', '--now', File.basename(BLOCKLIST_TIMER)])
      run_command(['/usr/bin/systemctl', 'start', '--no-block', File.basename(BLOCKLIST_SERVICE)])
    end

    def do_blocking_off
      blocking_stop
      do_remove_files(BLOCKLIST_CHOSEN, BLOCKLIST_STATUS)
      unbound_reload
    end

    # The blocklist goes from Unbound, paused or not, with its daily refresh and any resume.
    def blocking_stop
      if File.exist?(BLOCKLIST_TIMER)
        run_command(['/usr/bin/systemctl', 'disable', '--now', File.basename(BLOCKLIST_TIMER), { allow_failure: true }])
      end
      run_command(['/usr/bin/systemctl', 'stop', "#{DNS_RESUME_UNIT}.timer", { allow_failure: true }])
      do_remove_files(UNBOUND_BLOCKLIST, BLOCKLIST_PAUSED)
    end

    # Downloads each chosen list that's due (a list that can't be downloaded keeps its last copy,
    # and says why in BLOCKLIST_STATUS), and makes Unbound's blocklist from them: each domain
    # answers 0.0.0.0 and ::, with its subdomains, except the allowlist's and Amahi-kai's own
    # zones (the local domain, Firefox's canary). Written where it's paused, while it is.
    def do_refresh_blocklists
      chosen = read_json(BLOCKLIST_CHOSEN) or return 'blocking is off'
      return 'DNS is off' unless File.exist?(UNBOUND_CONF)
      own = File.read(UNBOUND_CONF).scan(/^\s*local-zone: "([^"]+)\." /).flatten
      allow = Array(chosen['allow']).grep(BLOCK_DOMAIN).reject { |name| under?(name, own) }
      status = { 'refreshed_at' => Time.now.to_i, 'lists' => {} }
      domains = {}
      (Array(chosen['lists']) & BLOCKLISTS.keys).each do |key|
        copy = "#{BLOCKLIST_DIR}/#{key}.txt"
        error = fetch_blocklist(key, copy) unless File.exist?(copy) && Time.now - File.mtime(copy) < BLOCKLIST_FRESH
        count = 0
        if File.exist?(copy)
          File.foreach(copy) do |line|
            name = blocklist_domain(line) or next
            domains[name] = true
            count += 1
          end
        end
        status['lists'][key] = { 'domains' => count, 'downloaded_at' => (File.mtime(copy).to_i if File.exist?(copy)), 'error' => error }.compact
      end
      allow.each { |name| domains.delete(name) }
      # A domain blocks the names under it, so those needn't be listed too.
      blocked = domains.keys.reject { |name| under?(name, own) || parent_listed?(name, domains) }.sort
      raise Failed, "the lists chosen block #{blocked.size} domains; at most #{BLOCKLIST_MAX_DOMAINS} fit" if blocked.size > BLOCKLIST_MAX_DOMAINS
      lines = ['# DNS blocklist (Network → DNS, DHCP and Internet): written by Amahi-kai, changes here are lost', 'server:']
      lines.concat(blocked.map { |name| %(  local-zone: "#{name}." always_null) })
      lines.concat(allow.map { |name| %(  local-zone: "#{name}." transparent) })
      content = "#{lines.join("\n")}\n"
      File.exist?(BLOCKLIST_PAUSED) ? do_install(BLOCKLIST_PAUSED, content, nil) : install_blocklist(content)
      do_install(BLOCKLIST_STATUS, "#{JSON.generate(status.merge('blocked' => blocked.size))}\n", nil, '0644')
      { 'blocked' => blocked.size }
    rescue Failed, Refused => e
      # The page says why; the blocklist before stays, and so does its count.
      before = read_json(BLOCKLIST_STATUS) || {}
      do_install(BLOCKLIST_STATUS, "#{JSON.generate(before.merge('refreshed_at' => Time.now.to_i, 'error' => e.message))}\n", nil, '0644')
      raise
    end

    # Downloads a list over HTTPS to +copy+ (replacing it only once it's whole), or says why not.
    def fetch_blocklist(key, copy)
      download = "#{copy}.download"
      run_command(['/usr/bin/curl', '-fsSL', '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2', '--max-time', '180',
                   '--max-filesize', BLOCKLIST_MAX_BYTES.to_s, '-o', download, BLOCKLISTS.fetch(key)[:url]])
      raise Failed, 'the download was empty' if File.size(download).zero?
      File.rename(download, copy)
      nil
    rescue Failed, SystemCallError => e
      File.unlink(download) if File.exist?(download)
      e.message
    end

    # The domain a list's line blocks, or nil (a comment, a blank, an address, a name that isn't one).
    def blocklist_domain(line)
      name = line.sub(/#.*/, '').strip.downcase.delete_prefix('*.').delete_suffix('.')
      name if name.match?(BLOCK_DOMAIN) && name != 'localhost.localdomain'
    end

    def under?(name, zones)
      zones.any? { |zone| name == zone || name.end_with?(".#{zone}") }
    end

    def parent_listed?(name, domains)
      labels = name.split('.')
      (1...(labels.size - 1)).any? { |i| domains.key?(labels.drop(i).join('.')) }
    end

    # Installs the blocklist, checked on its own and then with the whole of Unbound's config
    # (a name twice is an error there); the one before stays if either check fails. Unbound
    # then reloads, keeping its cache.
    def install_blocklist(content)
      previous = File.exist?(UNBOUND_BLOCKLIST) ? File.read(UNBOUND_BLOCKLIST) : nil
      do_install(UNBOUND_BLOCKLIST, content, :unbound)
      begin
        check_unbound_conf(UNBOUND_MAIN)
      rescue Refused
        previous ? do_install(UNBOUND_BLOCKLIST, previous, nil) : do_remove_files(UNBOUND_BLOCKLIST)
        raise
      end
      unbound_reload
    end

    # Blocking stops for BLOCKING_PAUSE seconds: the blocklist moves out of Unbound's config, and
    # a transient systemd timer runs dns.resume_blocking (a new pause starts the time again).
    def do_pause_blocking
      return 'blocking is off' unless File.exist?(UNBOUND_BLOCKLIST) || File.exist?(BLOCKLIST_PAUSED)
      if File.exist?(UNBOUND_BLOCKLIST)
        do_install(BLOCKLIST_PAUSED, File.read(UNBOUND_BLOCKLIST), nil)
        do_remove_files(UNBOUND_BLOCKLIST)
        unbound_reload
      end
      run_command(['/usr/bin/systemctl', 'stop', "#{DNS_RESUME_UNIT}.timer", { allow_failure: true }])
      run_command(['/usr/bin/systemctl', 'reset-failed', "#{DNS_RESUME_UNIT}.service", { allow_failure: true }])
      run_command(['/usr/bin/systemd-run', "--unit=#{DNS_RESUME_UNIT}", "--on-active=#{BLOCKING_PAUSE}",
                   '--timer-property=AccuracySec=5s', '/usr/local/sbin/amahi-helper', 'dns.resume_blocking'])
      { 'until' => Time.now.to_i + BLOCKING_PAUSE }
    end

    def do_resume_blocking
      if File.exist?(BLOCKLIST_PAUSED)
        install_blocklist(File.read(BLOCKLIST_PAUSED))
        do_remove_files(BLOCKLIST_PAUSED)
      end
      run_command(['/usr/bin/systemctl', 'stop', "#{DNS_RESUME_UNIT}.timer", { allow_failure: true }])
      nil
    end

    # Unbound reads its config again, keeping its cache (its counters start again). Nothing to do
    # while it's stopped.
    def unbound_reload
      return unless unbound_active?
      run_command([UNBOUND_CONTROL, 'reload_keep_cache'])
      Dir.mkdir(BLOCKLIST_DIR, 0o755) unless File.directory?(BLOCKLIST_DIR)
      do_install(UNBOUND_RELOADED, "#{Time.now.to_i}\n", nil, '0644')
    end

    def unbound_active?
      run_command(['/usr/bin/systemctl', 'is-active', '--quiet', 'unbound', { allow_failure: true }]).nil?
    end

    # Unbound's counters (unbound-control stats_noreset, with extended-statistics), and since when
    # they count: Unbound's start, or the last reload, whichever came later.
    def do_dns_stats
      return { 'running' => false } unless unbound_active?
      stats = capture([UNBOUND_CONTROL, 'stats_noreset']).lines.to_h { |line| line.strip.split('=', 2) }
      reloaded = File.exist?(UNBOUND_RELOADED) ? File.read(UNBOUND_RELOADED).to_i : 0
      { 'running' => true, 'since' => [Time.now.to_i - stats['time.up'].to_f.round, reloaded].max,
        'queries' => stats['total.num.queries'].to_i, 'answered_here' => stats['total.num.cachehits'].to_i,
        'secure' => stats['num.answer.secure'].to_i, 'bogus' => stats['num.answer.bogus'].to_i }
    rescue Failed => e
      { 'running' => true, 'error' => e.message }
    end

    # The address of a DHCP server that offers this machine an address on +interface+, other
    # than its own: a DHCPDISCOVER from the interface's MAC address, with the broadcast flag,
    # and the first other offer for it in DHCP_WAIT seconds.
    def do_dhcp_servers(interface)
      own = Socket.getifaddrs.select { |i| i.name == interface && i.addr&.ipv4? }.map { |i| i.addr.ip_address }
      mac = File.read("/sys/class/net/#{interface}/address").strip
      xid = SecureRandom.random_number(2**32)
      servers = []
      Socket.open(:INET, :DGRAM) do |socket|
        socket.setsockopt(:SOCKET, :REUSEADDR, true)
        socket.setsockopt(:SOCKET, :BROADCAST, true)
        socket.setsockopt(:SOCKET, :BINDTODEVICE, interface)
        socket.bind(Addrinfo.udp('0.0.0.0', 68))
        socket.send(dhcp_discover(xid, mac), 0, Addrinfo.udp('255.255.255.255', 67))
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DHCP_WAIT
        while (left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
          break unless IO.select([socket], nil, nil, left)
          data, sender = socket.recvfrom(1500)
          server = dhcp_offer_from(data, xid, sender.ip_address)
          next unless server && !own.include?(server)
          servers << server
          break
        end
      end
      { 'servers' => servers.uniq }
    rescue SystemCallError => e
      raise Failed, "couldn't look for other DHCP servers on #{interface}: #{e.message}"
    end

    # A DHCPDISCOVER (RFC 2131) from +mac+, asking for broadcast replies, padded to BOOTP's 300 bytes.
    def dhcp_discover(xid, mac)
      header = [1, 1, 6, 0, xid, 0, 0x8000, 0, 0, 0, 0].pack('CCCCNnnNNNN')
      chaddr = [mac.delete(':')].pack('H12').ljust(16, "\0")
      options = [0x63825363].pack('N') + [53, 1, 1, 55, 3, 1, 3, 6, 255].pack('C*')
      (header + chaddr + ("\0" * 192) + options).ljust(300, "\0")
    end

    # The server's address when +data+ is a DHCPOFFER for +xid+ (its server identifier, or
    # the address it came from), else nil.
    def dhcp_offer_from(data, xid, sender)
      data = data.b
      return unless data.bytesize >= 244 && data.getbyte(0) == 2 && data[4, 4].unpack1('N') == xid &&
                    data[236, 4].unpack1('N') == 0x63825363
      options = dhcp_options(data.byteslice(240..))
      return unless options[53] == "\x02".b
      options[54]&.bytesize == 4 ? options[54].unpack('C4').join('.') : sender
    end

    def dhcp_options(bytes)
      options = {}
      i = 0
      while i < bytes.bytesize
        code = bytes.getbyte(i)
        break if code == 255
        i += 1
        next if code.zero?
        length = bytes.getbyte(i) or break
        options[code] ||= bytes.byteslice(i + 1, length)
        i += 1 + length
      end
      options
    end

    # The addresses an Unbound config listens on, other than the NAS's own (127.0.0.1, ::1).
    def unbound_listening(content)
      content.each_line.filter_map do |line|
        address = line[/\A\s*interface:\s*(\S+)\s*\z/, 1]
        address if address && ip_address?(address) && !IPAddr.new(address).loopback?
      end.uniq
    end
  end
end
