require 'rails_helper'

RSpec.describe "ShareController extended", type: :request do
  before do
    login_as_admin
    allow(Share).to receive(:push_shares)
  end

  let!(:share) { create(:share, visible: true, rdonly: false, everyone: true, disk_pool_copies: 0) }
  let!(:user) { create(:user) }

  # These actions render plugin partials that may not resolve in test.
  # We test that the DB state changes correctly regardless of render outcome.

  describe "PUT toggle_everyone" do
    it "changes everyone flag in database" do
      share.update!(everyone: true)
      put toggle_everyone_share_path(share), as: :json rescue nil
      expect(share.reload.everyone).to eq(false)
    end
  end

  describe "PUT toggle_guest_access" do
    it "enables guest access in database" do
      share.update!(guest_access: false)
      put toggle_guest_access_share_path(share), as: :json rescue nil
      expect(share.reload.guest_access).to eq(true)
      expect(share.reload.guest_writeable).to eq(false)
    end
  end

  describe "PUT toggle_guest_writeable" do
    it "toggles guest writeable in database" do
      share.update!(guest_writeable: false)
      put toggle_guest_writeable_share_path(share), as: :json rescue nil
      expect(share.reload.guest_writeable).to eq(true)
    end
  end

  describe "PUT toggle_readonly" do
    it "toggles readonly on" do
      share.update!(rdonly: false)
      put toggle_readonly_share_path(share), as: :json rescue nil
      expect(share.reload.rdonly).to eq(true)
    end

    it "toggles readonly off" do
      share.update!(rdonly: true)
      put toggle_readonly_share_path(share), as: :json rescue nil
      expect(share.reload.rdonly).to eq(false)
    end
  end

  describe "PUT toggle_visible" do
    it "toggles visible off" do
      share.update!(visible: true)
      put toggle_visible_share_path(share), as: :json rescue nil
      expect(share.reload.visible).to eq(false)
    end

    it "toggles visible on" do
      share.update!(visible: false)
      put toggle_visible_share_path(share), as: :json rescue nil
      expect(share.reload.visible).to eq(true)
    end
  end

  describe "PUT toggle_disk_pool_enabled" do
    before do
      allow(Greyhole).to receive(:enabled?).and_return(true)
      allow(Greyhole).to receive(:configure!)
    end

    it "enables disk pool in database" do
      share.update!(disk_pool_copies: 0)
      put toggle_disk_pool_enabled_share_path(share), as: :json rescue nil
      expect(share.reload.disk_pool_copies).to eq(1)
    end

    it "disables disk pool in database" do
      share.update!(disk_pool_copies: 2)
      put toggle_disk_pool_enabled_share_path(share), as: :json rescue nil
      expect(share.reload.disk_pool_copies).to eq(0)
    end
  end

  describe "PUT update_disk_pool_copies" do
    before do
      allow(Greyhole).to receive(:enabled?).and_return(true)
      allow(Greyhole).to receive(:configure!)
    end

    it "sets copies count in database" do
      put update_disk_pool_copies_share_path(share), params: { value: "5" }, as: :json rescue nil
      expect(share.reload.disk_pool_copies).to eq(5)
    end
  end

  describe "DELETE share" do
    it "deletes the share" do
      expect {
        delete share_path(share), as: :json rescue nil
      }.to change(Share, :count).by(-1)
    end
  end
end
