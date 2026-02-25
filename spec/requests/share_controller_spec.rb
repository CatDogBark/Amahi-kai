require 'rails_helper'

RSpec.describe "ShareController", type: :request do
  describe "unauthenticated" do
    it "redirects to login" do
      post "/shares/create", params: { share: { name: "test" } }
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "authenticated admin" do
    before { login_as_admin }

    describe "POST /shares/create" do
      it "creates a new share" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)

        expect {
          post "/shares/create", params: { share: { name: "TestShare" } }
        }.to change(Share, :count).by(1)
      end

      it "rejects blank share name" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)

        expect {
          post "/shares/create", params: { share: { name: "" } }
        }.not_to change(Share, :count)
      end
    end

    describe "PUT /shares/:id/update_name" do
      let!(:share) { create(:share, name: "Original") }

      it "updates the share name" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)

        put "/shares/#{share.id}/update_name", params: { value: "NewName" }, as: :json
        expect(share.reload.name).to eq("NewName")
      end
    end

    describe "PUT /shares/:id/toggle_visible" do
      let!(:share) { create(:share) }

      it "toggles visibility" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)

        original = share.visible
        put "/shares/#{share.id}/toggle_visible", as: :json
        expect(share.reload.visible).not_to eq(original)
      end
    end

    describe "PUT /shares/:id/toggle_readonly" do
      let!(:share) { create(:share) }

      it "toggles readonly" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)

        original = share.rdonly
        put "/shares/#{share.id}/toggle_readonly", as: :json
        expect(share.reload.rdonly).not_to eq(original)
      end
    end

    describe "DELETE /shares/:id" do
      let!(:share) { create(:share) }

      it "destroys the share" do
        allow_any_instance_of(Share).to receive(:before_destroy_hook)
        allow_any_instance_of(Share).to receive(:after_destroy_hook)
        allow_any_instance_of(Share).to receive(:cleanup_share_index)

        expect {
          delete "/shares/#{share.id}", as: :json
        }.to change(Share, :count).by(-1)
      end
    end

    describe "disk pool operations" do
      let!(:share) { create(:share, disk_pool_copies: 0) }

      it "toggles disk pool enabled" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)
        allow(Greyhole).to receive(:configure!)

        put "/shares/#{share.id}/toggle_disk_pool_enabled", as: :json
        expect(share.reload.disk_pool_copies).to be >= 1
      end

      it "updates disk pool copies" do
        allow_any_instance_of(Share).to receive(:before_save_hook)
        allow_any_instance_of(Share).to receive(:after_save_hook)
        allow_any_instance_of(Share).to receive(:index_share_files)
        allow(Greyhole).to receive(:configure!)

        put "/shares/#{share.id}/update_disk_pool_copies", params: { value: "3" }, as: :json
        expect(share.reload.disk_pool_copies).to eq(3)
      end
    end
  end
end
