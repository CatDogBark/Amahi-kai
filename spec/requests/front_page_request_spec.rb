require 'spec_helper'

describe "Front page", type: :request do
  describe "unauthenticated access" do
    it "redirects to login page by default" do
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "always redirects to login when not authenticated" do
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

  describe "app updates" do
    # An app installed from an older image than the catalog's: System Update brought a newer one.
    def installed(identifier, tag: 'old', **attrs)
      entry = AppCatalog.find(identifier)
      DockerApp.create!({ identifier: identifier, name: entry[:name], status: 'running',
                          image: "#{entry[:image].split(/[:@]/).first}:#{tag}@sha256:#{'a' * 64}" }.merge(attrs))
    end

    it "tells admins which apps have an update, with their versions" do
      login_as_admin
      installed('gitea', tag: '1.0.0-rootless')
      installed('jellyfin', image: AppCatalog.find('jellyfin')[:image]) # up to date
      get root_path
      expect(response.body).to include(
        "App update: Gitea 1.0.0-rootless → #{AppCatalog.tag(AppCatalog.find('gitea')[:image])} — update on the Apps page"
      )
      expect(response.body).to include('href="/apps/installed_apps" class="update-notice"', '1 update')
      expect(response.body).not_to include('Jellyfin 10')
    end

    it "names three and counts the rest" do
      login_as_admin
      %w[bittube gitea jellyfin transmission].each { |id| installed(id) }
      get root_path
      expect(response.body).to include('App updates:', 'bitTube old →', ' · Gitea old →', ' · Jellyfin old →', 'and 1 more', '4 updates')
      expect(response.body).not_to include('Transmission old')
    end

    it "says nothing when every app is up to date, or to users who can't update them" do
      login_as_admin
      get root_path
      expect(response.body).not_to include('App update')

      installed('gitea')
      login_as(create(:user, admin: false))
      get root_path
      expect(response.body).not_to include('App update', '1 update')
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
