require 'rails_helper'

RSpec.describe PortForward do
  it 'takes a port, a protocol and a device, the same port on the device unless told otherwise' do
    forward = described_class.create!(protocol: 'tcp', port: 8080, address: '60')
    expect(forward.to_port).to eq(8080)
    expect(forward.label).to eq('tcp 8080')
    expect(described_class.create!(protocol: 'udp', port: 8080, address: '60', to_port: 80).label).to eq('udp 8080 → 80')
    expect(Privileged.calls).to be_empty # the router's rules are the controller's to rewrite, and report
  end

  it 'refuses what the helper would, and the same port twice for one protocol' do
    described_class.create!(protocol: 'tcp', port: 8080, address: '60')
    [{ protocol: 'tcp', port: 8080, address: '61' }, { protocol: 'icmp', port: 1, address: '60' }, { protocol: 'tcp', port: 0, address: '60' },
     { protocol: 'tcp', port: 70_000, address: '60' }, { protocol: 'tcp', port: 80, address: '1' }, { protocol: 'tcp', port: 80, address: '255' },
     { protocol: 'tcp', port: 80, address: '10.0.0.5' }, { protocol: 'tcp', port: 80, address: '60', name: 'x' * 41 }].each do |bad|
      expect(described_class.new(bad)).not_to be_valid, bad.inspect
    end
  end

  it 'gives the helper whole addresses on the LAN' do
    described_class.create!(protocol: 'tcp', port: 8080, address: '60', to_port: 80)
    expect(described_class.for_helper('10.99.0')).to eq([{ protocol: 'tcp', port: 8080, address: '10.99.0.60', to_port: 80 }])
  end
end
