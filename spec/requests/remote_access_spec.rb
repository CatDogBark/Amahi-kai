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

      # P4.7: what an app reached only through Tailscale (Vaultwarden) needs from the tailnet
      it "says whether Tailscale's HTTPS certificates are on, and what apps reached through it need" do
        connected = { installed: true, running: true, tailscale_ip: '100.64.0.1', hostname: 'amahi-kai.tail1234.ts.net',
                      magic_dns: 'amahi-kai.tail1234.ts.net', peers: 1, magic_dns_on: true, https_certificates: false }
        allow(TailscaleService).to receive(:status).and_return(connected)
        get '/network/remote_access'
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#tailscale-https').text.squish).to eq('HTTPS certificates Off')
        expect(page.at_css('#tailscale-https-note').text.squish)
          .to start_with('Apps reached only through Tailscale (Vaultwarden) need MagicDNS and HTTPS Certificates on')

        allow(TailscaleService).to receive(:status).and_return(connected.merge(https_certificates: true))
        get '/network/remote_access'
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#tailscale-https').text.squish).to eq('HTTPS certificates 🟢 On')
        expect(page.at_css('#tailscale-https-note').text.squish).to include('are served over HTTPS at this NAS')
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

    # Asked every few seconds by the page while a sign-in waits in another tab (Connect)
    describe "GET tailscale_status" do
      it "says whether Tailscale is connected" do
        allow(TailscaleService).to receive(:running?).and_return(false)
        get '/network/remote_access/tailscale_status', as: :json
        expect(response.parsed_body).to eq('running' => false)
        allow(TailscaleService).to receive(:running?).and_return(true)
        get '/network/remote_access/tailscale_status', as: :json
        expect(response.parsed_body).to eq('running' => true)
      end

      it "gives the Connect button its address" do
        allow(TailscaleService).to receive(:status).and_return(installed: true, running: false)
        get '/network/remote_access'
        button = Nokogiri::HTML(response.body).at_css('[data-call="startTailscale"]')
        expect(JSON.parse(button['data-args'])).to eq(['@el', '/network/remote_access/start_tailscale', '/network/remote_access/tailscale_status'])
      end

      it "gives the install window the same address, to wait for the sign-in" do
        allow(TailscaleService).to receive(:status).and_return(installed: false, running: false)
        get '/network/remote_access'
        button = Nokogiri::HTML(response.body).at_css('[data-call="installTailscale"]')
        expect(JSON.parse(button['data-args'])).to eq(['/network/remote_access/install_tailscale_stream', '/network/remote_access/tailscale_status'])
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
