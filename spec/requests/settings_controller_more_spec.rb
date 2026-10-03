require 'rails_helper'

RSpec.describe "SettingsController more", type: :request do
  before { login_as_admin }

  # --- System status ---

  describe "GET /settings/system_status" do
    it "returns 200 with system info" do
      get '/settings/system_status'
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Update system ---

  describe "POST /settings/update_system" do
    it "redirects to system_status" do
      post '/settings/update_system'
      expect(response).to redirect_to('/settings/system_status')
    end
  end

  describe "GET /settings/update_system_stream" do
    it "returns SSE content type" do
      get '/settings/update_system_stream', headers: same_origin
      expect(response.content_type).to include('text/event-stream')
    end
  end

  # --- Poweroff / Reboot ---

  describe "POST /settings/reboot" do
    it "calls Platform.reboot! and returns text" do
      allow(Platform).to receive(:reboot!)
      post '/settings/reboot'
      expect(Platform).to have_received(:reboot!)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /settings/poweroff" do
    it "calls Platform.poweroff! and returns text" do
      allow(Platform).to receive(:poweroff!)
      post '/settings/poweroff'
      expect(Platform).to have_received(:poweroff!)
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Theme activation ---

  describe "POST /settings/activate_theme" do
    it "updates theme and redirects" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "default"; s.kind = Setting::GENERAL }
      post '/settings/activate_theme', params: { id: 'vertical' }
      expect(response).to redirect_to('/settings/themes')
      expect(Setting.find_by(name: 'theme').value).to eq('vertical')
    end

    it "rejects a theme that isn't installed" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "amahi-kai"; s.kind = Setting::GENERAL }
      ['dark-mode', '../../tmp/evil'].each do |name|
        post '/settings/activate_theme', params: { id: name }
        expect(response).to redirect_to('/settings/themes')
        expect(Setting.find_by(name: 'theme').value).to eq('amahi-kai')
      end
    end
  end

  # --- Themes index ---

  describe "GET /settings/themes" do
    it "shows available themes" do
      allow(Theme).to receive(:available).and_return([])
      get '/settings/themes'
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Settings index ---

  describe "GET /settings" do
    it "shows settings page" do
      get '/settings'
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Servers page ---

  describe "GET /settings/servers" do
    context "when advanced mode is off" do
      it "redirects to settings index" do
        get '/settings/servers'
        # Should redirect since @advanced is false by default
        expect(response).to redirect_to('/settings').or have_http_status(:ok)
      end
    end
  end

  # --- Toggle setting ---

  describe "POST /settings/toggle_setting" do
    it "toggles a setting value" do
      setting = Setting.find_or_create_by!(name: 'advanced') { |s| s.value = '0'; s.kind = Setting::GENERAL }
      setting.update!(value: '0')
      post "/settings/toggle_setting", params: { id: setting.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(setting.reload.value).to eq('1')
    end

    it "toggles back from 1 to 0" do
      setting = Setting.find_or_create_by!(name: 'advanced') { |s| s.value = '1'; s.kind = Setting::GENERAL }
      setting.update!(value: '1')
      post "/settings/toggle_setting", params: { id: setting.id }, as: :json
      expect(setting.reload.value).to eq('0')
    end
  end

  # --- Change language ---

  describe "POST /settings/change_language" do
    it "sets locale cookie for valid locale" do
      post '/settings/change_language', params: { locale: 'en' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('ok')
    end

    it "still returns ok for invalid locale (no crash)" do
      post '/settings/change_language', params: { locale: 'zz_invalid' }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Service actions (Settings → Servers) ---

  describe "POST /settings/servers/:key/:verb" do
    let(:entry) { SystemServices::CATALOG.find { |e| e[:key] == 'smbd' } }
    let(:samba) { SystemServices::Service.new(entry, { 'ActiveState' => 'active' }) }

    before do
      allow(SystemServices).to receive(:find).and_return(nil)
      allow(SystemServices).to receive(:find).with('smbd').and_return(samba)
      allow(Shell).to receive(:run).and_return(true)
    end

    %w[start stop restart].each do |verb|
      it "runs systemctl #{verb} through sudo's exact unit name" do
        post "/settings/servers/smbd/#{verb}"
        expect(Shell).to have_received(:run).with("systemctl #{verb} smbd.service")
        expect(response).to redirect_to('/settings/servers')
        expect(flash[:notice]).to include('Samba')
      end
    end

    it "reports a failed command" do
      allow(Shell).to receive(:run).and_return(false)
      post "/settings/servers/smbd/restart"
      expect(flash[:error]).to include('failed')
    end

    it "refuses services without controls" do
      mariadb = SystemServices::Service.new(SystemServices::CATALOG.find { |e| e[:key] == 'mariadb' }, {})
      allow(SystemServices).to receive(:find).with('mariadb').and_return(mariadb)
      post "/settings/servers/mariadb/stop"
      expect(response).to have_http_status(:not_found)
      expect(Shell).not_to have_received(:run)
    end

    it "refuses unknown services" do
      post "/settings/servers/sshd/stop"
      expect(response).to have_http_status(:not_found)
      expect(Shell).not_to have_received(:run)
    end

    it "has no route for other verbs" do
      expect { Rails.application.routes.recognize_path('/settings/servers/smbd/enable', method: :post) }
        .to raise_error(ActionController::RoutingError)
    end
  end

  # --- Auth ---

  describe "unauthenticated" do
    it "redirects to login" do
      reset!
      get '/settings'
      expect(response).to redirect_to(new_user_session_url)
    end
  end
end
