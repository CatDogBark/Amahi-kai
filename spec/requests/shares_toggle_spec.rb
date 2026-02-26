require 'spec_helper'

describe "Shares Toggle Actions", type: :request do

  describe "admin" do
    before do
      login_as_admin
      # Stub system calls (Samba config push, shell commands)
      allow(Share).to receive(:push_shares)
      allow_any_instance_of(Command).to receive(:execute)
    end

    let(:share) { create(:share) }

    describe "PUT /shares/:id/toggle_visible" do
      it "toggles visibility" do
        original = share.visible
        put toggle_visible_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(share.reload.visible).to eq(!original)
      end
    end

    describe "PUT /shares/:id/toggle_readonly" do
      it "toggles readonly" do
        put toggle_readonly_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "PUT /shares/:id/toggle_everyone" do
      it "toggles everyone access" do
        put toggle_everyone_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/toggle_guest_access" do
      it "toggles guest access" do
        put toggle_guest_access_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/toggle_guest_writeable" do
      it "toggles guest writeable" do
        put toggle_guest_writeable_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/update_extras" do
      it "updates extras" do
        put update_extras_share_path(share), params: { share: { extras: "vfs objects = recycle" } }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/clear_permissions" do
      it "clears permissions" do
        put clear_permissions_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /shares/settings" do
      it "redirects if not advanced" do
        Setting.find_by(name: "advanced")&.update!(value: "0")
        get "/tab/shares/settings"
        expect(response).to have_http_status(:redirect)
      end

      it "shows settings page when advanced" do
        Setting.create!(name: "advanced", value: "1", kind: 0)
        get "/tab/shares/settings"
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
