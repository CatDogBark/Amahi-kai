require 'spec_helper'

describe "Network tab", type: :request do
  before { login_as_admin }

  describe "Fixed IPs" do
    it "renders the hosts page" do
      get network_engine.hosts_path
      expect(response).to have_http_status(:ok)
    end

    it "creates a new fixed IP" do
      post network_engine.hosts_path, params: {
        host: { name: "testIP", mac: "11:22:33:44:55:66", address: "10" }
      }
      expect(Host.find_by(name: "testIP")).to be_present
    end
  end

  describe "DNS Aliases" do
    it "renders the DNS aliases page" do
      get network_engine.dns_aliases_path
      expect(response).to have_http_status(:ok)
    end

    it "creates a new DNS alias" do
      post network_engine.dns_aliases_path, params: {
        dns_alias: { name: "testdns", address: "10" }
      }
      expect(DnsAlias.find_by(name: "testdns")).to be_present
    end
  end
end
