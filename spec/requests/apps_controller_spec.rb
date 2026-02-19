require 'spec_helper'

describe "Apps Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/tab/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/tab/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /tab/apps" do
      it "shows the apps index" do
        get "/tab/apps"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/apps/installed" do
      it "shows installed apps" do
        get "/tab/apps/installed"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /tab/apps/toggle_in_dashboard/:id" do
      let(:installed_app) do
        App.connection.execute("INSERT INTO apps (name, identifier, installed, show_in_dashboard) VALUES ('TestApp', 'test-app', 1, 0)")
        App.find_by(identifier: "test-app")
      end

      it "toggles dashboard visibility for an installed app" do
        app = installed_app
        put "/tab/apps/toggle_in_dashboard/#{app.identifier}", as: :json
        expect(response).to have_http_status(:ok)
        expect(app.reload.show_in_dashboard).to be true
      end

      it "toggles back to hidden" do
        app = installed_app
        app.update_column(:show_in_dashboard, true)
        put "/tab/apps/toggle_in_dashboard/#{app.identifier}", as: :json
        expect(response).to have_http_status(:ok)
        expect(app.reload.show_in_dashboard).to be false
      end

      it "does not toggle for uninstalled app" do
        App.connection.execute("INSERT INTO apps (name, identifier, installed, show_in_dashboard) VALUES ('TestApp2', 'test-app-2', 0, 0)")
        put "/tab/apps/toggle_in_dashboard/test-app-2", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end

    # --- Docker Engine Installation ---

    describe "GET /tab/apps/install_docker_stream" do
      it "returns SSE content type" do
        get "/tab/apps/install_docker_stream"
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "POST /tab/apps/start_docker" do
      it "starts docker and redirects to docker apps" do
        allow(DockerService).to receive(:start!)
        post "/tab/apps/start_docker"
        expect(response).to redirect_to("/tab/apps/docker_apps")
      end
    end

    # --- Docker Apps ---

    describe "GET /tab/apps/docker_apps" do
      it "renders when docker is not installed" do
        allow(DockerService).to receive(:installed?).and_return(false)
        allow(DockerService).to receive(:running?).and_return(false)
        allow(AppCatalog).to receive(:all).and_return([])
        get "/tab/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end

      it "renders when docker is installed and running" do
        allow(DockerService).to receive(:installed?).and_return(true)
        allow(DockerService).to receive(:running?).and_return(true)
        allow(AppCatalog).to receive(:all).and_return([
          { identifier: "nextcloud", name: "Nextcloud", description: "Cloud storage", image: "nextcloud:latest", category: "productivity", ports: ["8080:80"], volumes: [], environment: {} }
        ])
        get "/tab/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end

      it "filters by category" do
        allow(DockerService).to receive(:installed?).and_return(true)
        allow(DockerService).to receive(:running?).and_return(true)
        allow(AppCatalog).to receive(:all).and_return([
          { identifier: "nextcloud", name: "Nextcloud", description: "Cloud storage", image: "nextcloud:latest", category: "productivity", ports: [], volumes: [], environment: {} },
          { identifier: "plex", name: "Plex", description: "Media server", image: "plex:latest", category: "media", ports: [], volumes: [], environment: {} }
        ])
        get "/tab/apps/docker_apps", params: { category: "media" }
        expect(response).to have_http_status(:ok)
      end

      it "handles errors gracefully" do
        allow(DockerService).to receive(:installed?).and_raise(RuntimeError, "docker not found")
        get "/tab/apps/docker_apps"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/apps/docker/status/:id" do
      it "returns status for an existing docker app" do
        DockerApp.create!(identifier: "test-app", name: "Test", image: "test:latest", status: "running", host_port: 8080)
        get "/tab/apps/docker/status/test-app", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("running")
        expect(body["host_port"]).to eq(8080)
      end

      it "returns available status for non-existent docker app" do
        get "/tab/apps/docker/status/nonexistent", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("available")
      end
    end
  end
end
