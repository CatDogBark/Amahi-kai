require 'rails_helper'

RSpec.describe "FrontController extended", type: :request do
  describe "POST toggle_advanced" do
    context "as admin" do
      before { login_as_admin }

      it "toggles advanced setting and returns JSON" do
        Setting.where(name: "advanced").delete_all
        Setting.create!(name: "advanced", value: "0", kind: Setting::GENERAL)
        post "/toggle_advanced", as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(Setting.find_by(name: "advanced").value).to eq("1")
      end

      it "toggles back to 0" do
        Setting.where(name: "advanced").delete_all
        Setting.create!(name: "advanced", value: "1", kind: Setting::GENERAL)
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
end
