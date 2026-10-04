require 'rails_helper'

RSpec.describe TailscaleService do
  def status_json(state, **extra)
    { 'BackendState' => state }.merge(extra).to_json
  end

  def tailscale_status(out, success: true)
    allow(Open3).to receive(:capture3).with('/usr/bin/tailscale', 'status', '--json')
                                      .and_return([out, '', instance_double(Process::Status, success?: success)])
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

    it 'reads the status as the app user (no root) and is true when BackendState is Running' do
      tailscale_status(status_json('Running'))
      expect(described_class.running?).to be true
    end

    it 'returns false when not running' do
      tailscale_status(status_json('Stopped'))
      expect(described_class.running?).to be false
    end

    it 'returns false when not installed' do
      allow(described_class).to receive(:installed?).and_return(false)
      expect(described_class.running?).to be false
    end

    it 'returns false when the status cannot be read' do
      tailscale_status('', success: false)
      expect(described_class.running?).to be false
      tailscale_status('not json')
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
      tailscale_status(status_json('Running',
                                   'Self' => { 'TailscaleIPs' => ['100.64.0.1'], 'DNSName' => 'myhost.tail123.ts.net.',
                                               'OS' => 'linux', 'Online' => true },
                                   'Peer' => { 'abc' => {}, 'def' => {} }))

      result = described_class.status
      expect(result).to include(installed: true, running: true, tailscale_ip: '100.64.0.1',
                                hostname: 'myhost.tail123.ts.net', peers: 2, magic_dns: 'myhost.tail123.ts.net')
    end

    it 'reports installed but not running when the status cannot be read' do
      allow(described_class).to receive(:installed?).and_return(true)
      tailscale_status('not json')
      expect(described_class.status).to eq({ installed: true, running: false })
    end
  end

  describe '.install!' do
    it "installs from Tailscale's apt repository through the root helper and starts the daemon" do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('packages.install', packages: ['tailscale']) do |*_args, &block|
        block.call('Setting up tailscale (1.90.1) ...')
        { 'ok' => true }
      end
      lines = []
      expect(described_class.install! { |line| lines << line }).to be true
      expect(Privileged.calls).to eq([['packages.add_repository', { repository: 'tailscale' }], ['tailscale.start', {}]])
      expect(lines).to eq(['Setting up tailscale (1.90.1) ...'])
    end

    it "raises the helper's reason" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.add_repository', 'curl exited 22'))
      expect { described_class.install! }.to raise_error(TailscaleService::TailscaleError, 'curl exited 22')
    end
  end

  describe '.start!' do
    before { allow(described_class).to receive(:installed?).and_return(true) }

    it 'starts the daemon and stops there when Tailscale is already up' do
      tailscale_status(status_json('Running'))
      expect(described_class.start!).to eq(success: true, auth_url: nil)
      expect(Privileged.calls).to eq([['tailscale.start', {}]])
    end

    it "brings it up and returns the login URL `tailscale up` prints" do
      tailscale_status(status_json('NeedsLogin'))
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('tailscale.up') do |*_args, &block|
        ["\n", 'To authenticate, visit:', "\thttps://login.tailscale.com/a/abc123"].each { |line| block.call(line) }
        { 'ok' => true, 'notes' => ['ignored: timeout exited 124'] }
      end
      lines = []
      result = described_class.start! { |line| lines << line }
      expect(result).to eq(success: true, auth_url: 'https://login.tailscale.com/a/abc123')
      expect(lines).to include('To authenticate, visit:')
    end

    it "returns the helper's reason when it fails" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('tailscale.start', "tailscale isn't installed"))
      expect(described_class.start!).to eq(success: false, error: "tailscale isn't installed")
    end
  end

  describe '.stop! and .logout!' do
    it 'go through the root helper' do
      expect(described_class.stop!).to be true
      expect(described_class.logout!).to be true
      expect(Privileged.calls.map(&:first)).to eq(%w[tailscale.down tailscale.logout])
    end

    it 'return false when the helper fails' do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('tailscale.down', 'tailscale exited 1'))
      expect(described_class.stop!).to be false
    end
  end
end
