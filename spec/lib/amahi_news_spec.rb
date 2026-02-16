require 'spec_helper'

RSpec.describe AmahiNews do
  describe ".top" do
    it "returns nil when blog is unreachable" do
      allow(Ping).to receive(:pingecho).and_return(false)
      expect(AmahiNews.top).to be_nil
    end

    it "returns nil on network errors" do
      allow(Ping).to receive(:pingecho).and_raise(StandardError)
      expect(AmahiNews.top).to be_nil
    end
  end
end
