require 'spec_helper'

describe "RemoteAccess Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get '/network/remote_access'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects non-admin users" do
      login_as_user
      get '/network/remote_access'
      expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
    end
  end

  describe "admin" do
    before do
      @admin = login_as_admin
      allow(CloudflareService).to receive_messages(status: { installed: false, running: false }, start!: true, stop!: true, configure!: true, installed?: false, install!: true, running?: false)
      allow(TailscaleService).to receive_messages(status: { installed: false, running: false }, start!: { success: true, auth_url: nil }, stop!: true, logout!: true)
      allow(SecurityAudit).to receive(:blockers).and_return([])
    end

    describe "GET /network/remote_access" do
      it "shows the remote access page" do
        get '/network/remote_access'
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST start_tunnel" do
      it "starts the tunnel" do
        post '/network/remote_access/start_tunnel', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end

    describe "POST stop_tunnel" do
      it "stops the tunnel" do
        post '/network/remote_access/stop_tunnel', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end

    describe "POST start_tailscale" do
      it "starts tailscale" do
        post '/network/remote_access/start_tailscale', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end

    describe "POST stop_tailscale" do
      it "stops tailscale" do
        post '/network/remote_access/stop_tailscale', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end

    describe "POST logout_tailscale" do
      it "logs out tailscale" do
        post '/network/remote_access/logout_tailscale', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end
  end
end
