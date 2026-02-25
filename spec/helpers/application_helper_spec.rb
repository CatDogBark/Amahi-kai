require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe "#full_page_title" do
    it "returns default title when no page_title" do
      assign(:page_title, nil)
      expect(helper.full_page_title).to eq("Amahi-kai Home Server")
    end

    it "includes page_title when set" do
      assign(:page_title, "Settings")
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

  describe "#rtl?" do
    it "returns false by default" do
      assign(:locale_direction, "ltr")
      expect(helper.rtl?).to be false
    end

    it "returns true for rtl direction" do
      assign(:locale_direction, "rtl")
      expect(helper.rtl?).to be true
    end
  end

  describe "#path2uri" do
    it "returns smb URI for Mac" do
      allow(helper).to receive(:is_a_mac?).and_return(true)
      expect(helper.path2uri("Movies")).to include("smb://hda/")
    end

    it "returns file URI for Windows" do
      allow(helper).to receive(:is_a_mac?).and_return(false)
      expect(helper.path2uri("Movies")).to include("file://///hda/")
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

  describe "#formatted_date" do
    it "formats a valid date" do
      result = helper.formatted_date(1.hour.ago)
      expect(result).to include("ago")
    end

    it "returns dash for invalid date" do
      expect(helper.formatted_date(nil)).to eq("-")
    end
  end

  describe "#theme_stylesheet_path" do
    it "returns correct path" do
      path = helper.theme_stylesheet_path("style", "amahi-kai")
      expect(path).to eq("/themes/amahi-kai/stylesheets/style.css")
    end
  end

  describe "#theme_image_path" do
    it "returns correct path with explicit theme" do
      path = helper.theme_image_path("logo.png", "amahi-kai")
      expect(path).to eq("/themes/amahi-kai/images/logo.png")
    end
  end
end
