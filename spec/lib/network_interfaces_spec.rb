require 'rails_helper'

RSpec.describe NetworkInterfaces do
  let(:ifaddr) { Struct.new(:name, :addr, :netmask) }
  let(:ifaddrs) do
    [ifaddr.new('lo', Addrinfo.ip('127.0.0.1'), Addrinfo.ip('255.0.0.0')),
     ifaddr.new('ens18', nil, nil), # a link-layer entry: no IP address
     ifaddr.new('ens18', Addrinfo.ip('192.168.1.10'), Addrinfo.ip('255.255.255.0')),
     ifaddr.new('ens18', Addrinfo.ip('fd12:3456:789a::10'), Addrinfo.ip('ffff:ffff:ffff:ffff::')),
     ifaddr.new('ens18', Addrinfo.ip('fe80::10'), Addrinfo.ip('ffff:ffff:ffff:ffff::')),
     ifaddr.new('docker0', Addrinfo.ip('172.17.0.1'), Addrinfo.ip('255.255.0.0')),
     ifaddr.new('tailscale0', Addrinfo.ip('100.64.96.4'), Addrinfo.ip('255.255.255.255'))]
  end

  it 'lists the addresses of each interface with their prefix lengths' do
    addresses = described_class.all(ifaddrs).fetch('ens18')
    expect(addresses.map { |a| [a.to_s, a.prefix] }).to eq([['192.168.1.10', 24], ['fd12:3456:789a::10', 64], ['fe80::10', 64]])
    expect(addresses.map(&:network)).to eq(['192.168.1.0/24', 'fd12:3456:789a::/64', 'fe80::/64'])
    expect(addresses.map(&:ula?)).to eq([false, true, false])
    expect(addresses.map(&:link_local?)).to eq([false, false, true])
  end

  it 'leaves loopback, Docker and Tailscale out of the LAN' do
    expect(described_class.lan(ifaddrs).keys).to eq(['ens18'])
    expect(described_class.addresses('tailscale0', ifaddrs).map(&:to_s)).to eq(['100.64.96.4'])
  end

  it 'finds the interface the default route leaves by' do
    Tempfile.create('route') do |file|
      file.write("Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\n" \
                 "docker0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\n" \
                 "ens18\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\n")
      file.flush
      expect(described_class.default_name(file.path)).to eq('ens18')
    end
    expect(described_class.default_name('/nonexistent/route')).to be_nil
  end

  it "reads this machine's interfaces" do
    expect { described_class.all }.not_to raise_error
  end
end
