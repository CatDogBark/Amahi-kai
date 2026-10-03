require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
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

  # (#debug? and #debug_tab? were removed with the plugin system; their specs went too.)
end
