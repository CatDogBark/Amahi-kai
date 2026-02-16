require 'spec_helper'

describe Setting do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  describe ".get and .set" do
    it "should set and get a value" do
      Setting.set("test_key", "test_value")
      expect(Setting.get("test_key")).to eq("test_value")
    end

    it "should update existing values" do
      Setting.set("test_key", "value1")
      Setting.set("test_key", "value2")
      expect(Setting.get("test_key")).to eq("value2")
    end

    it "should return nil for missing keys" do
      expect(Setting.get("nonexistent")).to be_nil
    end
  end

  describe ".value_by_name" do
    it "should return the value for a setting" do
      Setting.set("mykey", "myval")
      expect(Setting.value_by_name("mykey")).to eq("myval")
    end

    it "should return nil for missing settings" do
      expect(Setting.value_by_name("missing")).to be_nil
    end
  end

  describe "#set?" do
    it "should return true for '1'" do
      setting = Setting.new(value: "1")
      expect(setting.set?).to be true
    end

    it "should return true for 'true'" do
      setting = Setting.new(value: "true")
      expect(setting.set?).to be true
    end

    it "should return false for other values" do
      setting = Setting.new(value: "0")
      expect(setting.set?).to be false

      setting.value = "false"
      expect(setting.set?).to be false
    end
  end

  describe "scopes" do
    it "should filter by kind" do
      Setting.set("general_setting", "val", Setting::GENERAL)
      Setting.set("network_setting", "val", Setting::NETWORK)

      expect(Setting.general.pluck(:name)).to include("general_setting")
      expect(Setting.general.pluck(:name)).not_to include("network_setting")
      expect(Setting.network.pluck(:name)).to include("network_setting")
    end
  end

  describe "workgroup validation" do
    it "should validate workgroup format on update" do
      setting = Setting.create!(name: "workgroup", kind: Setting::GENERAL, value: "WORKGROUP")
      setting.value = "123invalid"
      expect(setting).not_to be_valid
    end

    it "should allow valid workgroup names" do
      setting = Setting.create!(name: "workgroup", kind: Setting::GENERAL, value: "WORKGROUP")
      setting.value = "MYWORKGROUP"
      expect(setting).to be_valid
    end

    it "should reject workgroup names over 15 characters" do
      setting = Setting.create!(name: "workgroup", kind: Setting::GENERAL, value: "WORKGROUP")
      setting.value = "A" * 16
      expect(setting).not_to be_valid
    end
  end
end
