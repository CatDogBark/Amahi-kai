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
      allow(described_class).to receive(:`).with('systemctl is-active dnsmasq 2>/dev/null').and_return("active\n")
      expect(described_class.running?).to be true
    end

    it 'returns false when not installed' do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.running?).to be false
    end

    it 'returns false when inactive' do
      allow(described_class).to receive(:installed?).and_return(true)
      allow(described_class).to receive(:`).with('systemctl is-active dnsmasq 2>/dev/null').and_return("inactive\n")
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

  describe '.start!' do
    it 'starts dnsmasq now and at boot' do
      described_class.start!
      expect(Privileged.calls).to eq([['services.enable', { service: 'dnsmasq' }]])
    end
  end

  describe '.stop!' do
    it 'stops dnsmasq now and at boot' do
      described_class.stop!
      expect(Privileged.calls).to eq([['services.disable', { service: 'dnsmasq' }]])
    end
  end

  describe '.write_config!' do
    before { allow(described_class).to receive(:running?).and_return(false) }

    def written
      Privileged.calls.find { |op, _| op == 'network.write_dnsmasq_config' }&.last&.fetch(:content)
    end

    it 'writes DHCP config when dhcp_enabled' do
      described_class.write_config!(
        net: '192.168.1', dyn_lo: 100, dyn_hi: 200,
        gateway: '1', lease_time: 86400, domain: 'home',
        dhcp_enabled: true, dns_enabled: false
      )

      expect(written).to include('dhcp-range=192.168.1.100,192.168.1.200,86400s')
      expect(written).to include('dhcp-option=option:router,192.168.1.1')
      expect(written).to include('dhcp-authoritative')
      expect(written).not_to include('local=/home/')
    end

    it 'writes DNS config when dns_enabled' do
      described_class.write_config!(dns_enabled: true, domain: 'mynet')
      expect(written).to include('local=/mynet/')
      expect(written).to include('expand-hosts')
      expect(written).to include('domain=mynet')
    end

    it 'always includes bind-interfaces and except-interface' do
      described_class.write_config!
      expect(written).to include('bind-interfaces')
      expect(written).to include('except-interface=lo')
    end

    it 'writes only lines the root helper accepts' do
      described_class.write_config!(net: '10.0.0', dyn_lo: 50, dyn_hi: 99, gateway: '254', lease_time: 600,
                                    domain: 'home.lan', dhcp_enabled: true, dns_enabled: true)
      Privileged.operations # loads libexec/amahi-helper
      expect { AmahiHelper.dnsmasq_conf(written, AmahiHelper::DNSMASQ_LINES) }.not_to raise_error
    end

    it 'restarts if running' do
      allow(described_class).to receive(:running?).and_return(true)
      described_class.write_config!
      expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config services.restart])
    end

    it 'does not restart if not running' do
      described_class.write_config!
      expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config])
    end

    it "raises the helper's reason when the config is refused" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.write_dnsmasq_config', 'refused'))
      expect { described_class.write_config! }.to raise_error(Privileged::Error, 'refused')
    end
  end
end
