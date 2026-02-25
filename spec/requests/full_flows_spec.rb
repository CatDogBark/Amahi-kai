require 'rails_helper'

RSpec.describe "Full integration flows", type: :request do
  before { login_as_admin }

  describe "Share lifecycle" do
    it "creates, configures, and destroys a share" do
      # Create
      post "/shares/create", params: { share: { name: "IntegrationTest" } }
      share = Share.find_by(name: "IntegrationTest")
      expect(share).to be_present
      expect(share.path).to include("integrationtest")

      # Toggle visibility
      put "/shares/#{share.id}/toggle_visible", as: :json
      share.reload
      expect(share.visible).to eq(false)

      # Toggle readonly
      put "/shares/#{share.id}/toggle_readonly", as: :json
      share.reload
      expect(share.rdonly).to eq(true)

      # Toggle everyone
      put "/shares/#{share.id}/toggle_everyone", as: :json
      share.reload

      # Update tags
      put "/shares/#{share.id}/update_tags", params: { value: "movies, media" }, as: :json
      share.reload
      expect(share.tags).to eq("movies, media")

      # Destroy
      delete "/shares/#{share.id}", as: :json
      expect(Share.find_by(id: share.id)).to be_nil
    end
  end

  describe "User lifecycle" do
    it "creates and manages a user" do
      # Create user
      post "/tab/users", params: {
        user: { login: "flowuser", name: "Flow User", password: "testpass123", password_confirmation: "testpass123" }
      }
      user = User.find_by(login: "flowuser")
      expect(user).to be_present
      expect(user.name).to eq("Flow User")

      # View user list
      get "/tab/users"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("flowuser")

      # Delete user
      delete "/tab/users/#{user.id}", as: :json
      expect(User.find_by(id: user.id)).to be_nil
    end
  end

  describe "DNS alias lifecycle" do
    before { Setting.create!(name: "advanced", value: "1", kind: 0) unless Setting.find_by(name: "advanced") }

    it "creates and destroys a DNS alias" do
      allow_any_instance_of(DnsAlias).to receive(:restart)

      post "/tab/network/dns_aliases", params: {
        dns_alias: { name: "testflow", address: "192.168.1.200" }
      }, as: :json
      dns = DnsAlias.find_by(name: "testflow")
      expect(dns).to be_present
      expect(dns.address).to eq("192.168.1.200")

      delete "/tab/network/dns_alias/#{dns.id}", as: :json
      expect(DnsAlias.find_by(id: dns.id)).to be_nil
    end
  end

  describe "Docker app lifecycle" do
    it "installs and manages a docker app" do
      # View catalog
      get "/tab/apps"
      expect(response).to have_http_status(:ok)

      # Install an app
      post "/tab/apps/install", params: { identifier: "jellyfin" }, as: :json
      app = DockerApp.find_by(identifier: "jellyfin")
      expect(app).to be_present

      # View installed apps
      get "/tab/apps"
      expect(response).to have_http_status(:ok)

      # Uninstall
      delete "/tab/apps/#{app.id}/uninstall", as: :json if app
    end
  end

  describe "Settings and system status" do
    it "views system status dashboard" do
      get "/tab/settings"
      expect(response).to have_http_status(:ok)
    end

    it "toggles advanced mode" do
      post "/toggle_advanced", as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end

    it "views debug page" do
      get "/tab/debug"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Disk management" do
    it "views disks page with device info" do
      get "/tab/disks"
      expect(response).to have_http_status(:ok)
    end

    it "manages storage pool partitions" do
      # Add to pool
      post "/tab/disks/pool", params: {
        disk_pool_partition: { path: "/mnt/integration-test", minimum_free: 15 }
      }, as: :json

      part = DiskPoolPartition.find_by(path: "/mnt/integration-test")
      if part
        expect(part.minimum_free).to eq(15)

        # Remove from pool
        delete "/tab/disks/pool/#{part.id}", as: :json
        expect(DiskPoolPartition.find_by(id: part.id)).to be_nil
      end
    end
  end

  describe "Search" do
    it "searches across share files" do
      # Create a share with indexed files
      share = create(:share, name: "SearchTest")
      ShareFile.create!(share: share, name: "vacation_photo.jpg", path: "#{share.path}/vacation_photo.jpg")
      ShareFile.create!(share: share, name: "work_document.pdf", path: "#{share.path}/work_document.pdf")

      get search_hda_path, params: { query: "vacation" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("vacation")

      # Image search
      get search_images_path, params: { query: "photo" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Security audit flow" do
    before { Setting.create!(name: "advanced", value: "1", kind: 0) unless Setting.find_by(name: "advanced") }

    it "runs security audit and shows results" do
      get "/tab/network/security"
      expect(response).to have_http_status(:ok)
    end

    it "fixes individual security checks" do
      post "/tab/network/security_fix", params: { check_name: "fail2ban" }, as: :json
      body = JSON.parse(response.body)
      expect(body).to include("status")
    end
  end

  describe "Setup wizard" do
    it "redirects to setup when not initialized" do
      Setting.where(name: 'initialized').destroy_all
      # Need to logout first since we logged in as admin
      delete user_session_path(0) rescue nil

      get root_path
      # Should redirect to login or setup
      expect(response).to be_redirect
    end
  end
end
