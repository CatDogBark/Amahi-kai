require 'spec_helper'

RSpec.describe Downloader do
  describe "constants" do
    it "has a download cache path" do
      expect(Downloader::HDA_DOWNLOAD_CACHE).to include("amahi-download-cache")
    end

    it "has custom exception classes" do
      expect(Downloader::SHA1VerificationFailed).to be < Exception
      expect(Downloader::TooManyRedirects).to be < Exception
    end
  end
end
