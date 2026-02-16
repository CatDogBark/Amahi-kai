require 'spec_helper'

describe "Network Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/tab/network"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/tab/network"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /tab/network (leases)" do
      it "shows the network page" do
        get "/tab/network"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/network/hosts" do
      it "shows the hosts page" do
        get "/tab/network/hosts"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /tab/network/hosts" do
      it "creates a new host" do
        allow_any_instance_of(Host).to receive(:restart)
        expect {
          post "/tab/network/hosts", params: { host: { name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "50" } }, as: :json
        }.to change(Host, :count).by(1)
      end

      it "rejects host with invalid mac" do
        allow_any_instance_of(Host).to receive(:restart)
        expect {
          post "/tab/network/hosts", params: { host: { name: "myhost", mac: "invalid", address: "50" } }, as: :json
        }.not_to change(Host, :count)
      end
    end

    describe "DELETE /tab/network/host/:id" do
      it "destroys a host" do
        allow_any_instance_of(Host).to receive(:restart)
        host = Host.create!(name: "testhost", mac: "aa:bb:cc:dd:ee:01", address: "51")
        expect {
          delete "/tab/network/host/#{host.id}", as: :json
        }.to change(Host, :count).by(-1)
      end
    end

    describe "DNS aliases" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows dns aliases page" do
        get "/tab/network/dns_aliases"
        expect(response).to have_http_status(:ok)
      end

      it "creates a dns alias" do
        allow_any_instance_of(DnsAlias).to receive(:restart)
        expect {
          post "/tab/network/dns_aliases", params: { dns_alias: { name: "myalias", address: "192.168.1.100" } }, as: :json
        }.to change(DnsAlias, :count).by(1)
      end

      it "destroys a dns alias" do
        allow_any_instance_of(DnsAlias).to receive(:restart)
        dns_alias = DnsAlias.create!(name: "testalias", address: "192.168.1.100")
        expect {
          delete "/tab/network/dns_alias/#{dns_alias.id}", as: :json
        }.to change(DnsAlias, :count).by(-1)
      end

      it "redirects to index if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/tab/network/dns_aliases"
        expect(response).to redirect_to("/tab/network")
      end
    end

    describe "network settings" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows settings page" do
        get "/tab/network/settings"
        expect(response).to have_http_status(:ok)
      end

      it "redirects to index if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/tab/network/settings"
        expect(response).to redirect_to("/tab/network")
      end
    end

    describe "PUT /tab/network/update_dns" do
      it "updates dns to a known provider" do
        allow_any_instance_of(Kernel).to receive(:system)
        put "/tab/network/update_dns", params: { setting_dns: "google" }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "PUT /tab/network/update_lease_time" do
      it "updates lease time with valid value" do
        allow_any_instance_of(Kernel).to receive(:system)
        put "/tab/network/update_lease_time", params: { lease_time: "7200" }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects invalid lease time" do
        allow_any_instance_of(Kernel).to receive(:system)
        put "/tab/network/update_lease_time", params: { lease_time: "0" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    describe "PUT /tab/network/update_gateway" do
      it "updates gateway with valid value" do
        allow_any_instance_of(Kernel).to receive(:system)
        Setting.create!(name: "net", value: "192.168.1", kind: Setting::NETWORK) unless Setting.find_by(name: "net")
        put "/tab/network/update_gateway", params: { gateway: "1" }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects out-of-range gateway" do
        put "/tab/network/update_gateway", params: { gateway: "300" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    describe "PUT /tab/network/toggle_setting/:id" do
      it "toggles a network setting" do
        allow_any_instance_of(Kernel).to receive(:system)
        setting = Setting.create!(name: "dnsmasq_dhcp", value: "1", kind: Setting::NETWORK)
        put "/tab/network/toggle_setting/#{setting.id}", as: :json
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("0")
      end
    end

    describe "PUT /tab/network/update_dhcp_range/:id" do
      before do
        allow_any_instance_of(Kernel).to receive(:system)
        Setting.create!(name: "dyn_lo", value: "100", kind: Setting::NETWORK)
        Setting.create!(name: "dyn_hi", value: "254", kind: Setting::NETWORK)
      end

      it "updates min range" do
        put "/tab/network/update_dhcp_range/min", params: { id: "min", dyn_lo: "50" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "rejects invalid range (too narrow)" do
        put "/tab/network/update_dhcp_range/min", params: { id: "min", dyn_lo: "250" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end
  end
end
