require 'rails_helper'

RSpec.describe "Full integration flows", type: :request do
  before { login_as_admin }

  describe "Share lifecycle" do
    it "creates, configures, and destroys a share" do
      # Create
      post shares_path, params: { share: { name: "IntegrationTest" } }
      share = Share.find_by(name: "IntegrationTest")
      expect(share).to be_present

      # Verify toggle works at DB level (partials may not render in test)
      share.update!(visible: true)
      share.toggle_visible!
      expect(share.reload.visible).to eq(false)

      share.toggle_readonly!
      expect(share.reload.rdonly).to eq(true)

      # Destroy
      share.destroy
      expect(Share.find_by(id: share.id)).to be_nil
    end
  end

  describe "User lifecycle" do
    it "lists users" do
      get users_engine.users_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Username")
    end
  end

  describe "DNS alias lifecycle" do
    before do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "1"; s.kind = Setting::GENERAL }
      Setting.find_by(name: "advanced").update!(value: "1")
    end

    it "creates and destroys a DNS alias" do
      allow_any_instance_of(DnsAlias).to receive(:restart)

      post "/network/dns_aliases", params: {
        dns_alias: { name: "testflow", address: "192.168.1.200" }
      }, as: :json
      dns = DnsAlias.find_by(name: "testflow")
      expect(dns).to be_present
      expect(dns.address).to eq("192.168.1.200")

      delete "/network/dns_alias/#{dns.id}", as: :json
      expect(DnsAlias.find_by(id: dns.id)).to be_nil
    end
  end

  describe "Docker app catalog" do
    it "views the app catalog" do
      get "/tab/apps"
      expect(response).to have_http_status(:ok)
    end

    it "views installed apps" do
      get "/tab/apps/installed_apps"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Settings pages" do
    it "views settings page" do
      get "/tab/settings"
      expect(response).to have_http_status(:ok)
    end

    it "views debug page" do
      get "/tab/debug"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Disk management" do
    it "views disks page" do
      get "/tab/disks"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Search with real data" do
    it "finds indexed files by name" do
      share = create(:share, name: "SearchTest")
      ShareFile.create!(share: share, name: "vacation_photo.jpg",
                        path: "#{share.path}/vacation_photo.jpg",
                        relative_path: "vacation_photo.jpg",
                        content_type: "image", extension: "jpg")

      get search_hda_path, params: { query: "vacation" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("vacation")
    end
  end

  describe "Security audit" do
    before do
      Setting.find_or_create_by!(name: "advanced") { |s| s.value = "1"; s.kind = Setting::GENERAL }
      Setting.find_by(name: "advanced").update!(value: "1")
    end

    it "shows security page" do
      get "/network/security"
      expect(response).to have_http_status(:ok)
    end
  end
end
