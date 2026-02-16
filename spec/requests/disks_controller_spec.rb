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
  end
end
