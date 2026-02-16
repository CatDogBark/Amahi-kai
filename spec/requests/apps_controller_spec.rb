require 'spec_helper'

describe "Apps Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/tab/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/tab/apps"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /tab/apps" do
      it "shows the apps index" do
        get "/tab/apps"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /tab/apps/installed" do
      it "shows installed apps" do
        get "/tab/apps/installed"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /tab/apps/toggle_in_dashboard/:id" do
      # App.new calls AmahiApi::App.find, so we insert directly via SQL
      let(:installed_app) do
        App.connection.execute("INSERT INTO apps (name, identifier, installed, show_in_dashboard) VALUES ('TestApp', 'test-app', 1, 0)")
        App.find_by(identifier: "test-app")
      end

      it "toggles dashboard visibility for an installed app" do
        app = installed_app
        put "/tab/apps/toggle_in_dashboard/#{app.identifier}", as: :json
        expect(response).to have_http_status(:ok)
        expect(app.reload.show_in_dashboard).to be true
      end

      it "does not toggle for uninstalled app" do
        App.connection.execute("INSERT INTO apps (name, identifier, installed, show_in_dashboard) VALUES ('TestApp2', 'test-app-2', 0, 0)")
        put "/tab/apps/toggle_in_dashboard/test-app-2", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("not_acceptable")
      end
    end
  end
end
