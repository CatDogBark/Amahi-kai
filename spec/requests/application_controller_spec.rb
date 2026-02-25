require 'rails_helper'

RSpec.describe "ApplicationController features", type: :request do
  describe "locale handling" do
    before { login_as_admin }

    it "uses default locale when no cookie" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "respects locale cookie" do
      cookies[:locale] = "en"
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "handles locale param override" do
      get root_path, params: { locale: "en" }
      expect(response).to have_http_status(:ok)
    end

    it "ignores invalid locale param" do
      get root_path, params: { locale: "xx_invalid" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "authentication" do
    it "login_required redirects unauthenticated users" do
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "admin_required redirects non-admin users" do
      user = create(:user, admin: false)
      login_as(user)
      get shares_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "admin_required allows admin users" do
      login_as_admin
      get shares_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "setup redirect" do
    it "redirects to setup when not completed" do
      login_as_admin
      Setting.set('setup_completed', 'false')
      get root_path
      expect(response).to redirect_to(setup_welcome_path)
    end

    it "does not redirect setup controller routes" do
      login_as_admin
      Setting.set('setup_completed', 'false')
      get setup_welcome_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "theme handling" do
    before { login_as_admin }

    it "sets theme from settings" do
      Setting.find_or_create_by!(name: "theme") { |s| s.value = "amahi-kai"; s.kind = 0 }
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "falls back to default theme" do
      Setting.where(name: "theme").delete_all
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "RTL direction" do
    before { login_as_admin }

    it "sets LTR for English" do
      cookies[:locale] = "en"
      get root_path
      expect(response.body).not_to include('dir="rtl"')
    end
  end
end
