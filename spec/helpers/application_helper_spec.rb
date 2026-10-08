require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe "#full_page_title" do
    it "returns default title when no page_title" do
      helper.instance_variable_set(:@page_title, nil)
      expect(helper.full_page_title).to eq("Amahi-kai Home Server")
    end

    it "includes page_title when set" do
      helper.instance_variable_set(:@page_title, "Settings")
      expect(helper.full_page_title).to include("Settings")
      expect(helper.full_page_title).to include("Amahi-kai")
    end
  end

  describe "#spinner" do
    it "returns a span with spinner class" do
      result = helper.spinner
      expect(result).to include("spinner")
      expect(result).to include("display: none")
    end

    it "includes custom css class" do
      result = helper.spinner("my-class")
      expect(result).to include("my-class")
    end
  end

  describe "#current_user_is_admin?" do
    it "returns false when no current user" do
      allow(helper).to receive(:current_user).and_return(nil)
      expect(helper.current_user_is_admin?).to be_falsey
    end

    it "returns true for admin user" do
      admin = double("User", admin?: true)
      allow(helper).to receive(:current_user).and_return(admin)
      expect(helper.current_user_is_admin?).to be true
    end

    it "returns false for non-admin user" do
      user = double("User", admin?: false)
      allow(helper).to receive(:current_user).and_return(user)
      expect(helper.current_user_is_admin?).to be false
    end
  end


  describe "#path2uri" do
    it "returns smb URI for Mac" do
      allow(helper).to receive(:is_a_mac?).and_return(true)
      expect(helper.path2uri("Movies")).to include("smb://amahi-kai/")
    end

    it "returns file URI for Windows" do
      allow(helper).to receive(:is_a_mac?).and_return(false)
      expect(helper.path2uri("Movies")).to include("file://///amahi-kai/")
    end

    it "encodes special characters" do
      allow(helper).to receive(:is_a_mac?).and_return(true)
      result = helper.path2uri("My Movies")
      expect(result).to include("My+Movies")
    end
  end

  describe "#is_a_mac?" do
    it "detects Mac user agent" do
      allow(helper.request).to receive(:env).and_return("HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel)")
      expect(helper.is_a_mac?).to be true
    end

    it "returns false for Windows user agent" do
      allow(helper.request).to receive(:env).and_return("HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT)")
      expect(helper.is_a_mac?).to be false
    end
  end

  # Written when the page loads; time_ago.js works them out again as time passes, so a page
  # left open doesn't keep saying "less than a minute ago".
  describe "#relative_time_tag" do
    include ActiveSupport::Testing::TimeHelpers

    let(:checked) { Time.utc(2026, 10, 5, 9, 0, 0) }

    before { travel_to(checked + 3.hours) }
    after { travel_back }

    it "says how long ago, with the time for the page's script" do
      expect(helper.relative_time_tag(checked)).to eq('<time datetime="2026-10-05T09:00:00Z" data-relative="ago">about 3 hours ago</time>')
      expect(helper.relative_time_tag(checked, capitalize: true, clock: true))
        .to eq('<time datetime="2026-10-05T09:00:00Z" data-relative="ago" data-capitalize="true" data-clock="true">About 3 hours ago</time>')
    end

    it "says how long until, or any moment once it's passed" do
      expect(helper.relative_time_tag(checked + 5.hours, future: true)).to include('data-relative="in">in about 2 hours</time>')
      expect(helper.relative_time_tag(checked, future: true)).to include('>any moment</time>')
    end

    it "is kept current by a script every page loads" do
      expect(File.read(Rails.root.join('app/assets/javascripts/application.js'))).to include('//= require time_ago')
    end
  end

  describe "#formatted_date" do
    it "formats a valid date" do
      result = helper.formatted_date(1.hour.ago)
      expect(result).to be_a(String)
    end

    it "returns dash for nil date" do
      expect(helper.formatted_date(nil)).to eq("-")
    end

    it "returns dash for invalid date" do
      expect(helper.formatted_date("not a date")).to eq("-")
    end
  end

end
