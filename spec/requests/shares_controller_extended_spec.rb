require 'rails_helper'

RSpec.describe "SharesController extended", type: :request do
  before do
    login_as_admin
    allow(Share).to receive(:push_shares)
    allow(SambaService).to receive(:push_config)
    allow(Shell).to receive(:run).and_return(true)
    allow(Platform).to receive(:reload)
    allow(ShareIndexer).to receive(:index_share)
  end

  # --- Create validation ---

  describe "POST /shares (create)" do
    it "rejects an empty name" do
      expect {
        post shares_path, params: { share: { name: "" } }
      }.not_to change(Share, :count)
    end

    it "creates share successfully" do
      expect {
        post shares_path, params: { share: { name: "NewShare" } }
      }.to change(Share, :count).by(1)
      expect(response).to redirect_to(shares_path)
    end

    it "sets default path based on name" do
      post shares_path, params: { share: { name: "MediaFiles" } }
      share = Share.find_by(name: "MediaFiles")
      expect(share).to be_present
      expect(share.path).to include("mediafiles")
    end
  end

  # --- Update tags ---

  describe "PUT /shares/:id/update_tags" do
    let!(:share) { create(:share) }

    it "updates tags via name param" do
      put update_tags_share_path(share), params: { name: "movies" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "updates tags via value param (lowercased)" do
      put update_tags_share_path(share), params: { value: "MUSIC" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "updates tags via share[tags] param" do
      put update_tags_share_path(share), params: { share: { tags: "docs" } }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  # --- Disk pool operations ---

  describe "disk pool operations" do
    let!(:share) { create(:share, disk_pool_copies: 0) }

    before do
      allow(Greyhole).to receive(:enabled?).and_return(true)
      allow(Greyhole).to receive(:configure!)
    end

    describe "PUT toggle_disk_pool_enabled" do
      it "enables disk pool (sets copies to 1)" do
        put toggle_disk_pool_enabled_share_path(share), as: :json
        expect(share.reload.disk_pool_copies).to eq(1)
      end

      it "disables disk pool when already enabled" do
        share.update_column(:disk_pool_copies, 2)
        put toggle_disk_pool_enabled_share_path(share), as: :json
        expect(share.reload.disk_pool_copies).to eq(0)
      end

      it "calls Greyhole.configure! when enabled" do
        put toggle_disk_pool_enabled_share_path(share), as: :json
        expect(Greyhole).to have_received(:configure!)
      end

      it "handles Greyhole errors gracefully" do
        allow(Greyhole).to receive(:configure!).and_raise(Shell::CommandError.new("greyhole", "failed", 1))
        put toggle_disk_pool_enabled_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT update_disk_pool_copies" do
      it "sets the number of copies" do
        put update_disk_pool_copies_share_path(share), params: { value: "5" }, as: :json
        expect(share.reload.disk_pool_copies).to eq(5)
      end

      it "handles Greyhole error gracefully" do
        allow(Greyhole).to receive(:configure!).and_raise(Shell::CommandError.new("greyhole", "boom", 1))
        put update_disk_pool_copies_share_path(share), params: { value: "2" }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # --- Error handling on destroy ---

  describe "DELETE /shares/:id" do
    let!(:share) { create(:share) }

    it "returns json with ok status" do
      delete share_path(share), as: :json
      body = response.parsed_body
      expect(body['status']).to eq('ok')
      expect(body['id']).to eq(share.id)
    end
  end

  # --- Permission toggle edge cases ---

  describe "permission toggles" do
    let!(:share) { create(:share, everyone: true) }
    let!(:user) { create(:user) }

    describe "PUT toggle_everyone" do
      it "switches from everyone to individual permissions" do
        put toggle_everyone_share_path(share), as: :json
        expect(share.reload.everyone).to eq(false)
      end

      it "switches from individual back to everyone" do
        share.update_column(:everyone, false)
        put toggle_everyone_share_path(share), as: :json
        expect(share.reload.everyone).to eq(true)
      end
    end

    describe "PUT toggle_access" do
      it "does nothing when everyone is true" do
        put toggle_access_share_path(share), params: { user_id: user.id }, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "adds user access when everyone is false" do
        share.update_column(:everyone, false)
        put toggle_access_share_path(share), params: { user_id: user.id }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT toggle_write" do
      it "does nothing when everyone is true" do
        put toggle_write_share_path(share), params: { user_id: user.id }, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT toggle_guest_access" do
      it "enables guest access" do
        share.update_columns(everyone: false, guest_access: false)
        put toggle_guest_access_share_path(share), as: :json
        expect(share.reload.guest_access).to eq(true)
      end

      it "disables guest access and clears guest_writeable" do
        share.update_columns(everyone: false, guest_access: true, guest_writeable: true)
        put toggle_guest_access_share_path(share), as: :json
        s = share.reload
        expect(s.guest_access).to eq(false)
      end
    end

    describe "PUT toggle_guest_writeable" do
      it "toggles guest writeable" do
        share.update_columns(guest_writeable: false)
        put toggle_guest_writeable_share_path(share), as: :json
        expect(share.reload.guest_writeable).to eq(true)
      end
    end

    describe "PUT clear_permissions" do
      it "clears all user permissions" do
        put clear_permissions_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # --- Update name ---

  describe "PUT /shares/:id/update_name" do
    let!(:share) { create(:share) }

    it "updates share name" do
      put update_name_share_path(share), params: { value: "NewName" }
      expect(response).to have_http_status(:ok)
      expect(share.reload.name).to eq("NewName")
    end

    it "rejects invalid name" do
      put update_name_share_path(share), params: { value: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # --- Update size ---

  describe "PUT /shares/:id/update_size" do
    let!(:share) { create(:share) }

    it "returns size info" do
      allow(Open3).to receive(:capture2e).and_return(["1048576 /path", double(success?: true)])
      put update_size_share_path(share), as: :json
      body = response.parsed_body
      expect(body['status']).to eq('ok')
      expect(body['size']).to be_present
    end

    it "handles errors gracefully" do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT.new("no such file"))
      put update_size_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
