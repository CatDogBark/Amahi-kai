require 'spec_helper'

describe "Users Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get '/users'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get '/users'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { @admin = login_as_admin }

    describe "GET /users" do
      it "shows the users page" do
        get '/users'
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /users" do
      it "creates a new user" do
        expect {
          post '/users', params: {
            user: { login: "newuser", name: "New User", password: "secretpassword", password_confirmation: "secretpassword" }
          }, as: :json
        }.to change(User, :count).by(1)
      end

      it "rejects user with short password" do
        expect {
          post '/users', params: {
            user: { login: "newuser", name: "New User", password: "short", password_confirmation: "short" }
          }, as: :json
        }.not_to change(User, :count)
      end
    end

    describe "DELETE /users/:id" do
      it "deletes a user" do
        user = create(:user)
        expect {
          delete "/users/#{user.id}", as: :json
        }.to change(User, :count).by(-1)
      end

      it "does not allow deleting yourself" do
        expect {
          delete "/users/#{@admin.id}", as: :json
        }.not_to change(User, :count)
      end
    end

    describe "PUT /users/:id/toggle_admin" do
      it "promotes a regular user to admin" do
        user = create(:user)
        put "/users/#{user.id}/toggle_admin", as: :json
        expect(user.reload.admin).to be true
      end

      it "does not allow revoking own admin" do
        put "/users/#{@admin.id}/toggle_admin", as: :json
        expect(@admin.reload.admin).to be true
      end
    end

    describe "PUT /users/:id/update_name" do
      it "updates a user's name" do
        user = create(:user)
        put "/users/#{user.id}/update_name", params: { user: { name: "Updated Name" } }, as: :json
        expect(user.reload.name).to eq("Updated Name")
      end
    end

    describe "PUT /users/:id/update_password" do
      it "updates a user's password" do
        user = create(:user)
        old_digest = user.password_digest
        put "/users/#{user.id}/update_password", params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }, as: :json
        expect(user.reload.password_digest).not_to eq(old_digest)
      end

      it "rejects blank password" do
        user = create(:user)
        put "/users/#{user.id}/update_password", params: { user: { password: "", password_confirmation: "" } }, as: :json
        expect(response.parsed_body['status']).to eq('not_acceptable')
      end
    end

    describe "PUT /users/:id/update_pin" do
      it "rejects blank pin" do
        user = create(:user)
        put "/users/#{user.id}/update_pin", params: { user: { pin: "", pin_confirmation: "" } }, as: :json
        expect(response.parsed_body['status']).to eq('not_acceptable')
      end

      it "rejects mismatched pins" do
        user = create(:user)
        put "/users/#{user.id}/update_pin", params: { user: { pin: "12345", pin_confirmation: "54321" } }, as: :json
        expect(response.parsed_body['message']).to include('match').or include('do not match')
      end
    end

    describe "PUT /users/:id/update_pubkey" do
      it "updates a user's public key" do
        user = create(:user)
        put "/users/#{user.id}/update_pubkey", params: { "public_key_#{user.id}" => "ssh-rsa AAAA..." }, as: :json
        expect(user.reload.public_key).to eq("ssh-rsa AAAA...")
      end

      it "clears a blank public key" do
        user = create(:user, public_key: "ssh-rsa old")
        put "/users/#{user.id}/update_pubkey", params: { "public_key_#{user.id}" => "" }, as: :json
        expect(user.reload.public_key).to be_nil
      end
    end
  end
end
