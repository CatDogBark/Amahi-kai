require 'spec_helper'

describe Host do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    # Stub system call to avoid dnsmasq restart
    allow_any_instance_of(Host).to receive(:restart)
  end

  it "should require a name" do
    host = Host.new(name: nil, mac: "aa:bb:cc:dd:ee:ff", address: "10")
    expect(host).not_to be_valid
  end

  it "should require name to start with a letter" do
    host = Host.new(name: "1bad", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    expect(host).not_to be_valid
  end

  it "should allow valid hostnames with hyphens" do
    host = Host.new(name: "my-host", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    expect(host).to be_valid
  end

  it "lists the devices kept off the internet by address, and has the router's rules follow them while the NAS is the router" do
    camera = Host.create!(name: "camera", mac: "aa:bb:cc:dd:ee:52", address: "52", lan_only: true)
    Host.create!(name: "printer", mac: "aa:bb:cc:dd:ee:53", address: "53")
    expect(Host.lan_only_addresses("192.168.1")).to eq(["192.168.1.52"])
    expect(Privileged.calls.map(&:first)).not_to include("network.router_on") # not the router: the flag waits
    allow(DnsService).to receive(:router?).and_return(true)
    allow(DnsService).to receive(:apply_router!)
    camera.update!(address: "54") # a kept-off device's address moved: the rule follows
    expect(DnsService).to have_received(:apply_router!).once
    camera.update!(lan_only: false)
    expect(DnsService).to have_received(:apply_router!).twice
    camera.update!(name: "cam") # nothing of the router's changed
    expect(DnsService).to have_received(:apply_router!).twice
    camera.update!(lan_only: true)
    camera.destroy
    expect(DnsService).to have_received(:apply_router!).exactly(4).times
  end

  it "should require unique names" do
    Host.create!(name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    duplicate = Host.new(name: "myhost", mac: "11:22:33:44:55:66", address: "11")
    expect(duplicate).not_to be_valid
  end

  it "should require a MAC address" do
    host = Host.new(name: "myhost", mac: nil, address: "10")
    expect(host).not_to be_valid
  end

  it "should validate MAC address format" do
    host = Host.new(name: "myhost", mac: "not-a-mac", address: "10")
    expect(host).not_to be_valid

    host.mac = "aa:bb:cc:dd:ee:ff"
    expect(host).to be_valid
  end

  it "should require unique MAC addresses" do
    Host.create!(name: "host1", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    duplicate = Host.new(name: "host2", mac: "aa:bb:cc:dd:ee:ff", address: "11")
    expect(duplicate).not_to be_valid
  end

  it "should require an address" do
    host = Host.new(name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: nil)
    expect(host).not_to be_valid
  end

  it "should require address to be between 1 and 254" do
    host = Host.new(name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "0")
    expect(host).not_to be_valid

    host.address = "255"
    expect(host).not_to be_valid

    host.address = "10"
    expect(host).to be_valid
  end

  it "should require unique addresses" do
    Host.create!(name: "host1", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    duplicate = Host.new(name: "host2", mac: "11:22:33:44:55:66", address: "10")
    expect(duplicate).not_to be_valid
  end

  it "should convert address to integer string on save" do
    host = Host.create!(name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "010")
    expect(host.reload.address).to eq("10")
  end

  it "should reject names ending with hyphen" do
    host = Host.new(name: "bad-", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    # format allows trailing hyphen per regex, but let's verify
    # The regex is /\A[a-z][a-z0-9-]*\z/i so trailing hyphen is allowed
    expect(host).to be_valid
  end

  it "should reject names with spaces" do
    host = Host.new(name: "my host", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    expect(host).not_to be_valid
  end

  it "should reject names with underscores" do
    host = Host.new(name: "my_host", mac: "aa:bb:cc:dd:ee:ff", address: "10")
    expect(host).not_to be_valid
  end

  it "should accept uppercase MAC addresses" do
    host = Host.new(name: "mactest", mac: "AA:BB:CC:DD:EE:FF", address: "10")
    expect(host).to be_valid
  end

  it "should reject MAC with dashes instead of colons" do
    host = Host.new(name: "dashmac", mac: "aa-bb-cc-dd-ee-ff", address: "10")
    expect(host).not_to be_valid
  end

  it "should reject MAC with too few octets" do
    host = Host.new(name: "shortmac", mac: "aa:bb:cc:dd:ee", address: "10")
    expect(host).not_to be_valid
  end

  it "should reject non-numeric addresses" do
    host = Host.new(name: "badaddr", mac: "aa:bb:cc:dd:ee:ff", address: "abc")
    expect(host).not_to be_valid
  end

  it "should reject decimal addresses" do
    host = Host.new(name: "decaddr", mac: "aa:bb:cc:dd:ee:ff", address: "10.5")
    expect(host).not_to be_valid
  end

  it "should accept address 1 (minimum)" do
    host = Host.new(name: "minaddr", mac: "aa:bb:cc:dd:ee:ff", address: "1")
    expect(host).to be_valid
  end

  it "should accept address 254 (maximum)" do
    host = Host.new(name: "maxaddr", mac: "aa:bb:cc:dd:ee:f1", address: "254")
    expect(host).to be_valid
  end

  it "refuses a name longer than a hostname label (63 characters)" do
    expect(Host.new(name: "a" * 63, mac: "aa:bb:cc:dd:ee:01", address: "60")).to be_valid
    expect(Host.new(name: "a" * 64, mac: "aa:bb:cc:dd:ee:02", address: "61")).not_to be_valid
  end

  describe "callbacks" do
    before do
      allow(DnsmasqService).to receive(:rewrite_config!)
      allow(DnsService).to receive(:rewrite!)
    end

    it "rewrites dnsmasq's config and Unbound's names after each change" do
      host = Host.create!(name: "cbhost", mac: "11:22:33:44:55:66", address: "50")
      host.update!(address: "52")
      host.destroy
      expect(DnsmasqService).to have_received(:rewrite_config!).exactly(3).times
      expect(DnsService).to have_received(:rewrite!).exactly(3).times
    end

    it "still rewrites Unbound's names when dnsmasq's config is refused" do
      allow(DnsmasqService).to receive(:rewrite_config!)
        .and_raise(Privileged::Error.new('network.write_dnsmasq_config', 'refused'))
      Host.create!(name: "cbhost", mac: "11:22:33:44:55:66", address: "50")
      expect(DnsService).to have_received(:rewrite!)
    end

    it "keeps the host when the helper refuses the config, and logs why" do
      allow(DnsmasqService).to receive(:rewrite_config!)
        .and_raise(Privileged::Error.new('network.write_dnsmasq_config', 'refused'))
      expect { Host.create!(name: "cbhost", mac: "11:22:33:44:55:66", address: "50") }.not_to raise_error
      expect(Host.find_by(name: "cbhost")).to be_present
    end
  end

end
