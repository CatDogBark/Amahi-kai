require 'rails_helper'

RSpec.describe "SharesController", type: :request do
  describe "unauthenticated" do
    it "redirects to login" do
      get shares_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "authenticated admin" do
    before do
      login_as_admin
      # Stub all system-level calls that share callbacks trigger
      allow(Share).to receive(:push_shares)
      allow_any_instance_of(Share).to receive(:push_shares)
      allow_any_instance_of(Command).to receive(:execute)
      allow(Platform).to receive(:reload)
    end

    describe "POST /shares (create)" do
      it "creates a new share" do
        expect {
          post shares_path, params: { share: { name: "TestShare" } }
        }.to change(Share, :count).by(1)
      end

      it "rejects blank share name" do
        expect {
          post shares_path, params: { share: { name: "" } }
        }.not_to change(Share, :count)
      end
    end

    describe "PUT /shares/:id/toggle_visible" do
      let!(:share) { create(:share, visible: true) }

      it "toggles visibility" do
        put toggle_visible_share_path(share), as: :json
        expect(share.reload.visible).to eq(false)
      end
    end

    describe "PUT /shares/:id/toggle_readonly" do
      let!(:share) { create(:share, rdonly: false) }

      it "toggles readonly" do
        put toggle_readonly_share_path(share), as: :json
        expect(share.reload.rdonly).to eq(true)
      end
    end

    describe "PUT /shares/:id/update_tags" do
      let!(:share) { create(:share) }

      it "updates tags" do
        put update_tags_share_path(share), params: { name: "movies, media" }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "DELETE /shares/:id" do
      let!(:share) { create(:share) }

      it "destroys the share" do
        expect {
          delete share_path(share), as: :json
        }.to change(Share, :count).by(-1)
      end
    end

    describe "disk pool operations" do
      let!(:share) { create(:share, disk_pool_copies: 0) }

      it "toggles disk pool enabled" do
        allow(Greyhole).to receive(:configure!)
        put toggle_disk_pool_enabled_share_path(share), as: :json
        expect(share.reload.disk_pool_copies).to be >= 1
      end

      it "updates disk pool copies" do
        allow(Greyhole).to receive(:configure!)
        put update_disk_pool_copies_share_path(share), params: { value: "3" }, as: :json
        expect(share.reload.disk_pool_copies).to eq(3)
      end
    end
  end
end
