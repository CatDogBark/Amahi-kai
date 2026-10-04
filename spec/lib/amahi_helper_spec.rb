require 'rails_helper'
require 'open3'

# libexec/amahi-helper, the root helper. Validation and planning are tested for every
# operation; file actions run on temporary folders. Nothing here needs root.
RSpec.describe 'AmahiHelper' do
  let(:helper_path) { Rails.root.join('libexec/amahi-helper').to_s }
  let(:helper) { AmahiHelper }
  let(:users_gid) { 100 }

  before(:all) { Privileged.operations } # loads the helper's source once

  def account(uid:, gid: 100, shell: '/usr/sbin/nologin')
    Etc::Passwd.new('x', 'x', uid, gid, '', '/home/x', shell)
  end

  def refusal(op, args)
    helper.validate(op, args)
    nil
  rescue AmahiHelper::Refused => e
    e.message
  end

  def steps(op, args)
    helper.plan(op, helper.validate(op, args))
  end

  # Run the helper as its own process, the way sudo runs it: no Bundler, no gems.
  def run_helper(*args, stdin: '')
    Bundler.with_unbundled_env do
      Open3.capture3(RbConfig.ruby, '--disable-gems', helper_path, *args, stdin_data: stdin)
    end
  end

  before do
    allow(helper).to receive(:group_id).and_call_original
    allow(helper).to receive(:group_id).with('users').and_return(users_gid)
    allow(helper).to receive(:passwd).and_return(nil)
  end

  describe 'the command line' do
    it 'loads without gems and passes its self-test' do
      out, _err, status = run_helper('--self-test')
      expect(status.exitstatus).to eq(0)
      expect(out).to eq("ok: #{AmahiHelper::OPERATIONS.size} operations\n")
    end

    it 'lists its operations' do
      out, _err, status = run_helper('--list')
      expect(status).to be_success
      expect(out.split).to eq(AmahiHelper::OPERATIONS.keys)
    end

    it 'prints the planned steps on --dry-run, with the password withheld' do
      out, _err, status = run_helper('--dry-run', 'samba.reload', stdin: '{}')
      expect(status).to be_success
      expect(JSON.parse(out)).to eq('ok' => true, 'steps' => [%w[/usr/bin/systemctl try-reload-or-restart smbd.service nmbd.service]])
    end

    it 'answers a refusal with exit status 1 and the reason' do
      out, _err, status = run_helper('--dry-run', 'users.create', stdin: '{"login":"root","name":"x"}')
      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(out)).to eq('ok' => false, 'error' => 'login root is reserved')
    end

    it 'refuses input that is not JSON' do
      out, _err, status = run_helper('--dry-run', 'samba.reload', stdin: 'nope')
      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(out)['error']).to eq('arguments are not valid JSON')
    end

    it 'shows usage for anything else' do
      _out, err, status = run_helper('--frobnicate')
      expect(status.exitstatus).to eq(2)
      expect(err).to include('usage')
    end
  end

  describe 'requests' do
    it 'refuses unknown operations, extra arguments and non-objects' do
      expect(refusal('users.chmod', {})).to eq('unknown operation "users.chmod"')
      expect(refusal('samba.reload', { 'now' => true })).to eq('unexpected argument now')
      expect(refusal('samba.reload', [])).to eq('arguments must be a JSON object')
    end

    it 'refuses to run unless root' do
      allow(helper).to receive(:check_environment!)
      allow(Process).to receive(:euid).and_return(1000)
      allow(helper).to receive(:log)
      expect { helper.execute('samba.reload', {}) }.to raise_error(AmahiHelper::Refused, 'the helper must run as root')
    end

    it 'refuses to run with RUBYOPT or RUBYLIB set' do
      allow(ENV).to receive(:key?).and_call_original
      allow(ENV).to receive(:key?).with('RUBYOPT').and_return(true)
      expect { helper.check_environment! }.to raise_error(AmahiHelper::Refused, /RUBYOPT/)
    end
  end

  describe 'users.create' do
    it 'plans useradd with the users group and no login shell' do
      expect(steps('users.create', { 'login' => 'ann', 'name' => 'Ann Smith' })).to eq([
        ['/usr/sbin/useradd', '-m', '-g', 'users', '-s', '/usr/sbin/nologin', '-c', 'Ann Smith', 'ann']
      ])
    end

    it 'accepts names in any language' do
      expect(refusal('users.create', { 'login' => 'jose', 'name' => 'José Ñandú' })).to be_nil
    end

    it 'refuses bad logins' do
      {
        'ab' => 'must be 3-32', 'Ann' => 'must be 3-32', '1ann' => 'must be 3-32', 'a-b-c' => 'must be 3-32',
        'a' * 33 => 'too long', 'root' => 'reserved', 'amahi' => 'reserved'
      }.each do |login, reason|
        expect(refusal('users.create', { 'login' => login, 'name' => 'X' })).to include(reason), login
      end
      expect(refusal('users.create', { 'login' => 7, 'name' => 'X' })).to eq('login must be a string')
      expect(refusal('users.create', { 'name' => 'X' })).to eq('login is missing')
    end

    it 'refuses a login that already exists' do
      allow(helper).to receive(:passwd).with('troy').and_return(account(uid: 1000, gid: 1000))
      expect(refusal('users.create', { 'login' => 'troy', 'name' => 'Troy' })).to eq('troy already exists on this system')
    end

    it 'refuses names the passwd file cannot hold' do
      expect(refusal('users.create', { 'login' => 'ann', 'name' => 'a:b' })).to include('colon')
      expect(refusal('users.create', { 'login' => 'ann', 'name' => "a\nb" })).to include('control character')
      expect(refusal('users.create', { 'login' => 'ann', 'name' => 'x' * 65 })).to include('too long')
      expect(refusal('users.create', { 'login' => 'ann', 'name' => "a\0b" })).to include('NUL')
    end
  end

  describe 'operations on existing accounts' do
    before do
      allow(helper).to receive(:passwd).with('ann').and_return(account(uid: 1001))
      allow(helper).to receive(:passwd).with('troy').and_return(account(uid: 1000, gid: 1000, shell: '/bin/bash'))
      allow(helper).to receive(:passwd).with('sysuser').and_return(account(uid: 120))
    end

    it 'sets the Samba password on stdin and never shows it' do
      planned = steps('users.set_password', { 'login' => 'ann', 'password' => 'hunter2hunter2' })
      expect(planned).to eq([['/usr/bin/pdbedit', '-d0', '-t', '-a', '-u', 'ann', { stdin: "hunter2hunter2\nhunter2hunter2\n" }]])
      expect(helper.describe(planned.first).to_s).not_to include('hunter2')
    end

    it 'refuses passwords pdbedit would split' do
      expect(refusal('users.set_password', { 'login' => 'ann', 'password' => "a\nb" })).to include('line break')
      expect(refusal('users.set_password', { 'login' => 'ann', 'password' => 'x' * 257 })).to include('too long')
    end

    it 'sets the full name' do
      expect(steps('users.set_name', { 'login' => 'ann', 'name' => 'Ann B' })).to eq([['/usr/sbin/usermod', '-c', 'Ann B', 'ann']])
    end

    it 'only changes accounts the app created' do
      %w[users.set_password users.set_name users.normalize].each do |op|
        args = { 'login' => 'troy', 'password' => 'longenough', 'name' => 'T' }.slice(*AmahiHelper::OPERATIONS[op][:params])
        expect(refusal(op, args)).to eq('troy is not an account Amahi created'), op
        expect(refusal(op, args.merge('login' => 'sysuser'))).to eq('sysuser is not an account Amahi created'), op
        expect(refusal(op, args.merge('login' => 'ghost'))).to eq('ghost has no Linux account'), op
      end
    end

    it 'normalizes an account to no shell and no extra groups, once' do
      allow(helper).to receive(:normal_account?).with('ann').and_return(false, true)
      expect(steps('users.normalize', { 'login' => 'ann' })).to eq([['/usr/sbin/usermod', '-s', '/usr/sbin/nologin', '-G', '', 'ann']])
      expect(steps('users.normalize', { 'login' => 'ann' })).to eq([])
    end

    it 'deletes the Samba user, then the Linux account and home of an app account' do
      expect(steps('users.delete', { 'login' => 'ann' })).to eq([
        ['/usr/bin/pdbedit', '-d0', '-x', '-u', 'ann', { allow_failure: true }],
        ['/usr/sbin/userdel', '-r', 'ann']
      ])
    end

    it 'deletes only the Samba user when there is no Linux account' do
      expect(steps('users.delete', { 'login' => 'ghost' })).to eq([['/usr/bin/pdbedit', '-d0', '-x', '-u', 'ghost', { allow_failure: true }]])
    end

    it "refuses to delete an account the app didn't create" do
      expect(refusal('users.delete', { 'login' => 'troy' })).to eq('troy is not an account Amahi created')
    end
  end

  describe 'samba.write_config' do
    let(:base) { "[global]\n\tworkgroup = WORKGROUP\n\tlog file = /var/log/samba/%m.log\n" }

    def share_with(line)
      "#{base}[Bad]\n\tpath = /var/lib/amahi-kai/files/bad\n\t#{line}\n"
    end

    before { allow(helper).to receive(:passwd).and_call_original }

    it 'plans an install checked by testparm' do
      planned = steps('samba.write_config', { 'content' => base })
      expect(planned).to eq([[:install, '/etc/samba/smb.conf', base, :smb_conf]])
    end

    it 'accepts the config the app generates' do
      create(:share, name: 'Movies', path: '/var/lib/amahi-kai/files/movies', disk_pool_copies: 2,
                     extras: "veto files = /.DS_Store/\nforce user = nobody", everyone: false, guest_writeable: true)
      allow(Greyhole).to receive(:installed?).and_return(true)
      conf = Share.samba_conf('example.local')
      expect(conf).to include('dfree command = /usr/bin/greyhole-dfree')
      expect(helper.samba_problems(conf)).to eq([])
    end

    it 'refuses parameters that run commands or change identities, however they are spelled' do
      [
        'root preexec = /bin/sh', 'ROOT  PREEXEC = /bin/sh', 'root_preexec = x', 'exec = x', 'postexec = x',
        'print command = x', 'add user script = x', 'magic script = x', 'passwd program = x',
        'idmap config * : script = x', 'include = /tmp/x', "inc\\\nlude = /tmp/x", 'config file = /tmp/x',
        'admin users = admin', 'username map = /tmp/map', 'panic action = x', 'wins hook = x', 'root directory = /'
      ].each do |line|
        expect(helper.samba_problems(share_with(line))).not_to be_empty, line
      end
    end

    it 'checks values that point at files, users and modules' do
      {
        'path = /etc' => 'outside the share folders',
        'directory = /var/lib/amahi-kai/files/../../../etc' => 'outside the share folders',
        'path = /var/lib/amahi-kai/files/%U' => 'outside the share folders',
        'log file = /etc/cron.d/x' => 'log file must be in /var/log/samba',
        'force user = root' => 'other than root',
        'group = root' => 'other than root',
        'force group = +root' => 'other than root',
        'guest account = root' => 'other than root',
        'vfs objects = /tmp/evil.so' => 'not allowed',
        'dfree command = /bin/sh' => 'must be /usr/bin/greyhole-dfree'
      }.each do |line, reason|
        expect(helper.samba_problems(share_with(line)).join).to include(reason), line
      end
    end

    it "allows ordinary share options and data drives" do
      ok = ['vfs objects = recycle fruit streams_xattr', 'acl allow execute always = yes', 'force user = nobody',
            'path = /mnt/storage-1/movies', 'hide dot files = yes']
      ok.each { |line| expect(helper.samba_problems(share_with(line))).to eq([]), line }
    end

    it "checks testparm's canonical output too" do
      testparm_output = "# Global parameters\n[global]\n\tlog file = /var/log/samba/%m.log\n" \
                        "\tidmap config * : backend = tdb\n\n\n[x]\n\tpath = /var/lib/amahi-kai/files/x\n\troot preexec = /bin/b\n"
      expect(helper.samba_problems(testparm_output)).to eq(['[x] root preexec is not allowed'])
    end

    it 'refuses the request before anything runs' do
      expect(refusal('samba.write_config', { 'content' => share_with('root preexec = /bin/sh') })).to start_with('smb.conf refused')
    end

    it 'checks smb.conf with the real testparm where Samba is installed' do
      skip 'testparm is not installed' unless File.executable?(AmahiHelper::TESTPARM)
      Dir.mktmpdir do |dir|
        conf = "#{dir}/smb.conf"
        File.write(conf, "[global]\n\tworkgroup = W\n[x]\n\tpath = /var/lib/amahi-kai/files/x\n")
        expect { helper.check_smb_conf(conf) }.not_to raise_error
        File.write(conf, "[global]\n[x]\n\tR O O T P R E E X E C = /bin/sh\n\tpath = /var/lib/amahi-kai/files/x\n")
        expect { helper.check_smb_conf(conf) }.to raise_error(AmahiHelper::Refused, /root preexec is not allowed/)
        File.write(conf, "[global]\n[x\n")
        expect { helper.check_smb_conf(conf) }.to raise_error(AmahiHelper::Refused, /testparm rejected/)
      end
    end
  end

  describe 'samba.write_lmhosts and samba.reload' do
    it 'accepts generated lmhosts' do
      content = Share.samba_lmhosts('example.local')
      expect(steps('samba.write_lmhosts', { 'content' => content })).to eq([[:install, '/etc/samba/lmhosts', content, nil]])
    end

    it 'refuses lines that are not an address and a name' do
      expect(refusal('samba.write_lmhosts', { 'content' => "1.2.3.4 a b\n" })).to include('not an address and a name')
      expect(refusal('samba.write_lmhosts', { 'content' => "#INCLUDE \\\\server\\x\n" })).to include('not an address')
    end

    it 'reloads running Samba services without starting stopped ones' do
      expect(steps('samba.reload', {})).to eq([%w[/usr/bin/systemctl try-reload-or-restart smbd.service nmbd.service]])
    end
  end

  describe 'share folders' do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmp = File.realpath(dir)
        Dir.mkdir("#{@tmp}/files")
        Dir.mkdir("#{@tmp}/mnt")
        Dir.mkdir("#{@tmp}/mnt/storage-1")
        example.run
      end
    end

    let(:root) { "#{@tmp}/files" }
    let(:me) { Etc.getpwuid(Process.uid).name }
    let(:my_group) { Etc.getgrgid(Process.gid).name }

    before do
      allow(helper).to receive(:share_root).and_return(root)
      allow(helper).to receive(:drives_root).and_return("#{@tmp}/mnt")
      allow(helper).to receive(:group_id).and_call_original
    end

    it 'plans create, own and chmod 2775 for a folder in the share root' do
      planned = steps('shares.create_dir', { 'path' => "#{root}/movies" })
      expect(planned).to eq([[:mkdir_p, "#{root}/movies"], [:own_dir, "#{root}/movies", 'amahi', 'users', '2775']])
      expect(helper.describe(planned.last)).to eq(['own_dir', "#{root}/movies", 'amahi', 'users', '2775'])
    end

    it 'refuses paths outside the roots or not in normal form' do
      ['/etc/x', root, "#{root}/", "#{root}/../x", "#{root}//x", "#{root}/./x", 'files/x', "#{root}/a\nb"].each do |path|
        expect(refusal('shares.create_dir', { 'path' => path })).not_to be_nil, path
      end
    end

    it 'refuses a share root that is a symlink' do
      File.symlink('/etc', "#{@tmp}/link")
      allow(helper).to receive(:share_root).and_return("#{@tmp}/link")
      expect(refusal('shares.create_dir', { 'path' => "#{@tmp}/link/x" })).to include('is not inside')
    end

    it 'only uses a data drive when it is mounted' do
      drive = "#{@tmp}/mnt/storage-1"
      expect(refusal('shares.create_dir', { 'path' => "#{drive}/movies" })).to include('is not inside')
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(drive).and_return(instance_double(File::Stat, dev: -1))
      expect(refusal('shares.create_dir', { 'path' => "#{drive}/movies" })).to be_nil
    end

    it 'creates nested folders and sets owner and mode through the open folder' do
      path = "#{root}/media/movies"
      helper.do_mkdir_p(path)
      helper.do_own_dir(path, me, my_group, '2775')
      expect(File.stat(path).mode & 0o7777).to eq(0o2775)
      expect(File.stat(path).gid).to eq(Process.gid)
    end

    it "won't follow a symlink in place of a folder" do
      File.symlink(@tmp, "#{root}/movies")
      expect { helper.do_mkdir_p("#{root}/movies/x") }.to raise_error(AmahiHelper::Failed, /is not a folder/)
      expect { helper.do_own_dir("#{root}/movies", me, my_group, '2775') }.to raise_error(AmahiHelper::Failed, /is not a folder/)
      expect(File.stat(@tmp).mode & 0o7777).not_to eq(0o2775)
    end

    it 'turns guest write on and off on the folder only' do
      path = "#{root}/public"
      Dir.mkdir(path, 0o2775)
      File.chmod(0o2775, path)
      helper.do_guest_write(path, true)
      expect(File.stat(path).mode & 0o7777).to eq(0o2777)
      helper.do_guest_write(path, false)
      expect(File.stat(path).mode & 0o7777).to eq(0o2775)
    end

    it 'removes only empty folders' do
      Dir.mkdir("#{root}/empty")
      Dir.mkdir("#{root}/full")
      File.write("#{root}/full/keep.txt", 'x')
      expect(helper.do_rmdir("#{root}/empty")).to be_nil
      expect(Dir.exist?("#{root}/empty")).to be false
      expect(helper.do_rmdir("#{root}/full")).to include("isn't empty")
      expect(Dir.exist?("#{root}/full")).to be true
      expect(helper.do_rmdir("#{root}/gone")).to include("doesn't exist")
    end

    it 'installs a file atomically and leaves no temp files' do
      target = "#{@tmp}/smb.conf"
      File.write(target, 'old')
      helper.do_install(target, 'new', nil)
      expect(File.read(target)).to eq('new')
      expect(File.stat(target).mode & 0o777).to eq(0o644)
      expect(Dir.children(@tmp)).to contain_exactly('files', 'mnt', 'smb.conf')
    end

    it 'keeps the old file when the check refuses the new one' do
      target = "#{@tmp}/smb.conf"
      File.write(target, 'old')
      allow(helper).to receive(:check_smb_conf).and_raise(AmahiHelper::Refused, 'testparm rejected smb.conf')
      expect { helper.do_install(target, 'new', :smb_conf) }.to raise_error(AmahiHelper::Refused)
      expect(File.read(target)).to eq('old')
      expect(Dir.children(@tmp)).to contain_exactly('files', 'mnt', 'smb.conf')
    end
  end

  describe 'services' do
    it 'controls only the services it lists, by their systemd unit' do
      expect(steps('services.restart', { 'service' => 'smbd' })).to eq([%w[/usr/bin/systemctl restart smbd.service]])
      expect(steps('services.stop', { 'service' => 'docker' })).to eq([%w[/usr/bin/systemctl stop docker.service]])
      expect(steps('services.start', { 'service' => 'greyhole' })).to eq([%w[/usr/bin/systemctl start greyhole.service]])
    end

    it 'enables and disables with --now, so the service starts or stops too' do
      expect(steps('services.enable', { 'service' => 'dnsmasq' })).to eq([%w[/usr/bin/systemctl enable --now dnsmasq.service]])
      expect(steps('services.disable', { 'service' => 'dnsmasq' })).to eq([%w[/usr/bin/systemctl disable --now dnsmasq.service]])
    end

    it 'refuses other services and unit names' do
      %w[sshd amahi-kai mariadb smbd.service ../x].each do |name|
        expect(refusal('services.restart', { 'service' => name })).to include("isn't one Amahi-kai manages"), name
      end
      expect(refusal('services.stop', {})).to eq('service is missing')
    end
  end

  describe 'system' do
    it 'reboots and powers off through systemd' do
      expect(steps('system.reboot', {})).to eq([%w[/usr/bin/systemctl reboot]])
      expect(steps('system.poweroff', {})).to eq([%w[/usr/bin/systemctl poweroff]])
      expect(refusal('system.reboot', { 'delay' => 5 })).to eq('unexpected argument delay')
    end

    it 'creates a swap file of 1 to 8 GB' do
      expect(steps('system.create_swap', { 'size_gb' => 2 })).to eq([[:create_swapfile, '/swapfile', 2]])
      [0, 9, '2', 2.5, nil].each do |size|
        expect(refusal('system.create_swap', { 'size_gb' => size })).to include('whole number from 1 to 8'), size.inspect
      end
    end

    describe 'the swap file' do
      let(:dir) { Dir.mktmpdir }
      let(:swapfile) { "#{dir}/swapfile" }
      let(:fstab) { "#{dir}/fstab" }
      let(:ran) { [] }

      before do
        stub_const('AmahiHelper::FSTAB', fstab)
        File.write(fstab, "UUID=abc / ext4 defaults 0 1\n")
        allow(helper).to receive(:run_command) { |argv| ran << argv.first.split('/').last }
      end

      after { FileUtils.rm_rf(dir) }

      it 'is created private, turned on and added to fstab once' do
        helper.do_create_swapfile(swapfile, 1)
        expect(File.stat(swapfile).mode & 0o777).to eq(0o600)
        expect(ran).to eq(%w[fallocate mkswap swapon])
        expect(File.read(fstab)).to end_with("#{swapfile} none swap sw 0 0\n")

        File.unlink(swapfile)
        helper.do_create_swapfile(swapfile, 1)
        expect(File.read(fstab).scan(swapfile).size).to eq(1)
      end

      it 'falls back to writing zeros when fallocate fails' do
        allow(helper).to receive(:run_command) do |argv|
          ran << argv.first.split('/').last
          raise AmahiHelper::Failed, 'fallocate exited 1' if argv.first.end_with?('fallocate')
        end
        helper.do_create_swapfile(swapfile, 1)
        expect(ran).to eq(%w[fallocate dd mkswap swapon])
      end

      it 'is removed again when a step fails, and fstab is left alone' do
        allow(helper).to receive(:run_command) { |argv| raise AmahiHelper::Failed, 'mkswap exited 1' if argv.first.end_with?('mkswap') }
        expect { helper.do_create_swapfile(swapfile, 1) }.to raise_error(AmahiHelper::Failed)
        expect(File.exist?(swapfile)).to be false
        expect(File.read(fstab)).not_to include(swapfile)
      end

      it 'refuses when the file already exists' do
        File.write(swapfile, 'in use')
        expect { helper.do_create_swapfile(swapfile, 1) }.to raise_error(AmahiHelper::Refused, /already exists/)
        expect(File.read(swapfile)).to eq('in use')
      end
    end
  end

  describe 'network' do
    it 'sets the hostname to one DNS label' do
      expect(steps('network.set_hostname', { 'hostname' => 'amahi-kai' })).to eq([%w[/usr/bin/hostnamectl set-hostname amahi-kai]])
      ['my nas', '-nas', 'nas-', 'nas.lan', 'x' * 64, "nas\n"].each do |name|
        expect(refusal('network.set_hostname', { 'hostname' => name })).not_to be_nil, name.inspect
      end
    end

    let(:dnsmasq_conf) do
      DnsmasqService.write_config!(net: '192.168.1', dyn_lo: 100, dyn_hi: 254, gateway: '1', lease_time: 14_400,
                                   domain: 'amahi.net', dhcp_enabled: true, dns_enabled: true)
      Privileged.calls.find { |op, _| op == 'network.write_dnsmasq_config' }.last[:content]
    end

    it "accepts dnsmasq's generated config and installs it with a dnsmasq check" do
      allow(DnsmasqService).to receive(:running?).and_return(false)
      expect(steps('network.write_dnsmasq_config', { 'content' => dnsmasq_conf }))
        .to eq([[:install, '/etc/dnsmasq.d/amahi.conf', dnsmasq_conf, :dnsmasq]])
    end

    it 'refuses dnsmasq lines that could run scripts, read files or redirect DNS' do
      ['dhcp-script=/tmp/x', 'conf-file=/etc/shadow', 'conf-dir=/tmp', 'addn-hosts=/tmp/h', 'server=8.8.8.8',
       'dhcp-range=192.168.1.100,192.168.1.300,600s', 'domain=bad domain', 'except-interface=eth0',
       "local=/x/\nuser=root"].each do |line|
        expect(refusal('network.write_dnsmasq_config', { 'content' => "#{line}\n" })).to include('not one Amahi-kai writes'), line
      end
    end

    it 'accepts only address lines for DNS aliases' do
      ok = "# aliases\naddress=/files/192.168.1.10\naddress=/blocked/\n"
      expect(steps('network.write_dns_aliases', { 'content' => ok })).to eq([[:install, '/etc/dnsmasq.d/amahi-aliases.conf', ok, :dnsmasq]])
      ['address=/a.b/1.2.3.4', 'address=/x/1.2.3.400', 'server=/x/1.2.3.4', 'dhcp-range=1.2.3.4,1.2.3.5,1s'].each do |line|
        expect(refusal('network.write_dns_aliases', { 'content' => "#{line}\n" })).to include('not one Amahi-kai writes'), line
      end
    end

    it 'creates the dnsmasq folder if dnsmasq is not installed yet' do
      Dir.mktmpdir do |dir|
        target = "#{dir}/dnsmasq.d/amahi.conf"
        allow(helper).to receive(:check_dnsmasq_conf)
        helper.do_install(target, "bind-interfaces\n", :dnsmasq)
        expect(File.read(target)).to eq("bind-interfaces\n")
        expect(helper).to have_received(:check_dnsmasq_conf)
      end
    end

    it 'checks the config with the real dnsmasq where it is installed' do
      skip 'dnsmasq is not installed' unless File.executable?(AmahiHelper::DNSMASQ)
      Dir.mktmpdir do |dir|
        conf = "#{dir}/amahi.conf"
        File.write(conf, "dhcp-range=192.168.1.100,192.168.1.254,14400s\nbind-interfaces\n")
        expect { helper.check_dnsmasq_conf(conf) }.not_to raise_error
        File.write(conf, "dhcp-rnage=1\n")
        expect { helper.check_dnsmasq_conf(conf) }.to raise_error(AmahiHelper::Refused, /dnsmasq rejected/)
      end
    end
  end

  describe 'running commands' do
    it 'runs without a shell, in a minimal environment, with stdin' do
      script = '[ -z "$RUBYOPT" ] && [ "$PATH" = "/usr/sbin:/usr/bin:/sbin:/bin" ] && read a && [ "$a" = secret ]'
      expect(helper.run_command(['/bin/sh', '-c', script, { stdin: "secret\n" }])).to be_nil
    end

    it 'raises with the end of stderr when a command fails' do
      expect { helper.run_command(['/bin/sh', '-c', 'echo first >&2; echo oops >&2; exit 3']) }
        .to raise_error(AmahiHelper::Failed, 'sh exited 3: first oops')
    end

    it 'notes an allowed failure instead of raising' do
      expect(helper.run_command(['/bin/sh', '-c', 'exit 4', { allow_failure: true }])).to start_with('ignored: sh exited 4')
    end
  end

  describe 'the audit log' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(dir) }

    before do
      stub_const('AmahiHelper::LOG_DIR', "#{dir}/log")
      stub_const('AmahiHelper::LOG_FILE', "#{dir}/log/helper.log")
      allow(helper).to receive(:check_environment!)
      allow(Process).to receive(:euid).and_return(0)
    end

    it 'writes one JSON line per call, with secrets filtered and content summarized' do
      expect { helper.execute('users.set_password', { 'login' => 'root', 'password' => 'hunter2hunter2' }) }
        .to raise_error(AmahiHelper::Refused)
      expect { helper.execute('samba.write_config', { 'content' => "[global]\n\troot preexec = x\n" }) }
        .to raise_error(AmahiHelper::Refused)

      expect { helper.execute('samba.reload', StringIO.new('not json')) }.to raise_error(AmahiHelper::Refused)

      lines = File.readlines(AmahiHelper::LOG_FILE).map { |l| JSON.parse(l) }
      expect(lines.size).to eq(3)
      expect(lines.last).to include('op' => 'samba.reload', 'args' => '(not a JSON object)', 'error' => 'arguments are not valid JSON')
      lines.pop
      expect(lines.first).to include('op' => 'users.set_password', 'result' => 'refused', 'error' => 'login root is reserved',
                                     'args' => { 'login' => 'root', 'password' => '[FILTERED]' })
      expect(lines.last['args']['content']).to include('bytes' => 27)
      expect(File.read(AmahiHelper::LOG_FILE)).not_to include('hunter2')
    end
  end
end
