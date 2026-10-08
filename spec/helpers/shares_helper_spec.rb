require 'rails_helper'

RSpec.describe SharesHelper, type: :helper do
  describe "#confirm_share_destroy_message" do
    it "includes share name" do
      msg = helper.confirm_share_destroy_message("Movies")
      expect(msg).to be_a(String)
    end
  end

end
