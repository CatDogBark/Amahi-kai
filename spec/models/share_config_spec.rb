require 'rails_helper'

RSpec.describe Share, 'config generation', type: :model do
  before do
    create(:admin)
    create(:setting, name: "net", value: "192.168.1")
    create(:setting, name: "self-address", value: "100")
    allow(Share).to receive(:push_shares)
  end

  describe '#to_param' do
    it 'returns the share name' do
      share = create(:share, name: "Movies")
      expect(share.to_param).to eq("Movies")
    end
  end

  describe '#share_conf' do
    it 'includes valid users and write list when not everyone' do
      share = create(:share, name: "Private", everyone: false)
      user = create(:user, login: "testuser")
      share.users_with_share_access << user
      share.users_with_write_access << user

      conf = share.share_conf
      expect(conf).to include("valid users = testuser")
      expect(conf).to include("write list = testuser")
    end

    it 'uses nobody when no users have access' do
      share = create(:share, name: "Empty", everyone: false)
      conf = share.share_conf
      expect(conf).to include("valid users = nobody")
      expect(conf).to include("write list = nobody")
    end

    it 'includes nobody in valid users when guest_access enabled' do
      share = create(:share, name: "GuestShare", everyone: false, guest_access: true)
      user = create(:user, login: "someuser")
      share.users_with_share_access << user

      conf = share.share_conf
      expect(conf).to include("nobody")
    end

    it 'includes greyhole vfs objects when disk_pool_copies > 0' do
      share = create(:share, name: "Pooled", disk_pool_copies: 2, extras: "")
      conf = share.share_conf
      expect(conf).to include("vfs objects = greyhole")
      expect(conf).to include("dfree command = /usr/bin/greyhole-dfree")
    end

    it 'does not include greyhole when disk_pool_copies is 0' do
      share = create(:share, name: "NoPool", disk_pool_copies: 0, extras: "")
      conf = share.share_conf
      expect(conf).not_to include("greyhole")
    end

    it 'strips existing greyhole entries from extras before re-adding' do
      share = create(:share, name: "RePool", disk_pool_copies: 1,
        extras: "\tdfree command = /usr/bin/greyhole-dfree\n\tvfs objects = greyhole\n")
      conf = share.share_conf
      # Should have exactly one of each, not duplicates
      expect(conf.scan("vfs objects = greyhole").length).to eq(1)
      expect(conf.scan("dfree command").length).to eq(1)
    end

    it 'includes create/directory masks' do
      share = create(:share)
      conf = share.share_conf
      expect(conf).to include("create mask = 0775")
      expect(conf).to include("directory mask = 0775")
      expect(conf).to include("force create mode = 0664")
      expect(conf).to include("force directory mode = 0775")
    end
  end

  describe '#tag_list' do
    it 'returns empty array for nil tags' do
      share = create(:share, tags: nil)
      expect(share.tag_list).to eq([])
    end

    it 'returns empty array for blank tags' do
      share = create(:share, tags: "")
      expect(share.tag_list).to eq([])
    end

    it 'splits comma-separated tags' do
      share = create(:share, tags: "music, video, photos")
      expect(share.tag_list).to eq(["music", "video", "photos"])
    end
  end

  describe '.default_samba_domain' do
    it 'strips common TLDs' do
      expect(Share.default_samba_domain("myserver.com")).to eq("myserver")
      expect(Share.default_samba_domain("myserver.local")).to eq("myserver")
    end

    it 'replaces dots with underscores' do
      expect(Share.default_samba_domain("my.server.com")).to eq("my_server")
    end

    it 'truncates to last 15 chars' do
      long = "a" * 20 + ".com"
      result = Share.default_samba_domain(long)
      expect(result.length).to be <= 15
    end

    it 'returns full domain if stripping leaves empty string' do
      # edge case: domain IS just a TLD
      expect(Share.default_samba_domain("com")).to eq("com")
    end
  end

  describe '.samba_lmhosts' do
    it 'generates lmhosts with correct IP and hostname' do
      Setting.set('server-name', 'mynas')
      result = Share.samba_lmhosts("example.local")
      expect(result).to include("192.168.1.100 mynas")
      expect(result).to include("192.168.1.100 files")
      expect(result).to include("192.168.1.100 mynas.example.local")
      expect(result).to include("127.0.0.1 localhost")
    end
  end

  describe '.header_workgroup' do
    before do
      Setting.find_or_create_by(Setting::GENERAL, "workgroup", "MYGROUP")
      Setting.find_or_create_by(Setting::SHARES, "pdc", "0")
      Setting.find_or_create_by(Setting::SHARES, "debug", "0")
      Setting.find_or_create_by(Setting::SHARES, "win98", "0")
    end

    it 'includes workgroup name' do
      result = Share.header_workgroup("example.local")
      expect(result).to include("workgroup = MYGROUP")
    end

    it 'includes server string' do
      result = Share.header_workgroup("example.local")
      expect(result).to include("server string = example.local")
    end

    it 'includes netbios name from settings' do
      Setting.set('server-name', 'mynas')
      result = Share.header_workgroup("example.local")
      expect(result).to include("netbios name = mynas")
    end

    it 'sets debug log level when debug enabled' do
      Setting.set_kind(Setting::SHARES, "debug", "1")
      result = Share.header_workgroup("example.local")
      expect(result).to include("log level = 5")
    end
  end

  describe '.header_pdc' do
    before do
      Setting.find_or_create_by(Setting::SHARES, "workgroup", "MYGROUP")
      Setting.find_or_create_by(Setting::SHARES, "debug", "0")
    end

    it 'includes domain logons' do
      result = Share.header_pdc("example.local")
      expect(result).to include("domain logons = yes")
    end

    it 'includes domain master' do
      result = Share.header_pdc("example.local")
      expect(result).to include("domain master = yes")
    end

    it 'includes admin users' do
      admin = create(:admin, login: "myadmin")
      result = Share.header_pdc("example.local")
      expect(result).to include("myadmin")
    end

    it 'includes netlogon and profiles sections' do
      result = Share.header_pdc("example.local")
      expect(result).to include("[netlogon]")
      expect(result).to include("[profiles]")
    end
  end

  describe '.header_common' do
    it 'includes print$ and printers sections' do
      result = Share.header_common
      expect(result).to include("[print$]")
      expect(result).to include("[printers]")
    end
  end

  describe '#update_tags!' do
    it 'toggles a tag off when already present' do
      share = create(:share, tags: "music, video")
      share.update_tags!(tags: "music")
      expect(share.reload.tag_list).not_to include("music")
      expect(share.reload.tag_list).to include("video")
    end

    it 'adds a new tag' do
      share = create(:share, tags: "music")
      share.update_tags!(tags: "photos")
      expect(share.reload.tag_list).to include("music", "photos")
    end

    it 'updates path when path param present' do
      share = create(:share, path: "/old/path")
      share.update_tags!(path: "/new/path", tags: "ignored")
      expect(share.reload.path).to eq("/new/path")
    end

    it 'rejects blank tag names' do
      share = create(:share, tags: "music")
      result = share.update_tags!(tags: "  ")
      expect(result).to be false
    end

    it 'strips HTML tags from input' do
      share = create(:share, tags: "music")
      share.update_tags!(tags: "<script>alert</script>video")
      tags = share.reload.tag_list
      expect(tags.join).not_to include("<script>")
    end
  end
end
