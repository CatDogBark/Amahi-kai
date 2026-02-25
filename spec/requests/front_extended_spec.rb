require 'rails_helper'

RSpec.describe "FrontController extended", type: :request do
  describe "POST toggle_advanced" do
    context "as admin" do
      before { login_as_admin }

      it "toggles advanced from 0 to 1" do
        Setting.find_or_create_by!(name: "advanced") { |s| s.value = "0"; s.kind = 0 }
        post "/toggle_advanced", as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(body["advanced"]).to eq(true)
        expect(Setting.find_by(name: "advanced").value).to eq("1")
      end

      it "toggles advanced from 1 to 0" do
        Setting.find_or_create_by!(name: "advanced") { |s| s.value = "1"; s.kind = 0 }
        Setting.find_by(name: "advanced").update!(value: "1")
        post "/toggle_advanced", as: :json
        expect(response).to have_http_status(:ok)
        expect(Setting.find_by(name: "advanced").value).to eq("0")
      end
    end

    context "as non-admin" do
      before do
        user = create(:user, admin: false)
        login_as(user)
      end

      it "returns forbidden" do
        post "/toggle_advanced", as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET / (dashboard)" do
    before { login_as_admin }

    it "includes dashboard stats" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end

    it "handles locale cookie" do
      cookies[:locale] = "en"
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end
end
