require 'rails_helper'

RSpec.describe "ShareController extended", type: :request do
  before do
    login_as_admin
    allow_any_instance_of(Command).to receive(:execute)
    allow_any_instance_of(Command).to receive(:submit).and_return(nil)
    allow(Share).to receive(:push_shares)
  end

  let!(:share) { create(:share, visible: true, rdonly: false, everyone: true, disk_pool_copies: 0) }
  let!(:user) { create(:user) }

  describe "PUT toggle_everyone" do
    it "toggles from everyone to per-user access" do
      share.update!(everyone: true)
      put toggle_everyone_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.everyone).to eq(false)
    end

    it "toggles from per-user to everyone" do
      share.update!(everyone: false)
      put toggle_everyone_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.everyone).to eq(true)
    end
  end

  describe "PUT toggle_guest_access" do
    it "enables guest access" do
      share.update!(guest_access: false)
      put toggle_guest_access_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.guest_access).to eq(true)
      expect(share.reload.guest_writeable).to eq(false)
    end

    it "disables guest access" do
      share.update!(guest_access: true)
      put toggle_guest_access_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.guest_access).to eq(false)
    end
  end

  describe "PUT toggle_guest_writeable" do
    it "toggles guest writeable" do
      share.update!(guest_writeable: false)
      put toggle_guest_writeable_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.guest_writeable).to eq(true)
    end
  end

  describe "PUT toggle_access" do
    before { share.update!(everyone: false) }

    it "toggles user access" do
      put toggle_access_share_path(share), params: { user: user.id }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "does nothing when everyone mode" do
      share.update!(everyone: true)
      put toggle_access_share_path(share), params: { user: user.id }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT toggle_write" do
    before { share.update!(everyone: false) }

    it "toggles write access for user" do
      put toggle_write_share_path(share), params: { user: user.id }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "does nothing when everyone mode" do
      share.update!(everyone: true)
      put toggle_write_share_path(share), params: { user: user.id }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT toggle_readonly" do
    it "toggles readonly on" do
      share.update!(rdonly: false)
      put toggle_readonly_share_path(share), as: :json
      expect(share.reload.rdonly).to eq(true)
    end

    it "toggles readonly off" do
      share.update!(rdonly: true)
      put toggle_readonly_share_path(share), as: :json
      expect(share.reload.rdonly).to eq(false)
    end
  end

  describe "PUT toggle_visible" do
    it "toggles visible off" do
      share.update!(visible: true)
      put toggle_visible_share_path(share), as: :json
      expect(share.reload.visible).to eq(false)
    end

    it "toggles visible on" do
      share.update!(visible: false)
      put toggle_visible_share_path(share), as: :json
      expect(share.reload.visible).to eq(true)
    end
  end

  describe "PUT update_path" do
    it "updates the share path" do
      put update_path_share_path(share), params: { value: "/new/test/path" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.path).to eq("/new/test/path")
    end
  end

  describe "PUT update_tags" do
    it "updates tags" do
      put update_tags_share_path(share), params: { value: "movies, media" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT update_extras" do
    it "updates extras" do
      put update_extras_share_path(share), params: { value: "force user = nobody" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.extras).to eq("force user = nobody")
    end

    it "handles blank extras" do
      put update_extras_share_path(share), params: { value: "" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT clear_permissions" do
    it "clears share permissions" do
      put clear_permissions_share_path(share), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT toggle_disk_pool_enabled" do
    before do
      allow(Greyhole).to receive(:enabled?).and_return(true)
      allow(Greyhole).to receive(:configure!)
    end

    it "enables disk pool" do
      share.update!(disk_pool_copies: 0)
      put toggle_disk_pool_enabled_share_path(share), as: :json
      expect(share.reload.disk_pool_copies).to eq(1)
    end

    it "disables disk pool" do
      share.update!(disk_pool_copies: 2)
      put toggle_disk_pool_enabled_share_path(share), as: :json
      expect(share.reload.disk_pool_copies).to eq(0)
    end
  end

  describe "PUT update_disk_pool_copies" do
    before do
      allow(Greyhole).to receive(:enabled?).and_return(true)
      allow(Greyhole).to receive(:configure!)
    end

    it "sets copies count" do
      put update_disk_pool_copies_share_path(share), params: { value: "5" }, as: :json
      expect(share.reload.disk_pool_copies).to eq(5)
    end
  end

  describe "PUT update_workgroup" do
    it "responds to workgroup update" do
      setting = Setting.find_or_create_by!(name: "workgroup", kind: Setting::SHARES) { |s| s.value = "WORKGROUP" }
      put update_workgroup_share_path(share), params: { id: setting.id, value: "MYGROUP" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE share" do
    it "deletes the share" do
      expect {
        delete share_path(share), as: :json
      }.to change(Share, :count).by(-1)
    end
  end

  describe "GET disk_pooling" do
    it "shows disk pooling page" do
      get disk_pooling_shares_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET settings" do
    it "shows share settings page" do
      Setting.find_or_create_by!(name: "win98", kind: Setting::SHARES) { |s| s.value = "0" }
      Setting.find_or_create_by!(name: "pdc", kind: Setting::SHARES) { |s| s.value = "0" }
      Setting.find_or_create_by!(name: "debug", kind: Setting::SHARES) { |s| s.value = "0" }
      Setting.find_or_create_by!(name: "workgroup", kind: Setting::SHARES) { |s| s.value = "WORKGROUP" }
      get settings_shares_path
      expect(response).to have_http_status(:ok)
    end
  end
end
