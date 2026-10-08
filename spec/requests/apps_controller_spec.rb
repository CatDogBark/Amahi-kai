require 'spec_helper'

describe "Apps Controller", type: :request do

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
        get "/apps/install_docker_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end

      it "installs Docker through DockerService in production, streaming its progress" do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(DockerService).to receive(:install!) { |&block| block.call('Installing Docker Engine...') }
        get "/apps/install_docker_stream", headers: same_origin
        expect(response.body).to include('Installing Docker Engine...').and include('Docker installed successfully')
      end

      it "streams the reason when the install fails" do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(DockerService).to receive(:install!).and_raise(DockerService::DockerError, 'curl exited 6')
        get "/apps/install_docker_stream", headers: same_origin
        expect(response.body).to include('curl exited 6').and include('Docker installation failed')
      end
    end

    describe "POST /apps/start_docker" do
      it "starts docker and redirects to docker apps" do
        allow(DockerService).to receive(:start!)
        post "/apps/start_docker"
        expect(response).to redirect_to("/apps")
      end
    end

    # The Apps pages themselves: spec/requests/docker_apps_spec.rb.
  end
end
