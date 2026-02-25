require 'rails_helper'

RSpec.describe Setting, type: :model do
  describe ".get_kind and .set_kind" do
    it "sets and gets kind-specific settings" do
      Setting.set_kind(Setting::NETWORK, "dns", "custom")
      expect(Setting.get_kind(Setting::NETWORK, "dns")).to eq("custom")
    end

    it "returns nil for missing kind settings" do
      expect(Setting.get_kind(Setting::NETWORK, "nonexistent_key")).to be_nil
    end
  end

  describe ".find_or_create_by" do
    it "creates new setting" do
      Setting.find_or_create_by(Setting::NETWORK, "new_key", "new_value")
      expect(Setting.get_kind(Setting::NETWORK, "new_key")).to eq("new_value")
    end

    it "does not overwrite existing setting" do
      Setting.set_kind(Setting::NETWORK, "existing", "original")
      Setting.find_or_create_by(Setting::NETWORK, "existing", "new_value")
      expect(Setting.get_kind(Setting::NETWORK, "existing")).to eq("original")
    end
  end

  describe "scopes" do
    before do
      Setting.create!(name: "share_set", value: "1", kind: Setting::SHARES)
      Setting.create!(name: "net_set", value: "1", kind: Setting::NETWORK)
    end

    it "filters shares settings" do
      expect(Setting.shares.pluck(:name)).to include("share_set")
      expect(Setting.shares.pluck(:name)).not_to include("net_set")
    end

    it "filters network settings" do
      expect(Setting.network.pluck(:name)).to include("net_set")
      expect(Setting.network.pluck(:name)).not_to include("share_set")
    end
  end

  describe ".get_by_name" do
    it "returns the setting object" do
      Setting.set("test_obj", "val123")
      obj = Setting.get_by_name("test_obj")
      expect(obj).to be_a(Setting)
      expect(obj.value).to eq("val123")
    end
  end

  describe "constants" do
    it "defines kind constants" do
      expect(Setting::GENERAL).to eq(0)
      expect(Setting::SHARES).to be_present
      expect(Setting::NETWORK).to be_present
    end
  end
end
