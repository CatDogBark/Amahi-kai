require 'spec_helper'
require 'network_address'
require 'tempfile'

RSpec.describe NetworkAddress do
  let(:address) { NetworkInterfaces::Address }
  let(:ens18) { [address.new(ip: IPAddr.new('192.168.1.13'), prefix: 24)] }
  let(:ens19) { [address.new(ip: IPAddr.new('10.99.0.1'), prefix: 24), address.new(ip: IPAddr.new('fd99::1'), prefix: 64)] }

  before do
    Privileged.reset!
    allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => ens18, 'ens19' => ens19, 'ens20' => [])
    allow(NetworkInterfaces).to receive(:default_routes).and_return([['ens20', '10.77.0.1', 50], ['ens18', '192.168.1.1', 200]])
    allow(described_class).to receive(:state).and_return(nil)
  end

  describe '.interfaces' do
    it "lists each interface with its IPv4 addresses, how it got them, its router and its part" do
      allow(DnsService).to receive_messages(router_state: { 'lan' => 'ens19', 'wan' => 'ens20' }, interface: 'ens19')
      allow(Shell).to receive(:output).with('ip', '-j', '-4', 'addr', 'show', 'dev', 'ens18')
                                      .and_return('[{"ifname":"ens18","addr_info":[{"local":"192.168.1.13","dynamic":true}]}]')
      allow(Shell).to receive(:output).with('ip', '-j', '-4', 'addr', 'show', 'dev', 'ens19')
                                      .and_return('[{"ifname":"ens19","addr_info":[{"local":"10.99.0.1"}]}]')
      allow(Shell).to receive(:output).with('ip', '-j', '-4', 'addr', 'show', 'dev', 'ens20').and_return('')
      rows = described_class.interfaces
      expect(rows.map(&:name)).to eq(%w[ens18 ens19 ens20])
      expect(rows[0]).to have_attributes(automatic: true, gateway: '192.168.1.1', part: nil, fixed?: false)
      expect(rows[0].addresses.map(&:to_s)).to eq(['192.168.1.13'])
      expect(rows[1]).to have_attributes(automatic: false, gateway: nil, part: :lan, fixed?: true)
      expect(rows[1].addresses.map(&:to_s)).to eq(['10.99.0.1']) # IPv6 left out
      expect(rows[2]).to have_attributes(automatic: false, gateway: '10.77.0.1', part: :internet, fixed?: false)
    end
  end

  it 'reads the DNS servers the NAS itself asks, IPv4 only' do
    Tempfile.create('resolv') do |file|
      file.write("# This is /run/systemd/resolve/resolv.conf\nnameserver 192.168.1.1\nnameserver fd99::1\nnameserver 9.9.9.9\nsearch home.arpa\n")
      file.flush
      expect(described_class.nameservers(file.path)).to eq(%w[192.168.1.1 9.9.9.9])
    end
    expect(described_class.nameservers('/nonexistent/resolv.conf')).to eq([])
  end

  describe 'a change' do
    before do
      allow(DnsService).to receive(:lan_address).and_return(address.new(ip: IPAddr.new('10.99.0.5'), prefix: 24))
      allow(DnsService).to receive(:apply!)
      allow(SambaService).to receive(:push_config)
    end

    it 'asks the helper, and what follows the address follows at once when the admin came in elsewhere' do
      described_class.change!(interface: 'ens19', mode: 'fixed', guard: false, address: '10.99.0.5/24', gateway: '', dns: ['10.99.0.1'])
      expect(Privileged.calls).to eq([['network.set_address', { interface: 'ens19', mode: 'fixed', guard: false, address: '10.99.0.5/24', gateway: nil, dns: ['10.99.0.1'] }]])
      expect(Setting.get('net')).to eq('10.99.0')
      expect(Setting.get('self-address')).to eq('5')
      expect(DnsService).to have_received(:apply!)
      expect(SambaService).to have_received(:push_config)
    end

    it 'waits to be reached when the admin came in through the interface, and settles on keep!' do
      described_class.change!(interface: 'ens19', mode: 'automatic', guard: true)
      expect(Privileged.calls).to eq([['network.set_address', { interface: 'ens19', mode: 'automatic', guard: true }]])
      expect(DnsService).not_to have_received(:apply!)
      described_class.keep!
      expect(Privileged.calls.last).to eq(['network.keep_address', {}])
      expect(DnsService).to have_received(:apply!)
    end
  end

  describe 'where a change stands' do
    it 'is pending while the helper waits, and recent for a while after' do
      allow(described_class).to receive(:state).and_return('state' => 'pending', 'interface' => 'ens19', 'since' => Time.now.to_i - 10, 'until' => Time.now.to_i + 80)
      expect(described_class.pending?).to be true
      expect(described_class.recent['interface']).to eq('ens19')
      allow(described_class).to receive(:state).and_return('state' => 'pending', 'since' => Time.now.to_i - 3600, 'until' => Time.now.to_i - 3500)
      expect(described_class.pending?).to be false # the helper's timer has long fired
      expect(described_class.recent).to be_nil
      allow(described_class).to receive(:state).and_return('state' => 'kept', 'since' => Time.now.to_i - 60, 'until' => nil)
      expect(described_class.pending?).to be false
      expect(described_class.recent['state']).to eq('kept')
    end
  end

  describe 'where a request came in' do
    let(:socket) { instance_double(TCPSocket, local_address: Addrinfo.tcp('::ffff:10.99.0.1', 3000)) }

    before { allow(NetworkInterfaces).to receive(:all).and_return('ens18' => ens18, 'ens19' => ens19) }

    it 'names the interface by the address Puma accepted on, IPv4-mapped or not' do
      expect(described_class.arrival_address('puma.socket' => socket)).to eq('10.99.0.1')
      expect(described_class.arrival_interface('puma.socket' => socket)).to eq('ens19')
      expect(described_class.arrival_interface('puma.socket' => instance_double(TCPSocket, local_address: Addrinfo.tcp('192.168.1.13', 3000)))).to eq('ens18')
    end

    it 'has no answer without a socket (a test) or for an address no interface has' do
      expect(described_class.arrival_interface({})).to be_nil
      expect(described_class.arrival_interface('puma.socket' => instance_double(TCPSocket, local_address: Addrinfo.tcp('127.0.0.1', 3000)))).to be_nil
    end
  end
end
