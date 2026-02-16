require 'spec_helper'

describe "Shares Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get shares_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get shares_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /shares" do
      it "shows the shares page" do
        get shares_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /shares" do
      it "creates a new share" do
        expect {
          post shares_path, params: { share: { name: "TestShare", visible: true, rdonly: false } }, as: :json
        }.to change(Share, :count).by(1)
      end

      it "rejects share with blank name" do
        expect {
          post shares_path, params: { share: { name: "", visible: true, rdonly: false } }, as: :json
        }.not_to change(Share, :count)
      end
    end

    describe "DELETE /shares/:id" do
      it "deletes a share" do
        share = create(:share)
        expect {
          delete share_path(share), as: :json
        }.to change(Share, :count).by(-1)
      end
    end
  end
end
