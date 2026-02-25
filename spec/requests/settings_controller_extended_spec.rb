require 'rails_helper'

RSpec.describe "SettingsController extended", type: :request do
  before { login_as_admin }

  describe "GET system_status" do
    it "shows system status page" do
      get "/tab/settings/system_status"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("System")
    end
  end

  describe "server management" do
    let!(:server) { Server.create!(name: "test-server", comment: "Test", pidfile: "/tmp/test.pid") }

    describe "GET refresh" do
      it "refreshes server status" do
        get "/tab/settings/servers/#{server.id}/refresh", as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST start" do
      it "starts a server" do
        allow_any_instance_of(Server).to receive(:do_start)
        post "/tab/settings/servers/#{server.id}/start", as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST stop" do
      it "stops a server" do
        allow_any_instance_of(Server).to receive(:do_stop)
        post "/tab/settings/servers/#{server.id}/stop", as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST restart" do
      it "restarts a server" do
        allow_any_instance_of(Server).to receive(:do_restart)
        post "/tab/settings/servers/#{server.id}/restart", as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT toggle_monitored" do
      it "toggles monitored flag" do
        put "/tab/settings/servers/#{server.id}/toggle_monitored", as: :json
        expect(response).to have_http_status(:ok)
        expect(server.reload.monitored).not_to eq(server.monitored_before_last_save)
      end
    end

    describe "PUT toggle_start_at_boot" do
      it "toggles start_at_boot flag" do
        original = server.start_at_boot
        put "/tab/settings/servers/#{server.id}/toggle_start_at_boot", as: :json
        expect(response).to have_http_status(:ok)
        expect(server.reload.start_at_boot).not_to eq(original)
      end
    end
  end

  describe "POST activate_theme" do
    it "activates a theme" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "amahi-kai"; s.kind = 0 }
      post "/tab/settings/activate_theme", params: { id: "amahi-kai" }
      expect(response).to redirect_to(settings_engine.themes_path)
      expect(Setting.find_by(name: "theme").value).to eq("amahi-kai")
    end
  end

  describe "POST update_system" do
    it "redirects to system_status" do
      post "/tab/settings/update_system"
      expect(response).to redirect_to(settings_engine.system_status_path)
    end
  end
end
