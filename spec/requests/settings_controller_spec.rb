require 'spec_helper'

describe "Settings Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/settings"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/settings"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /settings" do
      it "shows the settings page" do
        get "/settings"
        expect(response).to have_http_status(:ok)
      end
    end

    # English only: no language picker.
    it "serves pages in English, whatever language the browser asks for" do
      get "/settings", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'de-DE,de;q=0.9' }
      expect(Nokogiri::HTML(response.body).at('html')['lang']).to eq('en')
      expect(response.body).not_to include('change_language')
      expect(I18n.available_locales).to eq([:en])
    end

    describe "toggle_setting" do
      it "toggles a setting value" do
        setting = Setting.create!(name: "advanced", value: "0", kind: 0)
        post "/settings/toggle_setting", params: { id: setting.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("1")
      end

      it "toggles back" do
        setting = Setting.create!(name: "advanced", value: "1", kind: 0)
        post "/settings/toggle_setting", params: { id: setting.id }, as: :json
        expect(setting.reload.value).to eq("0")
      end
    end

    describe "servers" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows each service with its details" do
        entry = SystemServices::CATALOG.find { |e| e[:key] == 'smbd' }
        samba = SystemServices::Service.new(
          entry,
          { 'ActiveState' => 'active', 'SubState' => 'running', 'Description' => 'Samba SMB Daemon',
            'ActiveEnterTimestamp' => "@#{(Time.now - 90_000).to_i}", 'MainPID' => '4242',
            'MemoryCurrent' => '8003584', 'UnitFileState' => 'enabled' },
          version: '4.19.5', version_detail: '2:4.19.5+dfsg-4ubuntu9.7'
        )
        allow(SystemServices).to receive(:all).with(versions: true).and_return([samba])

        get "/settings/servers"
        expect(response).to have_http_status(:ok)
        body = response.body
        expect(body).to include('Samba SMB Daemon', '4.19.5', '1 day, 1 hour', '4242', '7.63 MB')
        expect(body).to include('/settings/servers/smbd/restart', '/settings/servers/smbd/stop')
      end

      it "redirects if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/settings/servers"
        expect(response).to redirect_to("/settings")
      end
    end

    describe "reboot" do
      it "asks the root helper to reboot" do
        post "/settings/reboot"
        expect(response).to have_http_status(:ok)
        expect(Privileged.calls).to eq([['system.reboot', {}]])
      end
    end

    describe "poweroff" do
      it "asks the root helper to power off" do
        post "/settings/poweroff"
        expect(response).to have_http_status(:ok)
        expect(Privileged.calls).to eq([['system.poweroff', {}]])
      end
    end

  end
end
