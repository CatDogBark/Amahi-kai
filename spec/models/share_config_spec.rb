require 'rails_helper'

RSpec.describe Share, 'config generation', type: :model do
  before do
    create(:admin)
    Setting.set('net', '192.168.1')
    Setting.set('self-address', '100')
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
      expect(conf).to include("dfree command = /opt/amahi-kai/libexec/amahi-dfree")
    end

    it "adds no blank line for an emptied Advanced box, and takes the browser's CRLF lines" do
      emptied = create(:share, name: "Emptied", disk_pool_copies: 2, extras: "\r\n")
      expect(emptied.share_conf.lines.map(&:strip)[0...-1]).not_to include("") # the last separates sections

      typed = create(:share, name: "Typed", disk_pool_copies: 0, extras: "veto files = /*.mp3/\r\nhide dot files = yes")
      expect(typed.share_conf).to include("\tveto files = /*.mp3/\n\thide dot files = yes\n")
      expect(typed.share_conf).not_to include("\r")
    end

    it 'does not include greyhole when disk_pool_copies is 0' do
      share = create(:share, name: "NoPool", disk_pool_copies: 0, extras: "")
      conf = share.share_conf
      expect(conf).not_to include("greyhole")
    end

    it "keeps a share's deleted files in its recycle bin, the Trash, unless it's pooled (Greyhole's trash)" do
      share = create(:share, name: "Plain", disk_pool_copies: 0, extras: "recycle:repository = elsewhere\nhide dot files = yes")
      conf = share.share_conf
      expect(conf.scan(/vfs objects = .*/)).to eq(['vfs objects = recycle'])
      Share::RECYCLE_PARAMS.each { |param| expect(conf).to include("\t#{param}\n") }
      expect(conf).not_to include('elsewhere')
      expect(conf).to include("\thide dot files = yes\n")
      share.update_column(:disk_pool_copies, 1)
      expect(share.reload.share_conf).not_to include('recycle')
    end

    it 'strips existing greyhole entries from extras before re-adding' do
      share = create(:share, name: "RePool", disk_pool_copies: 1,
        extras: "\tdfree command = /opt/amahi-kai/libexec/amahi-dfree\n\tvfs objects = greyhole\n")
      conf = share.share_conf
      # Should have exactly one of each, not duplicates
      expect(conf.scan("vfs objects = greyhole").length).to eq(1)
      expect(conf.scan("dfree command").length).to eq(1)
    end

    it "puts every feature's vfs modules on one line, Greyhole's first on a pooled share, without recycle" do
      share = create(:share, name: "Mixed", disk_pool_copies: 0,
                             extras: "vfs objects = recycle\nrecycle:repository = .recycle\nvfs objects = fruit streams_xattr\nfruit:time machine = yes")
      conf = share.share_conf
      expect(conf.scan(/vfs objects = .*/)).to eq(['vfs objects = recycle fruit streams_xattr'])
      expect(conf).to include("\trecycle:repository = .recycle\n", "\tfruit:time machine = yes\n")

      share.update_column(:disk_pool_copies, 2)
      conf = share.reload.share_conf
      expect(conf.scan(/vfs objects = .*/)).to eq(['vfs objects = greyhole fruit streams_xattr'])
      expect(conf.scan('dfree command').length).to eq(1)

      share.update_columns(extras: "hide dot files = yes")
      expect(share.reload.share_conf.scan(/vfs objects = .*/)).to eq(['vfs objects = greyhole'])
      share.update_columns(disk_pool_copies: 0)
      expect(share.reload.share_conf.scan(/vfs objects = .*/)).to eq(['vfs objects = recycle'])
    end

    it 'gives Samba a config it accepts, with every feature on a pooled share', if: File.executable?('/usr/bin/testparm') do
      share = create(:share, name: "AllOn", path: '/tmp', disk_pool_copies: 2,
                             extras: "vfs objects = recycle\nrecycle:repository = .recycle\nvfs objects = fruit streams_xattr\n" \
                                     "fruit:metadata = stream\nhide dot files = yes\nvfs objects = fruit streams_xattr\nfruit:time machine = yes")
      Tempfile.create('smb.conf') do |file|
        file.write("[global]\n\tworkgroup = TEST\n\n#{share.share_conf}")
        file.flush
        out, err, status = Open3.capture3('/usr/bin/testparm', '-s', '--section-name=AllOn', '--parameter-name=vfs objects', file.path)
        expect(status).to be_success, err
        expect(out.strip).to eq('greyhole fruit streams_xattr')
      end
    end

    it "gives Samba a recycle bin it accepts on a share that isn't pooled, which the root helper allows" do
      share = create(:share, name: "Plain", path: Share.default_full_path('plain'), disk_pool_copies: 0, extras: "")
      Privileged.operations # loads libexec/amahi-helper
      expect(AmahiHelper.samba_problems(share.share_conf)).to eq([])
      next unless File.executable?('/usr/bin/testparm')

      Tempfile.create('smb.conf') do |file|
        file.write("[global]\n\tworkgroup = TEST\n\n#{share.share_conf}")
        file.flush
        out, err, status = Open3.capture3('/usr/bin/testparm', '-s', '--section-name=Plain', '--parameter-name=recycle:repository', file.path)
        expect(status).to be_success, err
        expect(out.strip).to eq('.recycle')
      end
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
      Setting.set('workgroup', 'MYGROUP')
      Setting.set("debug", "0", Setting::SHARES)
      Setting.set("win98", "0", Setting::SHARES)
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

    it "never writes a server name that isn't one hostname-shaped word (the wizard checks it; this is the last line)" do
      Setting.set('server-name', "mynas\n\thosts allow = 0.0.0.0/0")
      conf = Share.header_workgroup("example.local")
      expect(conf).to include("netbios name = amahi-kai")
      expect(conf).not_to include('0.0.0.0/0')
      expect(Share.samba_lmhosts("example.local")).not_to include('0.0.0.0/0')
      expect(Share.samba_lmhosts("example.local")).to include('amahi-kai.example.local')
    end

    it 'sets debug log level when debug enabled' do
      Setting.set("debug", "1", Setting::SHARES)
      result = Share.header_workgroup("example.local")
      expect(result).to include("log level = 5")
    end

    describe 'network access' do
      before do
        Setting.set('net', '192.168.1')
        allow(Share).to receive(:primary_interface).and_return('ens18')
        allow(Share).to receive(:lan_ipv6_prefixes).and_return(['2603:800c:400:84f3::/64'])
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/sys/class/net/tailscale0').and_return(false)
      end

      it 'allows the NAS itself, the LAN and Tailscale, and nothing else' do
        result = Share.header_workgroup("example.local")
        expect(result).to include("hosts allow = 127.0.0.1 ::1 192.168.1. fe80::/10 2603:800c:400:84f3::/64 100.64.0.0/10 fd7a:115c:a1e0::/48")
        expect(result).not_to match(/hosts allow.*172\./)
      end

      it 'binds Samba to loopback and the LAN interface' do
        result = Share.header_workgroup("example.local")
        expect(result).to include("interfaces = lo ens18", "bind interfaces only = yes")
      end

      it 'adds the Tailscale interface when it exists' do
        allow(File).to receive(:exist?).with('/sys/class/net/tailscale0').and_return(true)
        expect(Share.header_workgroup("example.local")).to include("interfaces = lo ens18 tailscale0")
      end

      it 'leaves the allow list off when the LAN prefix is unknown, rather than lock the LAN out' do
        Setting.set('net', '')
        expect(Share.header_workgroup("example.local")).not_to include("hosts allow")
      end
    end

    it 'keeps the settings Greyhole needs when Greyhole is installed' do
      allow(Greyhole).to receive(:installed?).and_return(true)
      result = Share.header_workgroup("example.local")
      expect(result).to include("wide links = yes", "follow symlinks = yes", "allow insecure wide links = yes")
    end

    it 'leaves them out without Greyhole' do
      allow(Greyhole).to receive(:installed?).and_return(false)
      expect(Share.header_workgroup("example.local")).not_to include("wide links")
    end

    it 'gives the guest account no home share' do
      expect(Share.header_workgroup("example.local")).to include("invalid users = nobody")
    end
  end

  describe '.header' do
    it 'turns printer sharing off and adds no printer shares' do
      header = Share.header("example.local")
      expect(header).to include("load printers = no", "disable spoolss = yes")
      expect(header).not_to include("[printers]", "[print$]", "cups")
    end
  end

end
