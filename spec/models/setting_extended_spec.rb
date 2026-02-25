require 'rails_helper'

RSpec.describe Setting, type: :model do
  describe ".get_kind" do
    it "returns setting object for existing kind/name" do
      Setting.create!(name: "dns", value: "custom", kind: Setting::NETWORK)
      result = Setting.get_kind(Setting::NETWORK, "dns")
      expect(result).to be_a(Setting)
      expect(result.value).to eq("custom")
    end

    it "returns nil for missing kind/name" do
      expect(Setting.get_kind(Setting::NETWORK, "nonexistent_key_xyz")).to be_nil
    end
  end

  describe ".find_or_create_by" do
    it "creates new setting when none exists" do
      result = Setting.find_or_create_by(Setting::NETWORK, "new_key_test", "new_value")
      expect(result).to be_a(Setting)
      expect(result.value).to eq("new_value")
    end

    it "returns existing setting without overwriting" do
      Setting.create!(name: "existing_test", value: "original", kind: Setting::NETWORK)
      result = Setting.find_or_create_by(Setting::NETWORK, "existing_test", "new_value")
      expect(result.value).to eq("original")
    end
  end

  describe "scopes" do
    before do
      Setting.create!(name: "share_test_set", value: "1", kind: Setting::SHARES)
      Setting.create!(name: "net_test_set", value: "1", kind: Setting::NETWORK)
    end

    it "filters shares settings" do
      expect(Setting.shares.pluck(:name)).to include("share_test_set")
      expect(Setting.shares.pluck(:name)).not_to include("net_test_set")
    end

    it "filters network settings" do
      expect(Setting.network.pluck(:name)).to include("net_test_set")
      expect(Setting.network.pluck(:name)).not_to include("share_test_set")
    end
  end

  describe ".get_by_name" do
    it "returns the setting object" do
      Setting.set("test_obj_key", "val123")
      obj = Setting.get_by_name("test_obj_key")
      expect(obj).to be_a(Setting)
      expect(obj.value).to eq("val123")
    end
  end

  describe "constants" do
    it "defines kind constants as strings" do
      expect(Setting::GENERAL).to eq("general")
      expect(Setting::SHARES).to eq("shares")
      expect(Setting::NETWORK).to eq("network")
    end
  end
end
