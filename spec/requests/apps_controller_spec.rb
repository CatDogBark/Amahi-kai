require 'spec_helper'

describe "Apps Controller", type: :request, integration: true do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /apps" do
      it "shows the docker apps index" do
        allow(DockerService).to receive(:installed?).and_return(false)
        allow(DockerService).to receive(:running?).and_return(false)
        allow(AppCatalog).to receive(:all).and_return([])
        get "/apps"
        expect(response).to have_http_status(:ok)
      end
    end

    # --- Docker Engine Installation ---

    describe "GET /apps/install_docker_stream" do
      it "returns SSE content type" do
        get "/apps/install_docker_stream"
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "POST /apps/start_docker" do
      it "starts docker and redirects to docker apps" do
        allow(DockerService).to receive(:start!)
        post "/apps/start_docker"
        expect(response).to redirect_to("/apps/docker_apps")
      end
    end

    # --- Docker Apps ---

    describe "GET /apps/docker_apps" do
      it "renders when docker is not installed" do
        allow(DockerService).to receive(:installed?).and_return(false)
        allow(DockerService).to receive(:running?).and_return(false)
        allow(AppCatalog).to receive(:all).and_return([])
        get "/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end

      it "renders when docker is installed and running" do
        allow(DockerService).to receive(:installed?).and_return(true)
        allow(DockerService).to receive(:running?).and_return(true)
        allow(AppCatalog).to receive(:all).and_return([
          { identifier: "nextcloud", name: "Nextcloud", description: "Cloud storage", image: "nextcloud:latest", category: "productivity", ports: ["8080:80"], volumes: [], environment: {} }
        ])
        get "/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end

      it "filters by category" do
        allow(DockerService).to receive(:installed?).and_return(true)
        allow(DockerService).to receive(:running?).and_return(true)
        allow(AppCatalog).to receive(:all).and_return([
          { identifier: "nextcloud", name: "Nextcloud", description: "Cloud storage", image: "nextcloud:latest", category: "productivity", ports: [], volumes: [], environment: {} },
          { identifier: "plex", name: "Plex", description: "Media server", image: "plex:latest", category: "media", ports: [], volumes: [], environment: {} }
        ])
        get "/apps/docker_apps", params: { category: "media" }
        expect(response).to have_http_status(:ok)
      end

      it "handles errors gracefully" do
        allow(DockerService).to receive(:installed?).and_raise(RuntimeError, "docker not found")
        get "/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /apps/docker/status/:id" do
      it "returns status for an existing docker app" do
        DockerApp.create!(identifier: "test-app", name: "Test", image: "test:latest", status: "running", host_port: 8080)
        get "/apps/docker/status/test-app", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("running")
        expect(body["host_port"]).to eq(8080)
      end

      it "returns available status for non-existent docker app" do
        get "/apps/docker/status/nonexistent", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("available")
      end
    end
  end
end
