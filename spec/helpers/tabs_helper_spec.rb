require 'rails_helper'

RSpec.describe TabsHelper, type: :helper do
  describe "#advanced?" do
    it "returns true when advanced setting is 1" do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "1"; s.kind = 0 }
      Setting.find_by(name: "advanced").update!(value: "1")
      expect(helper.advanced?).to be true
    end

    it "returns false when advanced setting is 0" do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "0"; s.kind = 0 }
      Setting.find_by(name: "advanced").update!(value: "0")
      expect(helper.advanced?).to be false
    end

    it "returns false when no advanced setting" do
      Setting.where(name: "advanced").delete_all
      expect(helper.advanced?).to be_falsey
    end
  end

  describe "#debug?" do
    it "returns false" do
      expect(helper.debug?).to be false
    end
  end

  describe "#debug_tab?" do
    it "returns true when advanced" do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "1"; s.kind = 0 }
      Setting.find_by(name: "advanced").update!(value: "1")
      expect(helper.debug_tab?).to be true
    end

    it "returns false when not advanced" do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "0"; s.kind = 0 }
      Setting.find_by(name: "advanced").update!(value: "0")
      expect(helper.debug_tab?).to be false
    end
  end
end
