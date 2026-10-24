require 'spec_helper'

describe "Network Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/network"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/network"
      expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /network (devices)" do
      it "shows the devices seen and the fixed addresses, with the old Hosts page sent here" do
        allow(DnsmasqService).to receive(:rewrite_config!)
        allow(DnsService).to receive(:rewrite!)
        Host.create!(name: "printer", mac: "aa:bb:cc:dd:ee:01", address: "20")
        allow(Leases).to receive(:all).and_return([{ expiration: Time.now.to_i + 3600, mac: "aa:bb:cc:dd:ee:01", ip: "192.168.1.20", name: "printer" },
                                                   { expiration: Time.now.to_i + 600, mac: "aa:bb:cc:dd:ee:02", ip: "192.168.1.150", name: "laptop" }])
        get "/network"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("2 devices seen", "Fixed at <code>192.168.1.20</code>", "laptop", "Fix this address", "Unfix")
        get "/network/hosts"
        expect(response).to redirect_to("/network")
      end
    end

    describe "POST /network/hosts" do
      before do
        allow(DnsmasqService).to receive(:rewrite_config!)
        allow(DnsService).to receive(:rewrite!)
      end

      it "gives a device a fixed address" do
        expect { post "/network/hosts", params: { host: { name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "50" } } }.to change(Host, :count).by(1)
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("myhost keeps 192.168.1.50.")
      end

      it "says why it refused one" do
        expect { post "/network/hosts", params: { host: { name: "my_host", mac: "aa:bb", address: "50" } } }.not_to change(Host, :count)
        expect(flash[:alert]).to include("Mac")
      end

      it "takes a fixed address away" do
        host = Host.create!(name: "testhost", mac: "aa:bb:cc:dd:ee:01", address: "51")
        expect { delete "/network/host/#{host.id}" }.to change(Host, :count).by(-1)
        expect(flash[:notice]).to eq("testhost no longer has a fixed address.")
      end
    end

    it "sends the old DNS Aliases, Gateway and Settings pages to the new tabs" do
      get "/network/dns_aliases"
      expect(response).to redirect_to("/network/dns#dns-aliases")
      get "/network/gateway"
      expect(response).to redirect_to("/network/dhcp")
      get "/network/settings"
      expect(response).to redirect_to("/network/dns")
    end

    describe "GET /network/remote_access" do
      it "renders the remote access page" do
        allow(CloudflareService).to receive(:status).and_return({ installed: false, running: false })
        allow(SecurityAudit).to receive(:blockers).and_return([])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end

      it "renders with tunnel running" do
        allow(CloudflareService).to receive(:status).and_return({ installed: true, running: true, token_configured: true })
        allow(SecurityAudit).to receive(:blockers).and_return([])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end

      it "renders with security blockers present" do
        allow(CloudflareService).to receive(:status).and_return({ installed: false, running: false })
        allow(SecurityAudit).to receive(:blockers).and_return(["ufw_firewall"])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /network/start_tunnel" do
      it "starts the tunnel" do
        allow(SecurityAudit).to receive(:blockers).and_return([])
        allow(CloudflareService).to receive(:start!).and_return(true)
        post "/network/remote_access/start_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "POST /network/stop_tunnel" do
      it "stops the tunnel" do
        allow(CloudflareService).to receive(:stop!).and_return(true)
        post "/network/remote_access/stop_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    # --- Security ---

    describe "GET /network/security" do
      it "renders the security page" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        get "/network/security"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Security blockers found!")
      end

      it "says so when a blocker fails" do
        blocker = SecurityAudit::Check.new(name: 'ufw_firewall', description: 'UFW firewall enabled',
                                           status: :fail, severity: :blocker)
        allow(SecurityAudit).to receive(:run_all).and_return([blocker])
        get "/network/security"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Security blockers found!")
      end
    end

    describe "GET /network/security/audit_stream" do
      it "returns SSE content type" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        get "/network/security/audit_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "GET /network/security/fix_stream" do
      it "returns SSE content type" do
        get "/network/security/fix_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "POST /network/security/fix" do
      it "fixes a specific security check" do
        allow(SecurityAudit).to receive(:fix!).with("ufw_firewall").and_return(true)
        post "/network/security/fix", params: { check_name: "ufw_firewall" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(body["check"]).to eq("ufw_firewall")
      end

      it "returns error when fix fails" do
        allow(SecurityAudit).to receive(:fix!).with("unknown_check").and_return(false)
        post "/network/security/fix", params: { check_name: "unknown_check" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("error")
      end
    end
  end
end
