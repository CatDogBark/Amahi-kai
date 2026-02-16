require 'spec_helper'

RSpec.describe Yetting do
  describe ".settings" do
    it "returns a frozen hash" do
      expect(Yetting.settings).to be_a(Hash)
      expect(Yetting.settings).to be_frozen
    end
  end

  describe "method-style access" do
    it "returns configured values" do
      # locales_implemented should be in yetting.yml
      expect(Yetting.locales_implemented).to be_an(Array)
    end

    it "raises NoMethodError for unknown keys" do
      expect { Yetting.nonexistent_setting_xyz }.to raise_error(NoMethodError)
    end
  end

  describe ".respond_to_missing?" do
    it "responds to configured keys" do
      expect(Yetting.respond_to?(:locales_implemented)).to be true
    end

    it "does not respond to unknown keys" do
      expect(Yetting.respond_to?(:nonexistent_xyz)).to be false
    end
  end

  describe ".reload!" do
    it "clears and reloads settings" do
      original = Yetting.settings
      Yetting.reload!
      expect(Yetting.settings).to eq(original)
    end
  end
end
