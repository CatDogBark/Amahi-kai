require 'spec_helper'

describe "Settings Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/settings"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/settings"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /settings" do
      it "shows the settings page" do
        get "/settings"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "change_language" do
      it "sets locale cookie for valid locale" do
        post "/settings/change_language", params: { locale: "en" }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end

      it "handles invalid locale gracefully" do
        post "/settings/change_language", params: { locale: "xx_invalid" }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "toggle_setting" do
      it "toggles a setting value" do
        setting = Setting.create!(name: "advanced", value: "0", kind: 0)
        post "/settings/toggle_setting", params: { id: setting.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(setting.reload.value).to eq("1")
      end

      it "toggles back" do
        setting = Setting.create!(name: "advanced", value: "1", kind: 0)
        post "/settings/toggle_setting", params: { id: setting.id }, as: :json
        expect(setting.reload.value).to eq("0")
      end
    end

    describe "servers" do
      before do
        Setting.create!(name: "advanced", value: "1", kind: 0)
      end

      it "shows the servers page" do
        get "/settings/servers"
        expect(response).to have_http_status(:ok)
      end

      it "redirects if not advanced" do
        Setting.find_by(name: "advanced").update!(value: "0")
        get "/settings/servers"
        expect(response).to redirect_to("/settings")
      end
    end

    describe "reboot" do
      it "issues reboot command" do
        allow(Shell).to receive(:run).and_return(true)
        post "/settings/reboot"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "poweroff" do
      it "issues poweroff command" do
        allow(Shell).to receive(:run).and_return(true)
        post "/settings/poweroff"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "themes" do
      it "shows themes page" do
        get "/settings/themes"
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
