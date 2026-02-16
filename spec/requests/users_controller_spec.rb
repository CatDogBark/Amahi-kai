require 'spec_helper'

describe "Users Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get '/tab/users'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get '/tab/users'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { @admin = login_as_admin }

    describe "GET /tab/users" do
      it "shows the users page" do
        get '/tab/users'
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /tab/users/users" do
      it "creates a new user" do
        expect {
          post '/tab/users/users', params: {
            user: { login: "newuser", name: "New User", password: "secretpassword", password_confirmation: "secretpassword" }
          }, as: :json
        }.to change(User, :count).by(1)
      end

      it "rejects user with short password" do
        expect {
          post '/tab/users/users', params: {
            user: { login: "newuser", name: "New User", password: "short", password_confirmation: "short" }
          }, as: :json
        }.not_to change(User, :count)
      end
    end

    describe "DELETE /tab/users/users/:id" do
      it "deletes a user" do
        user = create(:user)
        expect {
          delete "/tab/users/users/#{user.id}", as: :json
        }.to change(User, :count).by(-1)
      end

      it "does not allow deleting yourself" do
        expect {
          delete "/tab/users/users/#{@admin.id}", as: :json
        }.not_to change(User, :count)
      end
    end

    describe "PUT /tab/users/users/:id/toggle_admin" do
      it "promotes a regular user to admin" do
        user = create(:user)
        put "/tab/users/users/#{user.id}/toggle_admin", as: :json
        expect(user.reload.admin).to be true
      end

      it "does not allow revoking own admin" do
        put "/tab/users/users/#{@admin.id}/toggle_admin", as: :json
        expect(@admin.reload.admin).to be true
      end
    end

    describe "PUT /tab/users/users/:id/update_name" do
      it "updates a user's name" do
        user = create(:user)
        put "/tab/users/users/#{user.id}/update_name", params: { user: { name: "Updated Name" } }, as: :json
        expect(user.reload.name).to eq("Updated Name")
      end
    end
  end
end
