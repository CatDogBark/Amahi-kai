require 'spec_helper'

RSpec.describe AmahiApi do
  describe ".api_key=" do
    it "sets the API key" do
      AmahiApi.api_key = "test-key-123"
      expect(AmahiApi.api_key).to eq("test-key-123")
    end
  end

  describe ".available?" do
    it "returns false (API is dead)" do
      expect(AmahiApi.available?).to be false
    end
  end

  describe "::Base.find" do
    it "raises AmahiApi::Error" do
      expect { AmahiApi::App.find(:all) }.to raise_error(AmahiApi::Error)
    end
  end

  describe "::Base#save" do
    it "returns false (no-op)" do
      report = AmahiApi::ErrorReport.new
      expect(report.save).to be false
    end
  end

  describe "class hierarchy" do
    it "has App, AppInstaller, AppUninstaller, ErrorReport, TimelineEvent" do
      expect(AmahiApi::App).to be < AmahiApi::Base
      expect(AmahiApi::AppInstaller).to be < AmahiApi::Base
      expect(AmahiApi::AppUninstaller).to be < AmahiApi::Base
      expect(AmahiApi::ErrorReport).to be < AmahiApi::Base
      expect(AmahiApi::TimelineEvent).to be < AmahiApi::Base
    end
  end
end
