require 'rails_helper'

RSpec.describe "ShareController extended", type: :request do
  before { login_as_admin }

  let!(:share) { create(:share, visible: true, rdonly: false, everyone: true, disk_pool_copies: 0) }
  let!(:user) { create(:user) }

  describe "PUT update_name" do
    it "updates the share name" do
      put update_name_share_path(share), params: { value: "NewName" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.name).to eq("NewName")
    end

    it "returns error for invalid name" do
      put update_name_share_path(share), params: { value: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PUT update_path" do
    it "updates the share path" do
      put update_path_share_path(share), params: { value: "/new/path" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.path).to eq("/new/path")
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

  describe "PUT update_tags" do
    it "updates tags" do
      put update_tags_share_path(share), params: { value: "movies, media" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.tags).to eq("movies, media")
    end
  end

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
      # Enabling guest forces read-only
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

    it "adds user access" do
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

  describe "PUT toggle_tag" do
    it "adds a tag" do
      share.update!(tags: "")
      put toggle_tag_share_path(share), params: { tag: "movies" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.tags).to include("movies")
    end

    it "removes a tag" do
      share.update!(tags: "movies, music")
      put toggle_tag_share_path(share), params: { tag: "movies" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(share.reload.tags).not_to include("movies")
    end
  end

  describe "POST create" do
    it "creates a share with valid params" do
      post shares_path, params: { name: "ValidShare", path: "/var/hda/files/valid", visible: "1", readonly: "1" }
      expect(response).to have_http_status(:ok)
      s = Share.find_by(name: "ValidShare")
      expect(s).to be_present
      expect(s.visible).to eq(true)
      expect(s.rdonly).to eq(true)
    end

    it "rejects share with no name" do
      post shares_path, params: { name: "", path: "/some/path" }
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects share with no path" do
      post shares_path, params: { name: "GoodName", path: "" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects share name over 32 chars" do
      post shares_path, params: { name: "A" * 33, path: "/some/path" }
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects path over 64 chars" do
      post shares_path, params: { name: "GoodName", path: "/" + "a" * 64 }
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects invalid share name (special chars)" do
      post shares_path, params: { name: "bad!name", path: "/some/path" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET new_share_name_check" do
    it "reports available name" do
      get new_share_name_check_shares_path, params: { name: "UniqueTestShare" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports taken name" do
      get new_share_name_check_shares_path, params: { name: share.name }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports blank name" do
      get new_share_name_check_shares_path, params: { name: "" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports invalid name" do
      get new_share_name_check_shares_path, params: { name: "!" * 33 }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET new_share_path_check" do
    it "reports available path" do
      get new_share_path_check_shares_path, params: { path: "/unique/test/path" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports taken path" do
      get new_share_path_check_shares_path, params: { path: share.path }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports blank path" do
      get new_share_path_check_shares_path, params: { path: "" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "reports invalid path with backslash" do
      get new_share_path_check_shares_path, params: { path: "C:\\bad\\path" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PUT toggle_disk_pool_enabled" do
    before { allow(Greyhole).to receive(:enabled?).and_return(true) }
    before { allow(Greyhole).to receive(:configure!) }

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
    before { allow(Greyhole).to receive(:enabled?).and_return(true) }
    before { allow(Greyhole).to receive(:configure!) }

    it "sets copies count" do
      put update_disk_pool_copies_share_path(share), params: { value: "5" }, as: :json
      expect(share.reload.disk_pool_copies).to eq(5)
    end
  end

  describe "PUT toggle_setting (share settings)" do
    it "toggles a share setting" do
      setting = Setting.create!(name: "win98", value: "0", kind: Setting::SHARES)
      Setting.create!(name: "pdc", value: "0", kind: Setting::SHARES) unless Setting.shares.find_by(name: "pdc")
      Setting.create!(name: "debug", value: "0", kind: Setting::SHARES) unless Setting.shares.find_by(name: "debug")
      Setting.create!(name: "workgroup", value: "WORKGROUP", kind: Setting::SHARES) unless Setting.shares.find_by(name: "workgroup")
      allow(Share).to receive(:push_shares)
      put toggle_setting_shares_path, params: { id: setting.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(setting.reload.value).to eq("1")
    end
  end

  describe "PUT update_workgroup_name" do
    it "updates workgroup name" do
      setting = Setting.find_or_create_by!(name: "workgroup", kind: Setting::SHARES) { |s| s.value = "WORKGROUP" }
      allow(Share).to receive(:push_shares)
      put update_workgroup_name_share_path(share), params: { id: setting.id, value: "MYGROUP" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE delete" do
    it "deletes the share" do
      expect {
        delete share_path(share), as: :json
      }.to change(Share, :count).by(-1)
    end
  end
end
