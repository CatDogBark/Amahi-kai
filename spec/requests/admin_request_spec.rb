require 'spec_helper'

describe "Admin access", type: :request do
  describe "admin user" do
    it "sees Setup link in navigation after login" do
      login_as_admin
      get root_path
      expect(response.body).to include("Setup")
      expect(response.body).to include("Logout")
    end
  end

  describe "non-admin user" do
    it "does not see Setup link in navigation" do
      login_as_user
      get root_path
      expect(response.body).not_to include(">Setup<")
    end

    it "cannot access admin-only pages" do
      login_as_user
      get "/users"
      # Should redirect or show access denied
      expect(response.body).to include("admin privileges").or(
        satisfy { response.redirect? }
      )
    end
  end
end
