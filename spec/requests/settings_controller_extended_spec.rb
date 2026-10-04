require 'rails_helper'

RSpec.describe "SettingsController extended", type: :request do
  before { login_as_admin }

  describe "GET system_status" do
    it "shows system status page with system info" do
      get "/settings/system_status"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("System")
    end

    # The update window's buttons live inside a bar that's always there, so the window keeps
    # its height when they appear or disappear (it used to jump and cut off the last line).
    it "puts the update window's buttons inside its always-visible status bar" do
      get "/settings/system_status"
      bar = Nokogiri::HTML(response.body).at_css('#update-install-bar')
      expect(bar).not_to be_nil
      expect(bar.at_css('#update-status')).not_to be_nil
      expect(bar.at_css('#update-install-footer button')).not_to be_nil
    end
  end

  describe "POST activate_theme" do
    it "updates theme setting and redirects to themes page" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "amahi-kai"; s.kind = Setting::GENERAL }
      post "/settings/activate_theme", params: { id: "amahi-kai" }
      expect(response).to redirect_to("/settings/themes")
      expect(Setting.find_by(name: "theme").value).to eq("amahi-kai")
    end
  end

  describe "POST update_system" do
    it "redirects to system_status" do
      post "/settings/update_system"
      expect(response).to redirect_to("/settings/system_status")
    end
  end
end
