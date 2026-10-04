require 'rails_helper'

RSpec.describe "SettingsController extended", type: :request do
  before { login_as_admin }

  describe "GET system_status" do
    it "shows system status page with system info" do
      get "/settings/system_status"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("System")
    end

    def update_status(data)
      allow(UpdateStatus).to receive(:load).and_return(UpdateStatus.new(data))
    end

    it "shows an available update with its changes linked, and Update now" do
      update_status('checked_at' => 2.hours.ago.utc.iso8601, 'current' => 'aaaaaaa1', 'latest' => 'bbbbbbb2',
                    'available' => true, 'behind' => 2,
                    'commits' => [{ 'sha' => 'bbbbbbb', 'subject' => 'Update window keeps its size (#36)' },
                                  { 'sha' => 'ccccccc', 'subject' => 'Drive temperatures (#35)' }])
      get "/settings/system_status"
      expect(response.body).to include('Update available:', '2 changes', 'aaaaaaa → bbbbbbb')
      expect(response.body).to include('https://github.com/CatDogBark/Amahi-kai/pull/36', 'update-now-btn')
      expect(response.body).not_to include('repair-btn')
    end

    it "shows up to date with Repair instead of Update now" do
      update_status('checked_at' => 5.minutes.ago.utc.iso8601, 'current' => 'aaaaaaa1', 'latest' => 'aaaaaaa1',
                    'available' => false, 'behind' => 0)
      get "/settings/system_status"
      expect(response.body).to include('Up to date (aaaaaaa)', 'Checked 5 minutes ago', 'repair-btn')
      expect(response.body).not_to include('update-now-btn')
    end

    it "says when nothing has been checked yet, and shows a failed check" do
      update_status({})
      get "/settings/system_status"
      expect(response.body).to include('Not checked yet')
      update_status('checked_at' => 1.minute.ago.utc.iso8601, 'behind' => 0, 'error' => "couldn't fetch from GitHub: timeout")
      get "/settings/system_status"
      expect(response.body).to include("Last check: couldn&#39;t fetch from GitHub: timeout")
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

  describe "POST check_updates" do
    it "runs the check through the helper" do
      post "/settings/check_updates", as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(Privileged.calls).to include(['system.check_update', {}])
    end

    it "reports a failed check" do
      allow(Privileged).to receive(:call).with('system.check_update')
        .and_raise(Privileged::Error.new('system.check_update', 'git is missing'))
      post "/settings/check_updates", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('git is missing')
    end
  end

  describe "POST update_system on the NAS" do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    it "starts an update" do
      post "/settings/update_system", as: :json
      expect(Privileged.calls).to include(['system.update', {}])
    end

    it "starts a repair with repair=1" do
      post "/settings/update_system?repair=1", as: :json
      expect(Privileged.calls).to include(['system.update', { repair: true }])
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
