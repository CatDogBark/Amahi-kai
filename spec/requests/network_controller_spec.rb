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
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /network (leases)" do
      it "shows the network page" do
        get "/network"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /network/hosts" do
      it "shows the hosts page" do
        get "/network/hosts"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /network/hosts" do
      it "creates a new host" do
        allow_any_instance_of(Host).to receive(:restart)
        expect {
          post "/network/hosts", params: { host: { name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "50" } }, as: :json
        }.to change(Host, :count).by(1)
      end

      it "rejects host with invalid mac" do
        allow_any_instance_of(Host).to receive(:restart)
        expect {
          post "/network/hosts", params: { host: { name: "myhost", mac: "invalid", address: "50" } }, as: :json
        }.not_to change(Host, :count)
      end
    end

    describe "DELETE /network/host/:id" do
      it "destroys a host" do
        allow_any_instance_of(Host).to receive(:restart)
        host = Host.create!(name: "testhost", mac: "aa:bb:cc:dd:ee:01", address: "51")
        expect {
          delete "/network/host/#{host.id}", as: :json
        }.to change(Host, :count).by(-1)
      end
    end

    describe "DNS aliases" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows dns aliases page" do
        get "/network/dns_aliases"
        expect(response).to have_http_status(:ok)
      end

      it "creates a dns alias" do
        allow_any_instance_of(DnsAlias).to receive(:restart)
        expect {
          post "/network/dns_aliases", params: { dns_alias: { name: "myalias", address: "192.168.1.100" } }, as: :json
        }.to change(DnsAlias, :count).by(1)
      end

      it "destroys a dns alias" do
        allow_any_instance_of(DnsAlias).to receive(:restart)
        dns_alias = DnsAlias.create!(name: "testalias", address: "192.168.1.100")
        expect {
          delete "/network/dns_alias/#{dns_alias.id}", as: :json
        }.to change(DnsAlias, :count).by(-1)
      end

      it "rejects dns alias with blank name" do
        allow_any_instance_of(DnsAlias).to receive(:restart)
        expect {
          post "/network/dns_aliases", params: { dns_alias: { name: "", address: "192.168.1.100" } }, as: :json
        }.not_to change(DnsAlias, :count)
      end

      it "redirects to index if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/network/dns_aliases"
        expect(response).to redirect_to("/network")
      end
    end

    describe "network settings" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows settings page" do
        get "/network/settings"
        expect(response).to have_http_status(:ok)
      end

      it "redirects to index if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/network/settings"
        expect(response).to redirect_to("/network")
      end
    end

    describe "PUT /network/update_dns" do
      before { allow_any_instance_of(Kernel).to receive(:system) }

      it "updates dns to google" do
        put "/network/update_dns", params: { setting_dns: "google" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "updates dns to cloudflare" do
        put "/network/update_dns", params: { setting_dns: "cloudflare" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "updates dns to opennic" do
        put "/network/update_dns", params: { setting_dns: "opennic" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "handles unknown dns provider gracefully" do
        put "/network/update_dns", params: { setting_dns: "unknown_provider" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "PUT /network/update_dns_ips" do
      before { allow_any_instance_of(Kernel).to receive(:system) }

      it "updates custom DNS IPs" do
        put "/network/update_dns_ips", params: { dns_ip_1: "8.8.8.8", dns_ip_2: "8.8.4.4" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects invalid DNS IPs" do
        put "/network/update_dns_ips", params: { dns_ip_1: "not_an_ip", dns_ip_2: "8.8.4.4" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    describe "PUT /network/update_lease_time" do
      before { allow_any_instance_of(Kernel).to receive(:system) }

      it "updates lease time with valid value" do
        put "/network/update_lease_time", params: { lease_time: "7200" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects zero lease time" do
        put "/network/update_lease_time", params: { lease_time: "0" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "rejects blank lease time" do
        put "/network/update_lease_time", params: { lease_time: "" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "rejects negative lease time" do
        put "/network/update_lease_time", params: { lease_time: "-100" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    describe "PUT /network/update_gateway" do
      it "updates gateway with valid value" do
        allow_any_instance_of(Kernel).to receive(:system)
        Setting.create!(name: "net", value: "192.168.1", kind: Setting::NETWORK) unless Setting.find_by(name: "net")
        put "/network/update_gateway", params: { gateway: "1" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(body["data"]).to include("192.168.1.1")
      end

      it "rejects out-of-range gateway (too high)" do
        put "/network/update_gateway", params: { gateway: "300" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "rejects zero gateway" do
        put "/network/update_gateway", params: { gateway: "0" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "rejects negative gateway" do
        put "/network/update_gateway", params: { gateway: "-1" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    describe "PUT /network/toggle_setting/:id" do
      before { allow_any_instance_of(Kernel).to receive(:system) }

      it "toggles a network setting from 1 to 0" do
        setting = Setting.create!(name: "dnsmasq_dhcp", value: "1", kind: Setting::NETWORK)
        put "/network/toggle_setting/#{setting.id}", as: :json
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("0")
      end

      it "toggles a network setting from 0 to 1" do
        setting = Setting.create!(name: "dnsmasq_dns", value: "0", kind: Setting::NETWORK)
        put "/network/toggle_setting/#{setting.id}", as: :json
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("1")
      end
    end

    describe "PUT /network/update_dhcp_range/:id" do
      before do
        allow_any_instance_of(Kernel).to receive(:system)
        Setting.create!(name: "dyn_lo", value: "100", kind: Setting::NETWORK)
        Setting.create!(name: "dyn_hi", value: "254", kind: Setting::NETWORK)
      end

      it "updates min range" do
        put "/network/update_dhcp_range/min", params: { id: "min", dyn_lo: "50" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "updates max range" do
        put "/network/update_dhcp_range/max", params: { id: "max", dyn_hi: "240" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects invalid range (too narrow)" do
        put "/network/update_dhcp_range/min", params: { id: "min", dyn_lo: "250" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "rejects max range below min + IP_RANGE" do
        put "/network/update_dhcp_range/max", params: { id: "max", dyn_hi: "105" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    # --- Remote Access (Cloudflare Tunnel) ---

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

    describe "POST /network/configure_tunnel" do
      it "configures and starts tunnel with valid token" do
        allow(CloudflareService).to receive(:configure!)
        allow(CloudflareService).to receive(:start!)
        post "/network/remote_access/configure_tunnel", params: { tunnel_token: "eyJhIjoiYWJjMTIzIn0=" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects blank token" do
        post "/network/remote_access/configure_tunnel", params: { tunnel_token: "" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
        expect(body["error"]).to eq("Token is required")
      end

      it "rejects whitespace-only token" do
        post "/network/remote_access/configure_tunnel", params: { tunnel_token: "   " }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end

      it "handles configuration errors gracefully" do
        allow(CloudflareService).to receive(:configure!).and_raise(RuntimeError, "Invalid token format")
        post "/network/remote_access/configure_tunnel", params: { tunnel_token: "bad-token" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("error")
        expect(body["error"]).to include("Invalid token format")
      end
    end

    describe "POST /network/start_tunnel" do
      it "starts the tunnel" do
        allow(CloudflareService).to receive(:start!)
        post "/network/remote_access/start_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "POST /network/stop_tunnel" do
      it "stops the tunnel" do
        allow(CloudflareService).to receive(:stop!)
        post "/network/remote_access/stop_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "GET /network/install_cloudflared_stream" do
      it "returns SSE content type" do
        get "/network/remote_access/install_cloudflared_stream"
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    # --- Security ---

    describe "GET /network/security" do
      it "renders the security page" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        allow(SecurityAudit).to receive(:has_blockers?).and_return(false)
        get "/network/security"
        expect(response).to have_http_status(:ok)
      end

      it "renders with blockers present" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        allow(SecurityAudit).to receive(:has_blockers?).and_return(true)
        get "/network/security"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /network/security/audit_stream" do
      it "returns SSE content type" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        get "/network/security/audit_stream"
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "GET /network/security/fix_stream" do
      it "returns SSE content type" do
        get "/network/security/fix_stream"
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
