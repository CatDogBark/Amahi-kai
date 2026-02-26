require 'spec_helper'

describe "Docker Apps", type: :request, integration: true do
  include RequestHelpers

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "192.168.1")
    create(:setting, name: "self-address", value: "10")
    create(:setting, name: "domain", value: "amahi.net")
    create(:setting, name: "advanced", value: "1")
    create(:setting, name: "theme", value: "default")
    login_as_admin
    # Stub Docker commands — no Docker in CI/test
    allow_any_instance_of(DockerApp).to receive(:system).and_return(true)
    allow_any_instance_of(DockerApp).to receive(:`).and_return("")
  end

  describe "GET docker_apps" do
    it "shows the Docker apps page" do
      get "/apps/docker_apps"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Docker Apps")
    end

    it "filters by category" do
      get "/apps/docker_apps", params: { category: "media" }
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST docker/install/:id" do
    it "installs a Docker app from catalog" do
      post "/apps/docker/install/jellyfin"
      expect(response).to redirect_to("/apps/docker_apps")
      expect(DockerApp.find_by(identifier: "jellyfin")).to be_present
      expect(DockerApp.find_by(identifier: "jellyfin").status).to eq("running")
    end

    it "returns not found for unknown app" do
      post "/apps/docker/install/nonexistent"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST docker/stop/:id" do
    it "stops a running Docker app" do
      DockerApp.create!(identifier: "testapp", name: "Test", image: "test:latest", status: "running", container_name: "amahi-testapp")
      post "/apps/docker/stop/testapp"
      expect(response).to redirect_to("/apps/docker_apps")
      expect(DockerApp.find_by(identifier: "testapp").status).to eq("stopped")
    end
  end

  describe "POST docker/start/:id" do
    it "starts a stopped Docker app" do
      DockerApp.create!(identifier: "testapp", name: "Test", image: "test:latest", status: "stopped", container_name: "amahi-testapp")
      post "/apps/docker/start/testapp"
      expect(response).to redirect_to("/apps/docker_apps")
      expect(DockerApp.find_by(identifier: "testapp").status).to eq("running")
    end
  end

  describe "POST docker/uninstall/:id" do
    it "uninstalls a Docker app" do
      DockerApp.create!(identifier: "testapp", name: "Test", image: "test:latest", status: "stopped", container_name: "amahi-testapp")
      post "/apps/docker/uninstall/testapp"
      expect(response).to redirect_to("/apps/docker_apps")
      expect(DockerApp.find_by(identifier: "testapp").status).to eq("available")
    end
  end

  describe "GET docker/status/:id" do
    it "returns JSON status for installed app" do
      DockerApp.create!(identifier: "testapp", name: "Test", image: "test:latest", status: "running", container_name: "amahi-testapp", host_port: 8080)
      get "/apps/docker/status/testapp"
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("running")
      expect(json["host_port"]).to eq(8080)
    end

    it "returns available for unknown app" do
      get "/apps/docker/status/unknown"
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("available")
    end
  end
end
