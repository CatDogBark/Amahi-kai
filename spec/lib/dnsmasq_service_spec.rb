require 'rails_helper'

RSpec.describe DnsmasqService do
  describe '.installed?' do
    it 'returns true when dnsmasq binary exists' do
      allow(File).to receive(:exist?).with('/usr/sbin/dnsmasq').and_return(true)
      expect(described_class.installed?).to be true
    end

    it 'returns false when dnsmasq binary is missing' do
      allow(File).to receive(:exist?).with('/usr/sbin/dnsmasq').and_return(false)
      expect(described_class.installed?).to be false
    end
  end

  describe '.running?' do
    it 'returns true when active' do
      allow(described_class).to receive(:installed?).and_return(true)
      allow(Shell).to receive(:output).with('systemctl', 'is-active', 'dnsmasq').and_return("active\n")
      expect(described_class.running?).to be true
    end

    it 'returns false when not installed' do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.running?).to be false
    end

    it 'returns false when inactive' do
      allow(described_class).to receive(:installed?).and_return(true)
      allow(Shell).to receive(:output).with('systemctl', 'is-active', 'dnsmasq').and_return("inactive\n")
      expect(described_class.running?).to be false
    end
  end

  describe '.restart!' do
    it 'restarts dnsmasq through the root helper when it is running' do
      allow(described_class).to receive(:running?).and_return(true)
      expect(described_class.restart!).to be true
      expect(Privileged.calls).to eq([['services.restart', { service: 'dnsmasq' }]])
    end

    it 'does nothing when dnsmasq is not running' do
      allow(described_class).to receive(:running?).and_return(false)
      expect(described_class.restart!).to be true
      expect(Privileged.calls).to be_empty
    end

    it 'reports a failure instead of raising' do
      allow(described_class).to receive(:running?).and_return(true)
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('services.restart', 'exit 1'))
      expect(described_class.restart!).to be false
    end
  end

  describe '.settings_problems' do
    it 'wants a range of at least ten addresses, without the NAS, a router and a lease time from the list' do
      expect(described_class.settings_problems(100, 200, 1, 14_400, 10)).to be_empty
      expect(described_class.settings_problems(200, 100, 1, 14_400, 10)).to include(/from 2 to 254/)
      expect(described_class.settings_problems(100, 105, 1, 14_400, 10)).to include(/at least 10 addresses/)
      expect(described_class.settings_problems(2, 254, 1, 14_400, 10)).to include("The range takes in the NAS's own address (.10)")
      expect(described_class.settings_problems(100, 200, 0, 14_400, 10)).to include(/router's address/)
      expect(described_class.settings_problems(100, 200, 1, 99, 10)).to include('Choose a lease time')
    end
  end

  describe '.write_config!' do
    before { allow(described_class).to receive(:running?).and_return(false) }

    def written
      Privileged.calls.find { |op, _| op == 'network.write_dnsmasq_config' }&.last&.fetch(:content)
    end

    let(:dhcp) { { net: '10.99.0', first: 100, last: 200, router: 1, lease_time: 86_400, interface: 'ens19', dhcp_enabled: true } }

    it 'hands out addresses on the interface DNS serves, and nowhere else' do
      described_class.write_config!(dhcp)
      expect(written.lines.map(&:strip)).to include('interface=ens19', 'bind-interfaces', 'dhcp-range=10.99.0.100,10.99.0.200,86400s',
                                                    'dhcp-option=option:router,10.99.0.1', 'dhcp-authoritative')
      expect(written).not_to include('except-interface')
    end

    it 'answers no DNS: Unbound does' do
      described_class.write_config!(dhcp)
      expect(written.lines.map(&:strip)).to include('port=0')
      expect(written).not_to include('local=/', 'expand-hosts')
    end

    it 'hands out the NAS as the DNS server, and its domain' do
      allow(DnsService).to receive_messages(on?: true, server_addresses: ['10.99.0.1'], domain: 'home.arpa')
      described_class.write_config!(dhcp)
      expect(written).to include('dhcp-option=option:dns-server,10.99.0.1', 'domain=home.arpa')
    end

    it 'hands out the NAS as the router while the NAS is the router' do
      allow(DnsService).to receive_messages(server_addresses: ['10.99.0.1'])
      described_class.write_config!(dhcp.merge(router_is_nas: true))
      expect(written).to include('dhcp-option=option:router,10.99.0.1')
      expect(written).not_to include('option:router,10.99.0.1,')
    end

    it 'hands out nothing while DHCP is off' do
      described_class.write_config!(dhcp.merge(dhcp_enabled: false))
      expect(written.lines.map(&:strip)).to include('port=0', 'bind-interfaces', 'except-interface=lo')
      expect(written).not_to include('dhcp-range', 'interface=ens19')
    end

    it 'gives each static host its address and name (Network → Hosts)' do
      allow(DnsmasqService).to receive(:rewrite_config!)
      allow(DnsService).to receive(:rewrite!)
      Host.create!(name: 'Printer', mac: 'AA:BB:CC:DD:EE:01', address: '20')
      described_class.write_config!(dhcp)
      expect(written).to include('dhcp-host=aa:bb:cc:dd:ee:01,10.99.0.20,printer')
    end

    it 'writes only lines the root helper accepts' do
      allow(DnsmasqService).to receive(:rewrite_config!)
      allow(DnsService).to receive(:rewrite!)
      allow(DnsService).to receive_messages(on?: true, server_addresses: ['10.0.0.2'], domain: 'home.lan')
      Host.create!(name: 'nas-backup', mac: 'aa:bb:cc:dd:ee:02', address: '21')
      described_class.write_config!(dhcp.merge(net: '10.0.0', first: 50, last: 99, router: 254, lease_time: 3600))
      Privileged.operations # loads libexec/amahi-helper
      expect { AmahiHelper.dnsmasq_conf(written, AmahiHelper::DNSMASQ_LINES) }.not_to raise_error
      described_class.write_config!(dhcp_enabled: false)
      expect { AmahiHelper.dnsmasq_conf(written, AmahiHelper::DNSMASQ_LINES) }.not_to raise_error
    end

    it 'restarts if running' do
      allow(described_class).to receive(:running?).and_return(true)
      described_class.write_config!
      expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config services.restart])
    end

    it "raises the helper's reason when the config is refused" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.write_dnsmasq_config', 'refused'))
      expect { described_class.write_config! }.to raise_error(Privileged::Error, 'refused')
    end
  end

  describe 'from the saved settings' do
    before do
      allow(described_class).to receive_messages(installed?: true, running?: false)
      allow(DnsService).to receive_messages(lan_prefix: '10.99.0', interface: 'ens19')
    end

    def written
      Privileged.calls.select { |op, _| op == 'network.write_dnsmasq_config' }.last.last[:content]
    end

    it "rewrites the config, handing out addresses only in DNS + DHCP" do
      Setting.set('dyn_lo', '120')
      Setting.set('dns_mode', 'dns')
      expect(described_class.rewrite_config!).to be true
      expect(written).not_to include('dhcp-range')
      Setting.set('dns_mode', 'dns_dhcp')
      described_class.rewrite_config!
      expect(written).to include('dhcp-range=10.99.0.120,10.99.0.254,14400s', 'interface=ens19')
    end

    it "does nothing when dnsmasq isn't installed" do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.rewrite_config!).to be false
      expect(described_class.apply!).to be false
      expect(Privileged.calls).to be_empty
    end

    it 'starts dnsmasq in DNS + DHCP, and stops it otherwise' do
      Setting.set('dns_mode', 'dns_dhcp')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config services.enable])
      Privileged.calls.clear
      Setting.set('dns_mode', 'dns')
      described_class.apply!
      expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config services.disable])
    end
  end

  describe '.other_servers' do
    it "asks the root helper, the way a device would" do
      allow(Privileged).to receive(:call).with('dhcp.check_servers', interface: 'ens19').and_return('ok' => true, 'servers' => ['10.99.0.7'])
      expect(described_class.other_servers('ens19')).to eq(['10.99.0.7'])
    end
  end
end
