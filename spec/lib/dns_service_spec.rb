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

    it 'writes the config and starts Unbound when DNS is turned on, then rewrites dnsmasq' do
      allow(described_class).to receive(:running?).and_return(false)
      Setting.set('dns_mode', 'dns')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable])
      expect(Privileged.calls.last).to eq(['services.enable', { service: 'unbound' }])
      expect(DnsmasqService).to have_received(:rewrite_config!)
    end

    it 'restarts Unbound when it was running' do
      allow(described_class).to receive(:running?).and_return(true)
      Setting.set('dns_mode', 'dns')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.restart])
    end

    it 'stops Unbound and removes its config when DNS is turned off' do
      Setting.set('dns_mode', 'off')
      described_class.apply!
      expect(Privileged.calls).to eq([['services.disable', { service: 'unbound' }], ['dns.remove_config', {}]])
      expect(DnsmasqService).to have_received(:rewrite_config!)
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
