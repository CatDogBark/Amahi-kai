require 'rails_helper'

RSpec.describe DnsService do
  let(:lan) { NetworkInterfaces::Address.new(ip: IPAddr.new('192.168.1.10'), prefix: 24) }
  let(:ula) { NetworkInterfaces::Address.new(ip: IPAddr.new('fd12:3456:789a::10'), prefix: 64) }
  let(:global) { NetworkInterfaces::Address.new(ip: IPAddr.new('2600:1700:abcd::10'), prefix: 64) }
  let(:link_local) { NetworkInterfaces::Address.new(ip: IPAddr.new('fe80::10'), prefix: 64) }
  let(:tailscale) { [] }

  before do
    allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [lan, ula, global, link_local], 'ens19' => [])
    allow(NetworkInterfaces).to receive(:default_name).and_return('ens18')
    allow(NetworkInterfaces).to receive(:addresses).and_return([])
    allow(NetworkInterfaces).to receive(:addresses).with('ens18').and_return([lan, ula, global, link_local])
    allow(NetworkInterfaces).to receive(:addresses).with('tailscale0').and_return(tailscale)
    allow(described_class).to receive(:hostname).and_return('kai')
    allow(described_class).to receive(:rewrite!).and_call_original
    allow(DnsmasqService).to receive(:rewrite_config!)
    allow(DnsmasqService).to receive(:apply!)
  end

  def lines = described_class.config.lines.map(&:strip)

  describe '.config' do
    it "listens on the NAS's own addresses, the interface's IPv4 and ULA, never 0.0.0.0" do
      listening = lines.grep(/\Ainterface:/)
      expect(listening).to eq(['interface: 127.0.0.1', 'interface: ::1', 'interface: 192.168.1.10',
                               'interface: fd12:3456:789a::10'])
      expect(lines).to include('ip-freebind: yes')
    end

    it 'answers the networks on the interface, IPv4 and IPv6' do
      expect(lines.grep(/\Aaccess-control:/)).to eq(['access-control: 192.168.1.0/24 allow',
                                                     'access-control: fd12:3456:789a::/64 allow',
                                                     'access-control: 2600:1700:abcd::/64 allow',
                                                     'access-control: fe80::/10 allow'])
    end

    context 'with Tailscale on' do
      let(:tailscale) do
        [NetworkInterfaces::Address.new(ip: IPAddr.new('100.64.96.4'), prefix: 32),
         NetworkInterfaces::Address.new(ip: IPAddr.new('fd7a:115c:a1e0::4'), prefix: 128),
         NetworkInterfaces::Address.new(ip: IPAddr.new('fe80::4'), prefix: 64)]
      end

      it "listens on Tailscale's addresses too, and answers its networks" do
        expect(lines).to include('interface: 100.64.96.4', 'interface: fd7a:115c:a1e0::4',
                                 'access-control: 100.64.0.0/10 allow', 'access-control: fd7a:115c:a1e0::/48 allow')
        expect(lines).not_to include('interface: fe80::4')
      end
    end

    it 'forwards over TLS to Quad9 by default, at all its addresses' do
      expect(lines).to include('forward-tls-upstream: yes', 'forward-addr: 9.9.9.9@853#dns.quad9.net',
                               'forward-addr: 2620:fe::9@853#dns.quad9.net', %(tls-cert-bundle: "#{DnsService::CA_CERTS}"))
    end

    it 'forwards to the provider picked' do
      Setting.set('dns_provider', 'dnssb')
      expect(lines.grep(/forward-addr/)).to eq(['forward-addr: 185.222.222.222@853#dot.sb', 'forward-addr: 45.11.45.11@853#dot.sb',
                                                'forward-addr: 2a09::@853#dot.sb', 'forward-addr: 2a11::@853#dot.sb'])
    end

    it 'forwards to a custom server at its addresses, under its TLS name' do
      Setting.set('dns_provider', 'custom')
      Setting.set('dns_custom_addresses', '192.168.1.53 fd00::53')
      Setting.set('dns_custom_tls_name', 'dns.example.org')
      expect(lines.grep(/forward-addr/)).to eq(['forward-addr: 192.168.1.53@853#dns.example.org',
                                                'forward-addr: fd00::53@853#dns.example.org'])
    end

    it 'drops outside answers naming addresses inside a home network, and tells Firefox to use it' do
      expect(lines).to include('private-address: 192.168.0.0/16', 'private-address: fd00::/8',
                               'local-zone: "use-application-dns.net." always_nxdomain')
    end

    it 'names the NAS, the fixed hosts and the DNS aliases, with and without the domain' do
      allow(DnsService).to receive(:rewrite!).and_return(true)
      Setting.set('net', '192.168.1')
      Host.create!(name: 'Printer', mac: 'aa:bb:cc:dd:ee:01', address: '20')
      DnsAlias.create!(name: 'files', address: '192.168.1.30')
      DnsAlias.create!(name: 'media', address: '')
      DnsAlias.create!(name: 'kai', address: '192.168.1.99') # the NAS's own name comes first
      expect(lines).to include('local-zone: "home.arpa." static',
                               'local-data: "kai.home.arpa. IN A 192.168.1.10"', 'local-data: "kai. IN A 192.168.1.10"',
                               'local-data: "kai.home.arpa. IN AAAA fd12:3456:789a::10"',
                               'local-data-ptr: "192.168.1.10 kai.home.arpa."',
                               'local-data: "printer.home.arpa. IN A 192.168.1.20"',
                               'local-data-ptr: "192.168.1.20 printer.home.arpa."',
                               'local-data: "files.home.arpa. IN A 192.168.1.30"', 'local-data: "files. IN A 192.168.1.30"',
                               'local-data: "media.home.arpa. IN A 192.168.1.10"')
      expect(lines.join("\n")).not_to include('192.168.1.99', '192.168.1.30 files', 'IN AAAA 2600:1700')
    end

    it "uses home.arpa when the domain setting is .local (mDNS's)" do
      Setting.set('domain', 'local')
      expect(lines).to include('local-zone: "home.arpa." static')
      Setting.set('domain', 'lan.example')
      expect(lines).to include('local-zone: "lan.example." static')
    end

    it 'writes only lines the root helper accepts' do
      Privileged.operations # loads libexec/amahi-helper
      expect { AmahiHelper.unbound_conf(described_class.config) }.not_to raise_error
    end
  end

  describe 'the modes' do
    it 'are off, DNS, and DNS + DHCP; anything else is off' do
      expect([described_class.mode, described_class.on?, described_class.dhcp?]).to eq(['off', false, false])
      Setting.set('dns_mode', 'dns')
      expect([described_class.on?, described_class.dhcp?]).to eq([true, false])
      Setting.set('dns_mode', 'dns_dhcp')
      expect([described_class.on?, described_class.dhcp?]).to eq([true, true])
      Setting.set('dns_mode', 'everything')
      expect(described_class.mode).to eq('off')
    end
  end

  describe '.lan_prefix' do
    it "is the network of the NAS's /24 address on the interface, else the net setting" do
      expect(described_class.lan_prefix).to eq('192.168.1')
      Setting.set('net', '10.0.0')
      allow(NetworkInterfaces).to receive(:addresses).with('ens18')
        .and_return([NetworkInterfaces::Address.new(ip: IPAddr.new('172.20.5.9'), prefix: 16)])
      expect(described_class.lan_prefix).to eq('10.0.0')
    end
  end

  describe '.interface' do
    it "is the one chosen while it's there, else the one the default route leaves by" do
      expect(described_class.interface).to eq('ens18')
      Setting.set('dns_interface', 'ens19')
      expect(described_class.interface).to eq('ens19')
      Setting.set('dns_interface', 'eth7')
      expect(described_class.interface).to eq('ens18')
    end
  end

  describe '.custom_problems' do
    it 'wants one to four addresses and a TLS name' do
      expect(described_class.custom_problems('9.9.9.9, 2620:fe::fe', 'dns.quad9.net')).to be_empty
      expect(described_class.custom_problems('', 'dns.quad9.net')).to eq(['Give one to four addresses'])
      expect(described_class.custom_problems('9.9.9.9 dns.google', 'x')).to eq(["dns.google isn't an address"])
      expect(described_class.custom_problems('1.1.1.1 1.0.0.1 1.1.1.2 1.0.0.2 1.1.1.3', 'one.one.one.one'))
        .to eq(['Give one to four addresses'])
      expect(described_class.custom_problems('9.9.9.9', 'not a name').last).to start_with('Give the TLS name')
    end
  end

  describe '.apply!' do
    before { allow(described_class).to receive(:installed?).and_return(true) }

    it 'writes the config and starts Unbound when DNS is turned on, then hands dnsmasq its part' do
      allow(described_class).to receive(:running?).and_return(false)
      Setting.set('dns_mode', 'dns')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable dns.blocking_off])
      expect(Privileged.calls[1]).to eq(['services.enable', { service: 'unbound' }])
      expect(DnsmasqService).to have_received(:apply!)
    end

    it 'restarts Unbound when it was running, with blocking as chosen' do
      allow(described_class).to receive(:running?).and_return(true)
      Setting.set('dns_mode', 'dns')
      Setting.set('dns_blocking', '1')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.restart dns.set_blocklists])
      expect(Privileged.calls.last.last).to eq(lists: %w[hagezi-normal hagezi-tif-mini], allow: [])
    end

    it 'stops Unbound and removes its config when DNS is turned off' do
      Setting.set('dns_mode', 'off')
      described_class.apply!
      expect(Privileged.calls).to eq([['services.disable', { service: 'unbound' }], ['dns.remove_config', {}]])
      expect(DnsmasqService).to have_received(:apply!)
    end

    it "does nothing to Unbound when it's off and not installed" do
      allow(described_class).to receive(:installed?).and_return(false)
      described_class.apply!
      expect(Privileged.calls).to be_empty
    end
  end

  describe '.rewrite!' do
    it 'does nothing while DNS is off' do
      expect(described_class.rewrite!).to be false
      expect(Privileged.calls).to be_empty
    end

    it 'rewrites the config and restarts Unbound while DNS is on' do
      allow(described_class).to receive_messages(installed?: true, running?: true)
      Setting.set('dns_mode', 'dns')
      expect(described_class.rewrite!).to be true
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.restart])
    end
  end

  describe 'blocking' do
    it 'starts with the recommended lists, until a choice is saved' do
      expect(described_class.blocklists).to eq(%w[hagezi-normal hagezi-tif-mini])
      Setting.set('dns_blocklists', 'oisd-big gone-list')
      expect(described_class.blocklists).to eq(%w[oisd-big])
      Setting.set('dns_blocklists', '')
      expect(described_class.blocklists).to eq([])
    end

    it 'reads the allowlist as typed: a line, a space or a comma apart, "*." and a final dot let go' do
      names, problems = described_class.parse_allowlist("Example.com\n*.cdn.example.net., ads.example.org  example.com\n")
      expect([names, problems]).to eq([%w[example.com cdn.example.net ads.example.org], []])
      expect(described_class.parse_allowlist('localhost 10.0.0.1 ok.example.com').last).to eq(['localhost, 10.0.0.1 aren\'t domains'])
    end

    it 'sends the lists and allowlist to the helper, or turns blocking off' do
      Setting.set('dns_blocking', '1')
      Setting.set('dns_allowlist', "example.com\ncdn.example.net")
      described_class.apply_blocking!
      expect(Privileged.calls.last).to eq(['dns.set_blocklists', { lists: %w[hagezi-normal hagezi-tif-mini], allow: %w[example.com cdn.example.net] }])
      Setting.set('dns_blocking', '0')
      described_class.apply_blocking!
      expect(Privileged.calls.last).to eq(['dns.blocking_off', {}])
    end

    it "reads the helper's last refresh, and how long a pause has left" do
      Dir.mktmpdir do |dir|
        stub_const('DnsService::BLOCKLIST_STATUS', "#{dir}/status.json")
        expect(described_class.blocking_status).to be_nil
        File.write("#{dir}/status.json", '{"blocked":5,"lists":{}}')
        expect(described_class.blocking_status['blocked']).to eq(5)
      end
      expect(described_class.paused_until).to be_nil
      Setting.set('dns_blocking_paused_until', (Time.now.to_i + 120).to_s)
      expect(described_class.paused_until).to be > Time.now
    end

    it 'knows the same lists as the root helper' do
      Privileged.operations # loads libexec/amahi-helper
      expect(described_class::BLOCKLISTS.keys).to match_array(AmahiHelper::BLOCKLISTS.keys)
      expect(AmahiHelper::BLOCKLISTS.values.map { |list| list[:url] }).to all(start_with('https://'))
      expect(described_class::BLOCKLISTS.values.count { |list| list[:default] }).to eq(2)
      expect(described_class::BLOCKLISTS.values.count { |list| list[:vendor] }).to eq(8)
    end
  end

  describe 'IPv6' do
    it 'makes its own unique local range once, and keeps it' do
      prefix = described_class.ula_prefix
      expect(prefix).to match(/\Afd[0-9a-f]{2}:[0-9a-f]{4}:[0-9a-f]{4}\z/)
      expect(described_class.ula_prefix).to eq(prefix)
      Setting.set('dns_ula_prefix', 'fdab:cdef:1234')
      expect([described_class.own_ipv6_address, described_class.own_ipv6_network]).to eq(%w[fdab:cdef:1234::53 fdab:cdef:1234::/64])
    end

    it 'listens on, answers and names the address it announces, while it does' do
      Setting.set('dns_ula_prefix', 'fdab:cdef:1234')
      expect(lines).not_to include('interface: fdab:cdef:1234::53')
      Setting.set('dns_ipv6_advertise', '1')
      expect(lines).to include('interface: fdab:cdef:1234::53', 'access-control: fdab:cdef:1234::/64 allow',
                               'local-data: "kai.home.arpa. IN AAAA fdab:cdef:1234::53"')
      expect(described_class.ipv6_server_address).to eq('fdab:cdef:1234::53')
    end

    it 'leaves its own address out once it stops announcing, though the address is still on the interface' do
      Setting.set('dns_ula_prefix', 'fdab:cdef:1234')
      own = NetworkInterfaces::Address.new(ip: IPAddr.new('fdab:cdef:1234::53'), prefix: 64)
      allow(NetworkInterfaces).to receive(:addresses).with('ens18').and_return([lan, ula, own])
      expect(lines.join("\n")).not_to include('fdab:cdef:1234')
      expect(lines).to include('interface: fd12:3456:789a::10')
      Setting.set('dns_ipv6_advertise', '1')
      expect(lines).to include('interface: fdab:cdef:1234::53')
    end

    it "uses a unique local address the router hands out, while the NAS doesn't announce one" do
      expect(described_class.ipv6_server_address).to eq('fd12:3456:789a::10')
    end

    it 'announces the NAS as the DNS server and its range, never as a router, in lines the root helper accepts' do
      Setting.set('dns_ula_prefix', 'fdab:cdef:1234')
      conf = described_class.radvd_config
      expect(conf).to include('interface ens18 {', 'AdvDefaultLifetime 0;', 'prefix fdab:cdef:1234::/64 {', 'RDNSS fdab:cdef:1234::53 {',
                              'DNSSL home.arpa {')
      Privileged.operations # loads libexec/amahi-helper
      expect { AmahiHelper.radvd_conf(conf) }.not_to raise_error
    end

    it 'puts its address up before Unbound listens, and starts radvd, while it announces' do
      allow(described_class).to receive_messages(installed?: true, running?: false, radvd_installed?: true, radvd_running?: false)
      Setting.set('dns_mode', 'dns')
      Setting.set('dns_ipv6_advertise', '1')
      Setting.set('dns_ula_prefix', 'fdab:cdef:1234')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.set_own_address dns.write_config services.enable dns.blocking_off
                                                     dns.write_radvd_config services.enable])
      expect(Privileged.calls.first.last).to eq(interface: 'ens18', address: 'fdab:cdef:1234::53')
      expect(Privileged.calls.last.last).to eq(service: 'radvd')
    end

    it 'stops announcing, and takes its address away, when that or DNS is turned off' do
      Dir.mktmpdir do |dir|
        stub_const('DnsService::RADVD_CONF', "#{dir}/radvd.conf")
        stub_const('DnsService::ULA_UNIT', "#{dir}/amahi-kai-ula.service")
        File.write("#{dir}/radvd.conf", '')
        File.write("#{dir}/amahi-kai-ula.service", '')
        allow(described_class).to receive_messages(installed?: true, radvd_installed?: true)
        described_class.apply!
        expect(Privileged.calls.map(&:first)).to eq(%w[services.disable dns.remove_config services.disable dns.remove_radvd_config
                                                       dns.remove_own_address])
      end
    end

    it 'keeps what the routers announce, and finds the DNS servers that are not the NAS' do
      allow(Privileged).to receive(:call).with('dns.check_routers', interface: 'ens18').and_return(
        'ok' => true, 'advertisers' => [{ 'router' => 'fe80::1', 'lifetime' => 1800, 'prefixes' => ['2600:1700:abcd::/64'],
                                          'dns' => %w[2600:1700:abcd::1 fd12:3456:789a::10], 'domains' => [] }]
      )
      described_class.check_routers!
      expect(described_class.ipv6_check).to include('interface' => 'ens18', 'checked_at' => be_within(5).of(Time.now.to_i))
      expect(described_class.other_ipv6_dns).to eq([['fe80::1', '2600:1700:abcd::1']])
    end
  end

  describe 'router mode' do
    let(:dir) { Dir.mktmpdir }

    before do
      allow(described_class).to receive_messages(installed?: true, running?: false)
      stub_const('DnsService::ROUTER_STATE', "#{dir}/router.json")
      stub_const('DnsService::UFW_CONF', "#{dir}/ufw.conf")
      File.write("#{dir}/ufw.conf", "ENABLED=yes\n")
    end

    after { FileUtils.rm_rf(dir) }

    it 'is DHCP too, with an internet interface the NAS has' do
      Setting.set('dns_mode', 'router')
      expect([described_class.dhcp?, described_class.router?]).to eq([true, true])
      expect(described_class.wan_interface).to be_nil
      Setting.set('dns_wan_interface', 'ens19')
      expect(described_class.wan_interface).to eq('ens19')
      Setting.set('dns_wan_interface', 'eth9')
      expect(described_class.wan_interface).to be_nil
    end

    it "puts the router's rules in last, with the forwards, and takes them out when the mode changes" do
      Setting.set('dns_mode', 'router')
      Setting.set('dns_wan_interface', 'ens19')
      Setting.set('net', '192.168.1')
      allow(described_class).to receive(:rewrite_router!)
      PortForward.create!(protocol: 'udp', port: 5000, address: '60')
      described_class.apply!
      ops = Privileged.calls.map(&:first)
      expect(ops.last).to eq('network.router_on')
      expect(ops.index('network.router_on')).to be > ops.index('services.enable')
      expect(Privileged.calls.last.last).to eq(lan: 'ens18', wan: 'ens19', forwards: [{ protocol: 'udp', port: 5000, address: '192.168.1.60', to_port: 5000 }],
                                               dns: '192.168.1.10')
      Privileged.calls.clear
      File.write(described_class::ROUTER_STATE, '{"lan":"ens18","wan":"ens19","forwards":[]}')
      Setting.set('dns_mode', 'dns_dhcp')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to include('network.router_off')
      expect(described_class.router_state).to include('wan' => 'ens19')
    end

    it "sends devices' lookups to the NAS unless that's turned off, and adds the encrypted-DNS list to blocking" do
      Setting.set('dns_mode', 'router')
      Setting.set('dns_wan_interface', 'ens19')
      expect(described_class.force_dns?).to be true
      expect(described_class.blocklists_in_force).to eq(%w[hagezi-normal hagezi-tif-mini hagezi-doh])
      Setting.set('dns_force_nas', '0')
      expect(described_class.blocklists_in_force).to eq(%w[hagezi-normal hagezi-tif-mini])
      described_class.rewrite_router!
      expect(Privileged.calls.last.last[:dns]).to be_nil
      Setting.set('dns_mode', 'dns')
      Setting.set('dns_force_nas', '1')
      expect(described_class.blocklists_in_force).to eq(%w[hagezi-normal hagezi-tif-mini]) # only the router can redirect
    end

    it 'rewrites the rules for a port forward only while the NAS is the router' do
      expect(described_class.rewrite_router!).to be false
      Setting.set('dns_mode', 'router')
      Setting.set('dns_wan_interface', 'ens19')
      expect(described_class.rewrite_router!).to be true
      expect(Privileged.calls.map(&:first)).to eq(%w[network.router_on])
    end
  end

  describe '.totals' do
    it "are the helper's counts, or nil without them" do
      expect(described_class.totals).to be_nil # the simulated helper counts nothing
      allow(Privileged).to receive(:call).with('dns.stats').and_return('ok' => true, 'queries' => 5, 'answered_here' => 2)
      expect(described_class.totals['queries']).to eq(5)
      allow(Privileged).to receive(:call).with('dns.stats').and_raise(Privileged::Error.new('dns.stats', 'unbound-control exited 1'))
      expect(described_class.totals).to be_nil
    end

    it 'has Unbound count DNSSEC answers too' do
      expect(lines).to include('extended-statistics: yes')
    end
  end

  describe '.check' do
    it 'times a lookup of the NAS and of an outside name, nil for one that fails' do
      resolver = instance_double(Resolv::DNS, :timeouts= => nil, close: nil)
      allow(Resolv::DNS).to receive(:new).with(nameserver_port: [['127.0.0.1', 53]]).and_return(resolver)
      allow(resolver).to receive(:getaddress).with('kai.home.arpa').and_return(Resolv::IPv4.create('192.168.1.10'))
      allow(resolver).to receive(:getaddress).with('example.com').and_raise(Resolv::ResolvError)
      result = described_class.check
      expect(result[:local]).to be_a(Integer)
      expect(result[:outside]).to be_nil
    end
  end
end
