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

      it "keeps the password message outside the part that closes on success" do
        get '/users'
        page = Nokogiri::HTML(response.body)
        message = page.at('form.update-password [data-user-target="passwordMessage"]')
        expect(message).to be_present
        expect(message.ancestors('.password-edit')).to be_empty
      end
    end

    describe "POST /users as JSON" do
      let(:user_params) do
        { user: { login: 'newbie', name: 'New Person', password: 'longpassword', password_confirmation: 'longpassword',
                  role: 'user' } }
      end

      it "answers with the updated list (it used to be a 500: no JSON template)" do
        post '/users', params: user_params, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
        expect(response.parsed_body['content']).to include('newbie')
      end

      it "answers with the form and its errors when the user isn't valid" do
        post '/users', params: { user: user_params[:user].merge(password_confirmation: 'different') }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['errors']).to be true
        expect(response.parsed_body['content']).to include('<form')
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

    # Web users get no shell, so the app no longer installs SSH keys for them.
    describe "PUT /users/:id/update_pubkey" do
      it "no longer exists" do
        user = create(:user)
        put "/users/#{user.id}/update_pubkey", params: { "public_key_#{user.id}" => "ssh-ed25519 AAAA" }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
