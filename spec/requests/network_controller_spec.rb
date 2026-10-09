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

    describe "PUT /network/update_dnsmasq_config" do
      before { allow(DnsmasqService).to receive(:running?).and_return(false) }

      it "saves the DHCP and DNS choices, so the form shows them next time" do
        put "/network/update_dnsmasq_config", params: { dhcp_enabled: '1', dyn_lo: '120' }
        expect(Setting.get('dnsmasq_dhcp')).to eq('1')
        expect(Setting.get('dnsmasq_dns')).to eq('0')
        content = Privileged.calls.find { |op, _| op == 'network.write_dnsmasq_config' }.last[:content]
        expect(content).to include('dhcp-range=', '.120,')
        expect(content).not_to include('expand-hosts')
        expect(response).to redirect_to('/network/gateway')
      end
    end

    describe "GET /network/install_dnsmasq_stream in production" do
      before { allow(Rails.env).to receive(:production?).and_return(true) }

      it "installs dnsmasq through the root helper and leaves it stopped until configured" do
        allow(DnsmasqService).to receive(:stop!).and_return(true)
        get "/network/install_dnsmasq_stream", headers: same_origin
        expect(response.body).to include("dnsmasq installed successfully")
        expect(Privileged.calls).to include(['packages.install', { packages: ['dnsmasq'] }])
        expect(DnsmasqService).to have_received(:stop!)
      end

      it "streams the helper's reason when the install fails" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.install', 'apt-get exited 100: E: oops'))
        get "/network/install_dnsmasq_stream", headers: same_origin
        expect(response.body).to include("apt-get exited 100").and include("Installation failed")
      end
    end

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
