require 'rails_helper'

# Actions that change the system can't be triggered by a plain link from another
# site. One-shot actions are POST-only, so the CSRF token protects them. Streams
# must be GET for EventSource, so they only start when the browser says the
# request came from an Amahi page (Sec-Fetch-Site: same-origin).
RSpec.describe "Link-triggered actions", type: :request do
  before { login_as_admin }

  describe "one-shot actions" do
    %w[
      /settings/reboot
      /settings/poweroff
      /settings/toggle_setting
      /settings/change_language
      /settings/activate_theme
      /settings/servers/1/refresh
      /settings/servers/1/start
      /settings/servers/1/stop
      /settings/servers/1/restart
      /settings/servers/1/toggle_start_at_boot
      /logout
    ].each do |path|
      it "has no GET route for #{path}" do
        expect { Rails.application.routes.recognize_path(path, method: :get) }
          .to raise_error(ActionController::RoutingError)
      end
    end

    it "does not power off on GET" do
      allow(Platform).to receive(:poweroff!)
      get "/settings/poweroff"
      expect(response).to have_http_status(:not_found)
      expect(Platform).not_to have_received(:poweroff!)
    end

    it "still powers off on POST" do
      allow(Platform).to receive(:poweroff!)
      post "/settings/poweroff"
      expect(Platform).to have_received(:poweroff!)
    end

    it "logs out on DELETE /logout" do
      delete logout_path
      expect(response).to redirect_to(root_path)
    end

    it "renders power off and reboot as confirmed POST buttons" do
      get settings_index_path
      expect(response.body).to include('action="/settings/poweroff"', 'action="/settings/reboot"')
      expect(response.body).to include('onsubmit="return confirm(')
    end
  end

  describe "streams" do
    it "refuses a stream opened from another site" do
      get "/settings/update_system_stream", headers: { 'Sec-Fetch-Site' => 'cross-site' }
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a stream without a Sec-Fetch-Site header" do
      get "/settings/update_system_stream"
      expect(response).to have_http_status(:forbidden)
    end

    it "accepts a stream opened by an Amahi page" do
      get "/settings/update_system_stream", headers: same_origin
      expect(response.media_type).to eq("text/event-stream")
    end

    it "does not prepare or format drives for a cross-site request" do
      Setting.set('setup_completed', 'false')
      allow(DiskManager).to receive(:format_disk!)
      get setup_prepare_drives_stream_path,
        params: { drives: "/dev/sdb1", format_drives: "/dev/sdb1" },
        headers: { 'Sec-Fetch-Site' => 'cross-site' }
      expect(response).to have_http_status(:forbidden)
      expect(DiskManager).not_to have_received(:format_disk!)
    end
  end

  describe "setup wizard after setup is complete" do
    before { Setting.set('setup_completed', 'true') }

    it "redirects wizard pages to the dashboard" do
      get setup_welcome_path
      expect(response).to redirect_to(root_path)
    end

    it "does not prepare drives" do
      allow(DiskManager).to receive(:format_disk!)
      get setup_prepare_drives_stream_path,
        params: { drives: "/dev/sdb1", format_drives: "/dev/sdb1" }, headers: same_origin
      expect(response).to redirect_to(root_path)
      expect(DiskManager).not_to have_received(:format_disk!)
    end
  end
end
