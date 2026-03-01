require 'spec_helper'

RSpec.describe "RemoteAccess extended", type: :request do
  before do
    login_as_admin
    allow(CloudflareService).to receive_messages(
      status: { installed: true, running: false },
      start!: true, stop!: true, configure!: true,
      installed?: true, install!: true, running?: true
    )
    allow(TailscaleService).to receive_messages(
      status: { installed: true, running: false },
      start!: { success: true, auth_url: 'https://login.tailscale.com/a/test123' },
      stop!: true, logout!: true
    )
    allow(SecurityAudit).to receive(:blockers).and_return([])
  end

  # --- Tailscale ---

  describe "POST start_tailscale" do
    it "returns auth_url when present" do
      post '/network/remote_access/start_tailscale', as: :json
      body = response.parsed_body
      expect(body['status']).to eq('ok')
      expect(body['auth_url']).to eq('https://login.tailscale.com/a/test123')
    end

    it "returns ok without auth_url when already authenticated" do
      allow(TailscaleService).to receive(:start!).and_return({ success: true, auth_url: nil })
      post '/network/remote_access/start_tailscale', as: :json
      body = response.parsed_body
      expect(body['status']).to eq('ok')
      expect(body['auth_url']).to be_nil
    end
  end

  describe "POST stop_tailscale" do
    it "stops tailscale successfully" do
      post '/network/remote_access/stop_tailscale', as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(TailscaleService).to have_received(:stop!)
    end
  end

  describe "POST logout_tailscale" do
    it "logs out tailscale" do
      post '/network/remote_access/logout_tailscale', as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(TailscaleService).to have_received(:logout!)
    end
  end

  # --- Cloudflare tunnel ---

  describe "POST configure_tunnel" do
    it "configures and starts with valid token" do
      post '/network/remote_access/configure_tunnel', params: { tunnel_token: 'valid-token' }, as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(CloudflareService).to have_received(:configure!).with('valid-token')
      expect(CloudflareService).to have_received(:start!)
    end

    it "rejects blank token" do
      post '/network/remote_access/configure_tunnel', params: { tunnel_token: '  ' }, as: :json
      expect(response.parsed_body['status']).to eq('not_acceptable')
    end

    it "returns error on exception" do
      allow(CloudflareService).to receive(:configure!).and_raise(StandardError.new("config failed"))
      post '/network/remote_access/configure_tunnel', params: { tunnel_token: 'tok' }, as: :json
      body = response.parsed_body
      expect(body['status']).to eq('error')
      expect(body['error']).to include('config failed')
    end
  end

  describe "POST start_tunnel" do
    it "starts the tunnel" do
      post '/network/remote_access/start_tunnel', as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(CloudflareService).to have_received(:start!)
    end
  end

  describe "POST stop_tunnel" do
    it "stops the tunnel" do
      post '/network/remote_access/stop_tunnel', as: :json
      expect(response.parsed_body['status']).to eq('ok')
      expect(CloudflareService).to have_received(:stop!)
    end
  end

  # --- SSE streams ---

  describe "GET install_cloudflared_stream" do
    it "returns SSE content type" do
      get '/network/remote_access/install_cloudflared_stream'
      expect(response.content_type).to include('text/event-stream')
    end
  end

  describe "GET setup_tunnel_stream" do
    it "returns SSE content type" do
      get '/network/remote_access/setup_tunnel_stream', params: { token: 'test-token' }
      expect(response.content_type).to include('text/event-stream')
    end

    it "streams error when token is blank" do
      get '/network/remote_access/setup_tunnel_stream', params: { token: '' }
      expect(response.content_type).to include('text/event-stream')
      expect(response.body).to include('No tunnel token')
    end
  end

  describe "GET install_tailscale_stream" do
    it "returns SSE content type" do
      get '/network/remote_access/install_tailscale_stream'
      expect(response.content_type).to include('text/event-stream')
    end
  end

  # --- Index page ---

  describe "GET /network/remote_access" do
    it "shows remote access page with status info" do
      get '/network/remote_access'
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Auth ---

  describe "unauthenticated" do
    it "redirects all actions to login" do
      reset!
      post '/network/remote_access/start_tailscale', as: :json
      expect(response).to redirect_to(new_user_session_url)
    end
  end
end
