require 'spec_helper'

describe "Front page", type: :request do
  describe "unauthenticated access" do
    it "redirects to login page by default" do
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "shows dashboard if guest dashboard is enabled" do
      Setting.set('guest-dashboard', '1')
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end

    it "redirects to login if guest dashboard is disabled" do
      Setting.set('guest-dashboard', '0')
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "authenticated access" do
    before { login_as_admin }

    it "shows dashboard after login" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end

    it "shows logout link" do
      get root_path
      expect(response.body).to include("Logout")
    end
  end

  describe "login flow" do
    it "logs in with valid credentials and shows dashboard" do
      ensure_setup_completed!
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      expect(response).to redirect_to(root_url)
      follow_redirect!
      expect(response.body).to include("Dashboard")
    end

    it "rejects bad username" do
      user = create(:user)
      post user_sessions_path, params: { username: "bogus", password: "secretpassword" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Incorrect username or password")
    end

    it "rejects bad password" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "bogus" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Incorrect username or password")
    end

    it "logs out and redirects to root" do
      user = create(:user)
      login_as(user)
      delete user_session_path(0)
      expect(response).to redirect_to(root_path)
    end
  end
end
