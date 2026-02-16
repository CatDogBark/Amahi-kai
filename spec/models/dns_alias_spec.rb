require 'spec_helper'

describe DnsAlias do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    # Stub system call to avoid hda-ctl-hup
    allow_any_instance_of(DnsAlias).to receive(:restart)
  end

  it "should require a name" do
    alias_record = DnsAlias.new(name: nil, address: "192.168.1.1")
    expect(alias_record).not_to be_valid
  end

  it "should require name to start with a letter" do
    alias_record = DnsAlias.new(name: "1bad", address: "192.168.1.1")
    expect(alias_record).not_to be_valid
  end

  it "should allow alphanumeric names with hyphens" do
    alias_record = DnsAlias.new(name: "my-alias", address: "192.168.1.1")
    expect(alias_record).to be_valid
  end

  it "should require unique names" do
    DnsAlias.create!(name: "myalias", address: "192.168.1.1")
    duplicate = DnsAlias.new(name: "myalias", address: "192.168.1.2")
    expect(duplicate).not_to be_valid
  end

  describe ".user_visible" do
    it "should exclude aliases with empty addresses" do
      visible = DnsAlias.create!(name: "visible", address: "192.168.1.1")
      hidden = DnsAlias.create!(name: "hidden", address: "")
      expect(DnsAlias.user_visible).to include(visible)
      expect(DnsAlias.user_visible).not_to include(hidden)
    end
  end
end
