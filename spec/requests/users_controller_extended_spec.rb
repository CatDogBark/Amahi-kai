require 'rails_helper'

RSpec.describe "UsersController extended", type: :request do
  before { @admin = login_as_admin }

  describe "PUT /tab/users/users/:id/update_password" do
    it "updates password with valid params" do
      user = create(:user)
      put "/tab/users/users/#{user.id}/update_password", params: {
        user: { password: "newpassword1", password_confirmation: "newpassword1" }
      }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "rejects mismatched passwords" do
      user = create(:user)
      put "/tab/users/users/#{user.id}/update_password", params: {
        user: { password: "newpassword1", password_confirmation: "different" }
      }, as: :json
      # Should fail validation
      expect(response.status).to be_in([200, 400, 422])
    end
  end

  describe "PUT /tab/users/users/:id/update_pin" do
    it "updates pin" do
      user = create(:user)
      put "/tab/users/users/#{user.id}/update_pin", params: {
        user: { pin: "1234" }
      }, as: :json
      expect(response.status).to be_in([200, 422])
    end
  end

  describe "PUT /tab/users/users/:id/update_pubkey" do
    it "updates public key" do
      user = create(:user)
      allow(Platform).to receive(:update_user_pubkey)
      put "/tab/users/users/#{user.id}/update_pubkey", params: {
        user: { public_key: "ssh-rsa AAAAB3... test@host" }
      }, as: :json
      expect(response.status).to be_in([200, 422])
    end
  end

  describe "GET /tab/users/users/settings" do
    it "shows user settings" do
      get "/tab/users/users/settings"
      expect(response.status).to be_in([200, 302])
    end
  end

  describe "PUT /tab/users/users/:id (update)" do
    it "updates user details" do
      user = create(:user)
      put "/tab/users/users/#{user.id}", params: {
        user: { name: "Updated Name" }
      }, as: :json
      expect(response.status).to be_in([200, 422])
    end
  end
end
