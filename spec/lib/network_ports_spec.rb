require 'spec_helper'
require 'network_ports'
require 'tmpdir'

RSpec.describe NetworkPorts do
  let(:sys) { Dir.mktmpdir }

  # A port in sysfs: its files, and its device as a directory (named like the bus names it)
  # with a driver link.
  def port(name, device: nil, driver: nil, carrier: '1', speed: nil, mac: 'bc:24:11:00:00:01')
    dir = File.join(sys, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'carrier'), "#{carrier}\n") if carrier
    File.write(File.join(dir, 'speed'), "#{speed}\n") if speed
    File.write(File.join(dir, 'address'), "#{mac}\n")
    return unless device
    device_dir = File.join(sys, 'devices', device)
    FileUtils.mkdir_p(device_dir)
    File.symlink(device_dir, File.join(dir, 'device'))
    FileUtils.mkdir_p(File.join(sys, 'drivers', driver))
    File.symlink(File.join(sys, 'drivers', driver), File.join(device_dir, 'driver'))
  end

  after { FileUtils.rm_rf(sys) }

  it 'names a real port by what lspci says of its PCI slot, with its link and MAC' do
    port('enp3s0', device: '0000:03:00.0', driver: 'igb', speed: '1000', mac: 'a0:36:9f:12:34:56')
    allow(Shell).to receive(:output).with('lspci', '-mm', '-s', '0000:03:00.0')
                                    .and_return(%(03:00.0 "Ethernet controller" "Intel Corporation" "I350 Gigabit Network Connection" -r01 "Intel Corporation" "Ethernet Server Adapter I350-T4"\n))
    info = described_class.info('enp3s0', sys: sys)
    expect(info).to have_attributes(driver: 'igb', model: 'Intel I350 Gigabit Network Connection', virtual: false, link: true, speed: 1000,
                                    mac: 'a0:36:9f:12:34:56', label: nil)
    expect(info.kind).to eq('Intel I350 Gigabit Network Connection')
    expect(info.link_text).to eq('link up, 1000 Mb/s')
  end

  it "calls a hypervisor's port virtual, without asking lspci, and reads no speed from it" do
    port('ens18', device: 'virtio1', driver: 'virtio_net', speed: '-1')
    expect(Shell).not_to receive(:output)
    info = described_class.info('ens18', sys: sys)
    expect(info).to have_attributes(driver: 'virtio_net', model: nil, virtual: true, link: true, speed: nil)
    expect(info.kind).to eq('virtual port (virtio)')
    expect(info.link_text).to eq('link up')
  end

  it 'falls back to the driver for a port off the PCI bus, and says when the cable is out' do
    port('enx00e04c680001', device: '1-3:1.0', driver: 'r8152', carrier: '0')
    info = described_class.info('enx00e04c680001', sys: sys)
    expect(info).to have_attributes(model: nil, virtual: false, link: false)
    expect(info.kind).to eq('r8152 port')
    expect(info.link_text).to eq('no link')
  end

  it 'takes a bridge or a port that is gone as virtual, with nothing read' do
    port('br0')
    expect(described_class.info('br0', sys: sys)).to have_attributes(driver: nil, virtual: true, link: true, mac: 'bc:24:11:00:00:01')
    expect(described_class.info('br0', sys: sys).kind).to eq('virtual port')
    expect(described_class.info('gone', sys: sys)).to have_attributes(driver: nil, virtual: true, link: false, mac: nil)
    expect(described_class.all(%w[br0 gone], sys: sys).keys).to eq(%w[br0 gone])
  end

  describe 'the name the admin gives a port' do
    it 'is kept as a setting and shown with the port' do
      expect(described_class.set_label!('ens20', '  Modem ')).to eq('Modem')
      expect(described_class.label('ens20')).to eq('Modem')
      expect(described_class.display('ens20')).to eq('Modem (ens20)')
      expect(described_class.display('ens19')).to eq('ens19')
      expect(described_class.set_label!('ens20', '')).to be_nil
      expect(described_class.display('ens20')).to eq('ens20')
    end

    it 'refuses one too long or with control characters' do
      expect { described_class.set_label!('ens20', 'x' * 33) }.to raise_error(ArgumentError, /up to 32/)
      expect { described_class.set_label!('ens20', "Mod\tem") }.to raise_error(ArgumentError, /letters, digits/)
      expect(described_class.label('ens20')).to be_nil
    end
  end

  it 'can blink a real port where ethtool is installed, through the helper' do
    real = described_class::Port.new(name: 'enp3s0', label: nil, driver: 'igb', model: nil, virtual: false, link: true, speed: nil, mac: nil)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with(described_class::ETHTOOL).and_return(true)
    expect(described_class.blinkable?(real)).to be true
    expect(described_class.blinkable?(real.with(virtual: true))).to be false
    allow(File).to receive(:executable?).with(described_class::ETHTOOL).and_return(false)
    expect(described_class.blinkable?(real)).to be false
    Privileged.reset!
    described_class.blink!('enp3s0')
    expect(Privileged.calls).to eq([['network.blink_port', { interface: 'enp3s0' }]])
  end
end
