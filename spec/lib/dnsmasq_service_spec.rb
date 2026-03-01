require 'rails_helper'

RSpec.describe DnsmasqService do
  before do
    allow(Shell).to receive(:run).and_return(true)
  end

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
    it 'runs systemctl restart' do
      described_class.restart!
      expect(Shell).to have_received(:run).with('systemctl restart dnsmasq.service')
    end
  end

  describe '.start!' do
    it 'enables and starts the service' do
      described_class.start!
      expect(Shell).to have_received(:run).with('systemctl enable dnsmasq.service 2>/dev/null')
      expect(Shell).to have_received(:run).with('systemctl start dnsmasq.service 2>/dev/null')
    end
  end

  describe '.stop!' do
    it 'stops and disables the service' do
      described_class.stop!
      expect(Shell).to have_received(:run).with('systemctl stop dnsmasq.service 2>/dev/null')
      expect(Shell).to have_received(:run).with('systemctl disable dnsmasq.service 2>/dev/null')
    end
  end

  describe '.write_config!' do
    let(:staged_path) { File.join(DnsmasqService::STAGING_DIR, 'dnsmasq-amahi.conf') }

    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with(staged_path, anything)
      allow(described_class).to receive(:running?).and_return(false)
    end

    it 'writes DHCP config when dhcp_enabled' do
      config_content = nil
      allow(File).to receive(:write).with(staged_path, anything) do |_, content|
        config_content = content
      end

      described_class.write_config!(
        net: '192.168.1', dyn_lo: 100, dyn_hi: 200,
        gateway: '1', lease_time: 86400, domain: 'home',
        dhcp_enabled: true, dns_enabled: false
      )

      expect(config_content).to include('dhcp-range=192.168.1.100,192.168.1.200,86400s')
      expect(config_content).to include('dhcp-option=option:router,192.168.1.1')
      expect(config_content).to include('dhcp-authoritative')
      expect(config_content).not_to include('local=/home/')
    end

    it 'writes DNS config when dns_enabled' do
      config_content = nil
      allow(File).to receive(:write).with(staged_path, anything) do |_, content|
        config_content = content
      end

      described_class.write_config!(dns_enabled: true, domain: 'mynet')
      expect(config_content).to include('local=/mynet/')
      expect(config_content).to include('expand-hosts')
      expect(config_content).to include('domain=mynet')
    end

    it 'always includes bind-interfaces and except-interface' do
      config_content = nil
      allow(File).to receive(:write).with(staged_path, anything) do |_, content|
        config_content = content
      end

      described_class.write_config!
      expect(config_content).to include('bind-interfaces')
      expect(config_content).to include('except-interface=lo')
    end

    it 'copies staged file to config path' do
      described_class.write_config!
      expect(Shell).to have_received(:run).with("cp #{staged_path} #{DnsmasqService::CONFIG_PATH}")
    end

    it 'restarts if running' do
      allow(described_class).to receive(:running?).and_return(true)
      described_class.write_config!
      expect(Shell).to have_received(:run).with('systemctl restart dnsmasq.service')
    end

    it 'does not restart if not running' do
      described_class.write_config!
      expect(Shell).not_to have_received(:run).with('systemctl restart dnsmasq.service')
    end
  end
end
