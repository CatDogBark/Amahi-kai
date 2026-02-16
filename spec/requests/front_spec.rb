require 'spec_helper'

describe "Front page", type: :request do

  describe "GET / (unauthenticated)" do
    it "redirects to login" do
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows dashboard when guest-dashboard is enabled" do
      # Seeds may create this setting first, so find-or-update
      s = Setting.where(name: "guest-dashboard").first_or_create
      s.update!(value: "1")
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end
  end

  describe "GET / (authenticated)" do
    it "shows the dashboard" do
      login_as_admin
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end
  end
end
