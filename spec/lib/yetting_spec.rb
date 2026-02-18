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

  describe "env var overrides" do
    around do |example|
      Yetting.reload!
      example.run
      ENV.delete('AMAHI_DUMMY_MODE')
      Yetting.reload!
    end

    it "returns true when AMAHI_DUMMY_MODE=1" do
      ENV['AMAHI_DUMMY_MODE'] = '1'
      expect(Yetting.dummy_mode).to be true
    end

    it "returns false when AMAHI_DUMMY_MODE=0" do
      ENV['AMAHI_DUMMY_MODE'] = '0'
      expect(Yetting.dummy_mode).to be false
    end

    it "falls back to yml when env var is not set" do
      ENV.delete('AMAHI_DUMMY_MODE')
      # test environment has dummy_mode: true in yetting.yml
      expect(Yetting.dummy_mode).to be true
    end

    it "responds_to? dummy_mode even without env var" do
      expect(Yetting.respond_to?(:dummy_mode)).to be true
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
