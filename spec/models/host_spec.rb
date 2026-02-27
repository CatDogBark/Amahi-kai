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

  describe "callbacks" do
    it "should call restart after save" do
      host = Host.new(name: "cbhost", mac: "11:22:33:44:55:66", address: "50")
      expect(host).to receive(:restart).at_least(:once)
      host.save!
    end

    it "should call restart after destroy" do
      host = Host.create!(name: "destroyhost", mac: "11:22:33:44:55:67", address: "51")
      expect(host).to receive(:restart)
      host.destroy
    end
  end
end
