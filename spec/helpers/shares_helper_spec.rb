require 'rails_helper'

RSpec.describe SharesHelper, type: :helper do
  describe "#tags_to_str" do
    it "returns tags when present" do
      expect(helper.tags_to_str("movies, music")).to eq("movies, music")
    end

    it "returns placeholder when blank" do
      expect(helper.tags_to_str("")).to eq("(add tags)")
      expect(helper.tags_to_str(nil)).to eq("(add tags)")
    end
  end

  describe "#confirm_share_destroy_message" do
    it "includes share name" do
      msg = helper.confirm_share_destroy_message("Movies")
      expect(msg).to be_a(String)
    end
  end

end
