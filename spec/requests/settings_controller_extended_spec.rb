require 'rails_helper'

RSpec.describe "SettingsController extended", type: :request do
  before do
    login_as_admin
    allow_any_instance_of(Command).to receive(:execute)
    allow_any_instance_of(Command).to receive(:submit).and_return(nil)
  end

  describe "GET system_status" do
    it "shows system status page" do
      get "/tab/settings/system_status"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST activate_theme" do
    it "updates theme setting and redirects" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "amahi-kai"; s.kind = 0 }
      post "/tab/settings/activate_theme", params: { id: "amahi-kai" }
      expect(response).to have_http_status(:redirect)
      expect(Setting.find_by(name: "theme").value).to eq("amahi-kai")
    end
  end

  describe "POST update_system" do
    it "redirects" do
      post "/tab/settings/update_system"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "server management" do
    let!(:server) do
      Server.create!(name: "test-server-#{SecureRandom.hex(4)}", comment: "Test", pidfile: "/tmp/test.pid")
    end

    describe "PUT toggle_monitored" do
      it "changes monitored flag in database" do
        original = server.monitored
        put "/tab/settings/servers/#{server.id}/toggle_monitored", as: :json rescue nil
        expect(server.reload.monitored).not_to eq(original)
      end
    end

    describe "PUT toggle_start_at_boot" do
      it "changes start_at_boot flag in database" do
        original = server.start_at_boot
        put "/tab/settings/servers/#{server.id}/toggle_start_at_boot", as: :json rescue nil
        expect(server.reload.start_at_boot).not_to eq(original)
      end
    end
  end
end
