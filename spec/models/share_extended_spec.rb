require 'rails_helper'

RSpec.describe Share, type: :model do
  before do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    allow(Share).to receive(:push_shares)
  end

  describe "#share_conf" do
    it "generates samba share configuration" do
      share = create(:share, name: "Movies", path: "/var/hda/files/movies", rdonly: false, visible: true, everyone: true)
      conf = share.share_conf
      expect(conf).to include("[Movies]")
      expect(conf).to include("path = /var/hda/files/movies")
    end

    it "sets read only when rdonly is true" do
      share = create(:share, rdonly: true)
      conf = share.share_conf
      expect(conf).to include("read only = Yes")
    end

    it "sets not browseable when not visible" do
      share = create(:share, visible: false)
      conf = share.share_conf
      expect(conf).to include("browseable = No")
    end

    it "includes extras when present" do
      share = create(:share, extras: "force user = nobody")
      conf = share.share_conf
      expect(conf).to include("force user = nobody")
    end

    it "includes guest ok when guest_access is true" do
      share = create(:share, guest_access: true)
      conf = share.share_conf
      expect(conf).to include("guest ok = Yes")
    end
  end

  describe "#toggle_everyone!" do
    it "toggles from everyone to per-user" do
      share = create(:share, everyone: true)
      share.toggle_everyone!
      expect(share.reload.everyone).to eq(false)
    end

    it "toggles from per-user to everyone" do
      share = create(:share, everyone: false)
      share.toggle_everyone!
      expect(share.reload.everyone).to eq(true)
    end
  end

  describe "#toggle_access!" do
    let(:share) { create(:share, everyone: false) }
    let(:user) { create(:user) }

    it "adds user access" do
      share.toggle_access!(user.id)
      expect(share.users_with_share_access).to include(user)
    end

    it "removes user access when already present" do
      share.users_with_share_access << user
      share.toggle_access!(user.id)
      expect(share.reload.users_with_share_access).not_to include(user)
    end
  end

  describe "#toggle_write!" do
    let(:share) { create(:share, everyone: false) }
    let(:user) { create(:user) }

    it "adds write access" do
      share.toggle_write!(user.id)
      expect(share.users_with_write_access).to include(user)
    end

    it "removes write access when already present" do
      share.users_with_write_access << user
      share.toggle_write!(user.id)
      expect(share.reload.users_with_write_access).not_to include(user)
    end
  end

  describe "#toggle_guest_access!" do
    it "enables guest access and forces non-writeable" do
      share = create(:share, guest_access: false)
      share.toggle_guest_access!
      expect(share.guest_access).to eq(true)
      expect(share.guest_writeable).to eq(false)
    end

    it "disables guest access" do
      share = create(:share, guest_access: true)
      share.toggle_guest_access!
      expect(share.guest_access).to eq(false)
    end
  end

  describe "#toggle_guest_writeable!" do
    it "toggles guest writeable" do
      share = create(:share, guest_writeable: false)
      share.toggle_guest_writeable!
      expect(share.guest_writeable).to eq(true)
    end
  end

  describe "#update_tags!" do
    it "adds a tag via toggle" do
      share = create(:share, tags: "music")
      share.update_tags!(tags: "video")
      expect(share.reload.tags).to include("video")
    end
  end

  describe "#update_extras!" do
    it "updates extras" do
      share = create(:share, extras: "")
      share.update_extras!(extras: "force user = nobody")
      expect(share.reload.extras).to eq("force user = nobody")
    end
  end

  describe "#clear_permissions" do
    it "executes chmod command without error" do
      share = create(:share)
      expect { share.clear_permissions }.not_to raise_error
    end
  end

  describe "#make_guest_writeable" do
    it "executes chmod command" do
      share = create(:share)
      expect { share.make_guest_writeable }.not_to raise_error
    end
  end

  describe "#make_guest_non_writeable" do
    it "executes chmod command" do
      share = create(:share)
      expect { share.make_guest_non_writeable }.not_to raise_error
    end
  end

  describe "#toggle_disk_pool!" do
    it "toggles from 0 to 1" do
      share = create(:share, disk_pool_copies: 0)
      share.toggle_disk_pool!
      expect(share.reload.disk_pool_copies).to eq(1)
    end

    it "toggles from positive to 0" do
      share = create(:share, disk_pool_copies: 2)
      share.toggle_disk_pool!
      expect(share.reload.disk_pool_copies).to eq(0)
    end
  end

  describe ".samba_conf" do
    it "generates full samba config" do
      create(:share, name: "TestConf")
      Setting.find_or_create_by!(name: "workgroup", kind: Setting::SHARES) { |s| s.value = "WORKGROUP" }
      Setting.find_or_create_by!(name: "pdc", kind: Setting::SHARES) { |s| s.value = "0" }
      conf = Share.samba_conf("WORKGROUP")
      expect(conf).to be_a(String)
      expect(conf).to include("[TestConf]")
    end
  end

  describe ".header" do
    it "returns header config" do
      Setting.find_or_create_by!(name: "pdc", kind: Setting::SHARES) { |s| s.value = "0" }
      header = Share.header("WORKGROUP")
      expect(header).to be_a(String)
      expect(header).to include("WORKGROUP")
    end
  end

  describe "#cleanup_share_index" do
    it "removes indexed files for the share" do
      share = create(:share)
      share.share_files.create!(name: "test.txt", path: "/test", size: 100)
      share.cleanup_share_index
      expect(share.share_files.count).to eq(0)
    end
  end

  describe "#index_share_files" do
    it "indexes files from an existing path" do
      dir = "/tmp/test_share_#{SecureRandom.hex(4)}"
      FileUtils.mkdir_p(dir)
      FileUtils.touch(File.join(dir, "testfile.txt"))
      share = create(:share, path: dir)
      share.index_share_files
      expect(share.share_files.count).to be >= 1
      FileUtils.rm_rf(dir)
    end

    it "handles non-existent paths gracefully" do
      share = create(:share, path: "/nonexistent/path/#{SecureRandom.hex(8)}")
      expect { share.index_share_files }.not_to raise_error
    end
  end
end
