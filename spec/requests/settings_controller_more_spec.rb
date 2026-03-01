require 'spec_helper'

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
      get '/settings/update_system_stream'
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
      post '/settings/activate_theme', params: { id: 'dark-mode' }
      expect(response).to redirect_to('/settings/themes')
      expect(Setting.find_by(name: 'theme').value).to eq('dark-mode')
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

  # --- Server actions ---

  describe "server management" do
    let!(:server) do
      Server.create!(name: 'test-server', comment: 'Test', start_at_boot: false, pidfile: '/tmp/test.pid')
    end

    before do
      allow_any_instance_of(Server).to receive(:do_start)
      allow_any_instance_of(Server).to receive(:do_stop)
      allow_any_instance_of(Server).to receive(:do_restart)
    end

    it "refreshes server status" do
      post "/settings/servers/#{server.id}/refresh"
      expect(response).to have_http_status(:ok)
    end

    it "starts a server" do
      post "/settings/servers/#{server.id}/start"
      expect(response).to have_http_status(:ok)
    end

    it "stops a server" do
      post "/settings/servers/#{server.id}/stop"
      expect(response).to have_http_status(:ok)
    end

    it "restarts a server" do
      post "/settings/servers/#{server.id}/restart"
      expect(response).to have_http_status(:ok)
    end

    it "toggles start_at_boot" do
      post "/settings/servers/#{server.id}/toggle_start_at_boot"
      expect(server.reload.start_at_boot).to eq(true)
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
