require 'spec_helper'

describe DnsAlias do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    # Stub system call to avoid dnsmasq restart
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

  it "should reject names with special characters" do
    %w[my_alias my.alias my@alias my!alias].each do |bad_name|
      alias_record = DnsAlias.new(name: bad_name, address: "192.168.1.1")
      expect(alias_record).not_to be_valid, "expected '#{bad_name}' to be invalid"
    end
  end

  it "should reject empty name" do
    alias_record = DnsAlias.new(name: "", address: "192.168.1.1")
    expect(alias_record).not_to be_valid
  end

  it "should allow single character names starting with a letter" do
    alias_record = DnsAlias.new(name: "a", address: "192.168.1.1")
    expect(alias_record).to be_valid
  end

  it "should be case-insensitive for name format (uppercase allowed)" do
    alias_record = DnsAlias.new(name: "MyAlias", address: "192.168.1.1")
    expect(alias_record).to be_valid
  end

  it "should allow empty address (points to self)" do
    alias_record = DnsAlias.new(name: "selfalias", address: "")
    expect(alias_record).to be_valid
  end

  it "should allow nil address" do
    alias_record = DnsAlias.new(name: "niladdr", address: nil)
    expect(alias_record).to be_valid
  end

  describe ".user_visible" do
    it "should exclude aliases with empty addresses" do
      visible = DnsAlias.create!(name: "visible", address: "192.168.1.1")
      hidden = DnsAlias.create!(name: "hidden", address: "")
      expect(DnsAlias.user_visible).to include(visible)
      expect(DnsAlias.user_visible).not_to include(hidden)
    end

    it "should include all aliases with non-empty addresses" do
      a1 = DnsAlias.create!(name: "aliasone", address: "10.0.0.1")
      a2 = DnsAlias.create!(name: "aliastwo", address: "10.0.0.2")
      expect(DnsAlias.user_visible).to include(a1, a2)
    end

    it "should return empty when all aliases have empty addresses" do
      DnsAlias.create!(name: "emptyaddr", address: "")
      expect(DnsAlias.user_visible).to be_empty
    end
  end

  describe "callbacks" do
    it "should call restart after save" do
      alias_record = DnsAlias.new(name: "callbacktest", address: "192.168.1.1")
      expect(alias_record).to receive(:restart)
      alias_record.save!
    end

    it "should call restart after destroy" do
      alias_record = DnsAlias.create!(name: "destroyme", address: "192.168.1.1")
      expect(alias_record).to receive(:restart)
      alias_record.destroy
    end
  end

  describe "dnsmasq aliases file" do
    it "is written through the root helper with every alias, in lines the helper accepts" do
      DnsAlias.create!(name: "files", address: "192.168.1.10")
      DnsAlias.create!(name: "blocked", address: "")
      DnsAlias.new.send(:regenerate_dnsmasq_config)

      op, args = Privileged.calls.last
      expect(op).to eq('network.write_dns_aliases')
      expect(args[:content]).to include("address=/files/192.168.1.10\n", "address=/blocked/\n")
      Privileged.operations # loads libexec/amahi-helper
      expect { AmahiHelper.dnsmasq_conf(args[:content], AmahiHelper::DNS_ALIAS_LINES) }.not_to raise_error
    end

    it "keeps the alias when the helper refuses the file" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.write_dns_aliases', 'refused'))
      expect { DnsAlias.new.send(:regenerate_dnsmasq_config) }.not_to raise_error
    end
  end
end
