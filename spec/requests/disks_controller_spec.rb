require 'spec_helper'

describe "Disks Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/tab/disks"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/tab/disks"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /tab/disks" do
      it "shows the disks page" do
        get "/tab/disks/"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/disks/mounts" do
      it "shows the mounts page" do
        get "/tab/disks/mounts"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/disks/storage_pool" do
      it "shows the storage pool page" do
        get "/tab/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end

      it "displays greyhole status" do
        allow(Greyhole).to receive(:status).and_return({ installed: true, running: true })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/tab/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end

      it "displays when greyhole is not installed" do
        allow(Greyhole).to receive(:status).and_return({ installed: false, running: false })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/tab/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /tab/disks/toggle_greyhole" do
      it "stops greyhole when running" do
        allow(Greyhole).to receive(:running?).and_return(true)
        allow(Greyhole).to receive(:stop!)
        post "/tab/disks/toggle_greyhole"
        expect(response).to redirect_to("/tab/disks/storage_pool")
        expect(Greyhole).to have_received(:stop!)
      end

      it "starts greyhole when stopped" do
        allow(Greyhole).to receive(:running?).and_return(false)
        allow(Greyhole).to receive(:start!)
        post "/tab/disks/toggle_greyhole"
        expect(response).to redirect_to("/tab/disks/storage_pool")
        expect(Greyhole).to have_received(:start!)
      end
    end

    describe "POST /tab/disks/install_greyhole" do
      it "installs greyhole and redirects with notice" do
        allow(Greyhole).to receive(:install!)
        post "/tab/disks/install_greyhole"
        expect(response).to redirect_to("/tab/disks/storage_pool")
        expect(flash[:notice]).to include("successfully")
      end

      it "handles GreyholeError during install" do
        allow(Greyhole).to receive(:install!).and_raise(Greyhole::GreyholeError, "apt failed")
        post "/tab/disks/install_greyhole"
        expect(response).to redirect_to("/tab/disks/storage_pool")
        expect(flash[:error]).to include("apt failed")
      end

      it "handles generic errors during install" do
        allow(Greyhole).to receive(:install!).and_raise(RuntimeError, "unexpected")
        post "/tab/disks/install_greyhole"
        expect(response).to redirect_to("/tab/disks/storage_pool")
        expect(flash[:error]).to include("unexpected")
      end
    end

    describe "GET /tab/disks/install_greyhole_stream" do
      it "returns SSE content type" do
        get "/tab/disks/install_greyhole_stream"
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end
  end
end
