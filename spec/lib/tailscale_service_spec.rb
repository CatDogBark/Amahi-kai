require 'rails_helper'

RSpec.describe TailscaleService do
  before do
    allow(Shell).to receive(:run).and_return(true)
  end

  describe '.installed?' do
    it 'returns true when binary exists' do
      allow(File).to receive(:exist?).with('/usr/bin/tailscale').and_return(true)
      expect(described_class.installed?).to be true
    end

    it 'returns false when binary missing' do
      allow(File).to receive(:exist?).with('/usr/bin/tailscale').and_return(false)
      expect(described_class.installed?).to be false
    end
  end

  describe '.running?' do
    before { allow(described_class).to receive(:installed?).and_return(true) }

    it 'returns true when BackendState is Running' do
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('{"BackendState":"Running"}')
      expect(described_class.running?).to be true
    end

    it 'returns false when not running' do
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('{"BackendState":"Stopped"}')
      expect(described_class.running?).to be false
    end

    it 'returns false when not installed' do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.running?).to be false
    end

    it 'returns false on empty output' do
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('')
      expect(described_class.running?).to be false
    end

    it 'returns false on invalid JSON' do
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('not json')
      expect(described_class.running?).to be false
    end
  end

  describe '.status' do
    it 'returns not installed when binary missing' do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.status).to eq({ installed: false, running: false })
    end

    it 'returns full status when running' do
      allow(described_class).to receive(:installed?).and_return(true)
      json = {
        'BackendState' => 'Running',
        'Self' => {
          'TailscaleIPs' => ['100.64.0.1'],
          'DNSName' => 'myhost.tail123.ts.net.',
          'OS' => 'linux',
          'Online' => true
        },
        'Peer' => { 'abc' => {}, 'def' => {} }
      }.to_json
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return(json)

      result = described_class.status
      expect(result[:installed]).to be true
      expect(result[:running]).to be true
      expect(result[:tailscale_ip]).to eq('100.64.0.1')
      expect(result[:hostname]).to eq('myhost.tail123.ts.net')
      expect(result[:peers]).to eq(2)
      expect(result[:magic_dns]).to eq('myhost.tail123.ts.net')
    end

    it 'handles empty output' do
      allow(described_class).to receive(:installed?).and_return(true)
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('')
      expect(described_class.status).to eq({ installed: true, running: false })
    end

    it 'handles parse errors gracefully' do
      allow(described_class).to receive(:installed?).and_return(true)
      allow(described_class).to receive(:`).with('sudo tailscale status --json 2>/dev/null').and_return('bad')
      result = described_class.status
      expect(result[:installed]).to be true
      expect(result[:running]).to be false
      expect(result[:error]).to be_present
    end
  end

  describe '.install!' do
    it 'downloads and runs install script' do
      allow(described_class).to receive(:system).with(/curl.*tailscale/).and_return(true)
      allow($?).to receive(:success?).and_return(true)
      allow(File).to receive(:exist?).with('/tmp/tailscale-install.sh').and_return(true)
      allow(described_class).to receive(:system).with(/sudo bash/).and_return(true)
      allow(FileUtils).to receive(:rm_f)

      expect(described_class.install!).to be true
    end

    it 'returns false if download fails' do
      allow(described_class).to receive(:system).and_return(false)
      allow($?).to receive(:success?).and_return(false)
      expect(described_class.install!).to be false
    end
  end

  describe '.start!' do
    it 'enables and starts tailscaled then brings up' do
      allow(described_class).to receive(:`).with('sudo tailscale status 2>&1').and_return('100.64.0.1 myhost')
      allow(described_class).to receive(:`).with('sudo timeout 5 tailscale up 2>&1').and_return('')

      result = described_class.start!
      expect(result[:success]).to be true
      expect(result[:auth_url]).to be_nil
      expect(Shell).to have_received(:run).with('systemctl enable tailscaled 2>/dev/null')
      expect(Shell).to have_received(:run).with('systemctl start tailscaled 2>/dev/null')
    end

    it 'returns auth URL when login needed' do
      allow(described_class).to receive(:`).with('sudo tailscale status 2>&1').and_return("Logged out. Login at: https://login.tailscale.com/a/abc123")

      result = described_class.start!
      expect(result[:success]).to be true
      expect(result[:needs_login]).to be true
      expect(result[:auth_url]).to eq('https://login.tailscale.com/a/abc123')
    end

    it 'returns error on exception' do
      allow(Shell).to receive(:run).and_raise(StandardError, 'boom')
      result = described_class.start!
      expect(result[:success]).to be false
      expect(result[:error]).to eq('boom')
    end
  end

  describe '.stop!' do
    it 'runs tailscale down' do
      described_class.stop!
      expect(Shell).to have_received(:run).with('tailscale down 2>/dev/null')
    end
  end

  describe '.logout!' do
    it 'logs out and stops the daemon' do
      described_class.logout!
      expect(Shell).to have_received(:run).with('tailscale logout 2>/dev/null')
      expect(Shell).to have_received(:run).with('systemctl stop tailscaled 2>/dev/null')
    end
  end
end
