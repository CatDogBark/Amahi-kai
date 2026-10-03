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
      ensure_setup_completed!
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

  # The legacy first-run flow created an admin without logging in and never
  # checked whether the system was already initialized. It must stay removed.
  describe "legacy first-run endpoints" do
    it "has no route for the legacy endpoints" do
      [["/user_sessions/initialize_system", :post],
       ["/user_sessions/initialize_system", :get],
       ["/start", :get]].each do |path, verb|
        expect { Rails.application.routes.recognize_path(path, method: verb) }
          .to raise_error(ActionController::RoutingError), "#{verb.upcase} #{path} is still routed"
      end
    end

    it "returns 404 and creates no user for POST /user_sessions/initialize_system" do
      allow(User).to receive(:system_find_name_by_username).and_return(["nobody", 65534, "nobody"])
      post "/user_sessions/initialize_system",
        params: { username: "nobody", password: "longenough1", password_confirmation: "longenough1" }
      expect(response).to have_http_status(:not_found)
      expect(User.where(login: "nobody")).to be_empty
    end

    it "still serves the login page" do
      Setting.where(name: 'initialized').destroy_all
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end
end
