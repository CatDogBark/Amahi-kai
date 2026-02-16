require 'spec_helper'

describe "User Sessions", type: :request do

  describe "GET /login" do
    it "shows the login page" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end

  describe "POST /user_sessions (login)" do
    it "logs in with valid credentials" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      expect(response).to redirect_to(root_url)
      follow_redirect!
      expect(response.body).to include("Dashboard")
    end

    it "rejects invalid credentials" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "wrongpassword" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end

    it "rejects nonexistent users" do
      post user_sessions_path, params: { username: "nobody", password: "password" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end

  describe "DELETE /user_sessions (logout)" do
    it "logs out and redirects to root" do
      user = create(:user)
      login_as(user)
      delete user_session_path(0)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /start" do
    it "redirects to login if system is initialized" do
      Setting.set('initialized', '1')
      get start_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects to login when initialized (seeds set initialized=1)" do
      get start_path
      expect(response).to redirect_to(login_path)
    end
  end
end
