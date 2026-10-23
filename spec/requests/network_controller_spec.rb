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

    it "shows why it refused a new host or alias, in the form, open, with what was typed" do
      post "/network/hosts", params: { host: { name: "my_host", mac: "aa:bb", address: "50" } }
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#new-host-step1')['style']).to be_nil
      expect(page.at_css('#new-host-step1 .alert-danger').text).to include('Mac')
      expect(page.at_css('input[name="host[mac]"]')['value']).to eq('aa:bb')

      post "/network/dns_aliases", params: { dns_alias: { name: "", address: "60" } }
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#new-dns-alias-step1')['style']).to be_nil
      expect(page.at_css('input[name="dns_alias[address]"]')['value']).to eq('60')
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

    it "sends the old Gateway and Settings pages to DNS & DHCP" do
      get "/network/gateway"
      expect(response).to redirect_to("/network/dns")
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
