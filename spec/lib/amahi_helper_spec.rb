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
  def run_helper(*args, stdin: '', env: {})
    Bundler.with_unbundled_env do
      Open3.capture3(env, RbConfig.ruby, '--disable-gems', helper_path, *args, stdin_data: stdin)
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

    it "checks a catalog's manifests for the catalog repo's CI" do
      out, _err, status = run_helper('--check-catalog', Rails.root.join('config/apps').to_s)
      expect(status.exitstatus).to eq(0)
      expect(out.lines.map(&:strip)).to all(end_with(': ok'))
      _out, _err, status = run_helper('--check-catalog', Rails.root.join('app').to_s)
      expect(status.exitstatus).to eq(1)
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
        ['/usr/sbin/useradd', '--no-create-home', '-g', 'users', '-s', '/usr/sbin/nologin', '-c', 'Ann Smith', 'ann']
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
      allow(helper).to receive(:passwd).with('casey').and_return(account(uid: 1000, gid: 1000))
      expect(refusal('users.create', { 'login' => 'casey', 'name' => 'Casey' })).to eq('casey already exists on this system')
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
      allow(helper).to receive(:passwd).with('casey').and_return(account(uid: 1000, gid: 1000, shell: '/bin/bash'))
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
        args = { 'login' => 'casey', 'password' => 'longenough', 'name' => 'T' }.slice(*AmahiHelper::OPERATIONS[op][:params])
        expect(refusal(op, args)).to eq('casey is not an account Amahi created'), op
        expect(refusal(op, args.merge('login' => 'sysuser'))).to eq('sysuser is not an account Amahi created'), op
        expect(refusal(op, args.merge('login' => 'ghost'))).to eq('ghost has no Linux account'), op
      end
    end

    it 'normalizes an account to no shell and no extra groups, once' do
      allow(helper).to receive(:normal_account?).with('ann').and_return(false, true)
      expect(steps('users.normalize', { 'login' => 'ann' })).to eq([['/usr/sbin/usermod', '-s', '/usr/sbin/nologin', '-G', '', 'ann']])
      expect(steps('users.normalize', { 'login' => 'ann' })).to eq([])
    end

    it 'deletes the Samba user, then the Linux account of an app account, with a home folder an older version made' do
      expect(steps('users.delete', { 'login' => 'ann' })).to eq([
        ['/usr/bin/pdbedit', '-d0', '-x', '-u', 'ann', { allow_failure: true }],
        [:end_user_processes, 'ann'], # their SMB sessions: userdel refuses an account in use
        ['/usr/sbin/userdel', 'ann']
      ])
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with('/home/x').and_return(true)
      expect(steps('users.delete', { 'login' => 'ann' }).last).to eq(['/usr/sbin/userdel', '-r', 'ann'])
    end

    it 'deletes only the Samba user when there is no Linux account' do
      expect(steps('users.delete', { 'login' => 'ghost' })).to eq([['/usr/bin/pdbedit', '-d0', '-x', '-u', 'ghost', { allow_failure: true }]])
    end

    it "ends a deleted account's processes, asked first, then made to; never a system account's" do
      allow(helper).to receive(:passwd).with('ann').and_return(account(uid: 1001))
      allow(helper).to receive(:passwd).with('sys').and_return(account(uid: 120))
      allow(helper).to receive(:pause)
      allow(helper).to receive(:user_process_ids).with(1001).and_return([4242], [4242], [], [])
      allow(Process).to receive(:kill)
      helper.do_end_user_processes('ann')
      expect(Process).to have_received(:kill).with('TERM', 4242).once
      expect(Process).not_to have_received(:kill).with('KILL', anything)

      helper.do_end_user_processes('sys')
      expect(Process).to have_received(:kill).once
    end

    it "counts a process as the user's by any of its ids, as userdel does" do
      Dir.mktmpdir do |proc_dir|
        FileUtils.mkdir_p(%W[#{proc_dir}/10 #{proc_dir}/11 #{proc_dir}/12])
        File.write("#{proc_dir}/10/status", "Name:\tsmbd\nUid:\t0\t1001\t0\t1001\n")
        File.write("#{proc_dir}/11/status", "Name:\tsshd\nUid:\t0\t0\t0\t0\n")
        File.write("#{proc_dir}/12/status", "Name:\tsmbd\nUid:\t1001\t1001\t1001\t1001\n")
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob).with('/proc/[0-9]*/status').and_return(Dir.glob("#{proc_dir}/*/status").sort)
        expect(helper.user_process_ids(1001)).to eq([10, 12])
      end
    end

    it "refuses to delete an account the app didn't create" do
      expect(refusal('users.delete', { 'login' => 'casey' })).to eq('casey is not an account Amahi created')
    end
  end

  describe 'samba.write_config' do
    let(:base) do
      "[global]\n\tworkgroup = WORKGROUP\n\tlog file = /var/log/samba/%m.log\n\tunix extensions = no\n" \
      "\tload printers = no\n\tprinting = bsd\n\tprintcap name = /dev/null\n\tdisable spoolss = yes\n"
    end

    def share_with(line)
      "#{base}[Bad]\n\tpath = /var/lib/amahi-kai/files/bad\n\t#{line}\n"
    end

    before { allow(helper).to receive(:passwd).and_call_original }

    it 'plans an install checked by testparm' do
      planned = steps('samba.write_config', { 'content' => base })
      expect(planned).to eq([[:install, '/etc/samba/smb.conf', base, :smb_conf], [:refresh_greyhole_pool], [:stop_greyhole_stats]])
    end

    # The config the app generates, with every kind of share and the settings a share's Advanced
    # section may add: Samba as the setup wizard, Greyhole and the Trash leave it.
    def app_config(greyhole: true)
      create(:share, name: 'Movies', path: '/var/lib/amahi-kai/files/movies', disk_pool_copies: 2,
                     extras: "veto files = /.DS_Store/\nhide dot files = yes", everyone: false, guest_writeable: true)
      create(:share, name: 'Backups', path: '/mnt/storage-1/backups', disk_pool_copies: 0, rdonly: true,
                     extras: "vfs objects = catia fruit streams_xattr\nfruit:time machine = yes\nfruit:time machine max size = 500G")
      Setting.set('debug', '1', Setting::SHARES)
      Setting.set('win98', '1', Setting::SHARES)
      Setting.set('net', '192.168.1')
      allow(Share).to receive(:primary_interface).and_return('ens18')
      allow(Greyhole).to receive(:installed?).and_return(greyhole)
      Share.samba_conf('example.local')
    end

    it 'accepts the config the app generates, with Greyhole and without' do
      conf = app_config
      expect(conf).to include('dfree command = /opt/amahi-kai/libexec/amahi-dfree', 'hosts allow', 'client lanman auth',
                              'log level = 5', 'wide links = yes', 'unix extensions = no')
      expect(helper.samba_problems(conf)).to eq([])
      Share.delete_all
      expect(helper.samba_problems(app_config(greyhole: false))).to eq([])
    end

    it "accepts testparm's canonical form of it too, where Samba is installed" do
      skip 'testparm is not installed' unless File.executable?(AmahiHelper::TESTPARM)
      [true, false].each do |greyhole|
        Share.delete_all
        conf = app_config(greyhole: greyhole)
        Dir.mktmpdir do |dir|
          File.write("#{dir}/smb.conf", conf)
          canonical, err, status = Open3.capture3(AmahiHelper::TESTPARM, '-s', "#{dir}/smb.conf")
          expect(status).to be_success, err
          expect(canonical).to include('read only = No', 'dfree command =', 'unix extensions = No')
          expect(helper.samba_problems(canonical)).to eq([]), "greyhole: #{greyhole}"
        end
      end
    end

    it 'pins the global values it writes, read as Samba reads them, and wants the ones whose default differs' do
      { 'guest account = root' => 'guest account must be nobody', 'guest account = amahi' => 'must be nobody',
        'unix extensions = yes' => 'unix extensions must be no', 'smb1 unix extensions = True' => 'must be no',
        'load printers = 1' => 'load printers must be no', 'printing = cups' => 'printing must be bsd',
        'printcap name = /etc/printcap' => 'must be /dev/null', 'disable spoolss = False' => 'must be yes' }.each do |line, reason|
        expect(helper.samba_problems("#{base}\t#{line}\n").join).to include(reason), line
      end
      ['Guest Account = NOBODY', 'unix extensions = False', 'unix extensions = 0', 'disable spoolss = True', 'disable spoolss = 1'].each do |line|
        expect(helper.samba_problems("#{base}\t#{line}\n")).to eq([]), line
      end
      without = base.lines.reject { |line| line.include?('unix extensions') }.join
      expect(helper.samba_problems(without)).to eq(['[global] unix extensions = no is missing'])
      expect(helper.samba_problems("#{without}\tsmb1 unix extensions = No\n")).to eq([])
      expect(helper.samba_problems("[global]\n\tworkgroup = W\n")).to eq(
        ['[global] unix extensions = no is missing', '[global] load printers = no is missing', '[global] printing = bsd is missing',
         '[global] printcap name = /dev/null is missing', '[global] disable spoolss = yes is missing']
      )
    end

    it 'refuses every parameter that is not on its list, however it is spelled' do
      [
        'root preexec = /bin/sh', 'ROOT  PREEXEC = /bin/sh', 'root_preexec = x', 'exec = x', 'postexec = x',
        'print command = x', 'add user script = x', 'magic script = x', 'passwd program = x',
        'idmap config * : script = x', 'include = /tmp/x', "inc\\\nlude = /tmp/x", 'config file = /tmp/x',
        'admin users = admin', 'username map = /tmp/map', 'panic action = x', 'wins hook = x', 'root directory = /',
        'preload modules = /var/lib/amahi-kai/files/x/m.so', 'perfcount module = x', 'force user = nobody',
        'force group = users', 'shadow:basedir = /', 'copy = global', 'smb ports = 4445', 'made up = x'
      ].each do |line|
        expect(helper.samba_problems(share_with(line))).to eq(["[bad] #{line.split('=').first.strip.gsub(/\\\n/, ' ')} is not allowed"]), line
      end
    end

    it "takes global parameters only in [global]" do
      expect(helper.samba_problems("#{base}\tpreload modules = /x.so\n")).to eq(['[global] preload modules is not allowed'])
      expect(helper.samba_problems(share_with('hosts allow = 0.0.0.0/0'))).to eq(['[bad] hosts allow is not allowed'])
      expect(helper.samba_problems(share_with('create mask = 0775'))).to eq([])
      expect(helper.samba_problems("#{base}\tcreate mask = 0775\n")).to eq([])
    end

    it 'checks values that point at files, users and modules' do
      {
        share_with('path = /etc') => 'outside the share folders',
        share_with('directory = /var/lib/amahi-kai/files/../../../etc') => 'outside the share folders',
        share_with('path = /var/lib/amahi-kai/files/%U') => 'outside the share folders',
        "#{base}\tlog file = /etc/cron.d/x\n" => 'log file must be in /var/log/samba',
        share_with('vfs objects = /tmp/evil.so') => 'not allowed',
        share_with('dfree command = /bin/sh') => 'must be /opt/amahi-kai/libexec/amahi-dfree',
        share_with('dfree command = /usr/bin/greyhole-dfree') => 'must be /opt/amahi-kai/libexec/amahi-dfree'
      }.each do |conf, reason|
        expect(helper.samba_problems(conf).join).to include(reason), conf
      end
    end

    it "allows ordinary share options and data drives" do
      ok = ['vfs objects = recycle fruit streams_xattr', 'acl allow execute always = yes', 'veto files = /.DS_Store/',
            'path = /mnt/storage-1/movies', 'hide dot files = yes', 'fruit:time machine = yes', 'recycle:keeptree = yes']
      ok.each { |line| expect(helper.samba_problems(share_with(line))).to eq([]), line }
    end

    it "checks testparm's canonical output too" do
      testparm_output = "# Global parameters\n[global]\n\tdisable spoolss = Yes\n\tload printers = No\n\tlog file = /var/log/samba/%m.log\n" \
                        "\tprintcap name = /dev/null\n\tsmb1 unix extensions = No\n\tidmap config * : backend = tdb\n\tprinting = bsd\n\n\n" \
                        "[x]\n\tpath = /var/lib/amahi-kai/files/x\n\troot preexec = /bin/b\n"
      expect(helper.samba_problems(testparm_output)).to eq(['[x] root preexec is not allowed'])
    end

    it 'refuses the request before anything runs' do
      expect(refusal('samba.write_config', { 'content' => share_with('root preexec = /bin/sh') })).to start_with('smb.conf refused')
    end

    it "doesn't offer --dry-run or --check-catalog through sudo" do
      out, err, status = run_helper('--dry-run', 'samba.reload', stdin: '{}', env: { 'SUDO_USER' => 'amahi' })
      expect(status.exitstatus).to eq(1)
      expect(out).to eq('')
      expect(err).to include('not available through sudo')
      _out, err, status = run_helper('--check-catalog', '/tmp', env: { 'SUDO_USER' => 'amahi' })
      expect(status.exitstatus).to eq(1)
      expect(err).to include('not available through sudo')
    end

    it 'checks smb.conf with the real testparm where Samba is installed' do
      skip 'testparm is not installed' unless File.executable?(AmahiHelper::TESTPARM)
      Dir.mktmpdir do |dir|
        conf = "#{dir}/smb.conf"
        File.write(conf, "#{base}[x]\n\tpath = /var/lib/amahi-kai/files/x\n")
        expect { helper.check_smb_conf(conf) }.not_to raise_error
        File.write(conf, "#{base}[x]\n\tR O O T P R E E X E C = /bin/sh\n\tpath = /var/lib/amahi-kai/files/x\n")
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

    it "won't follow a symlink in place of a folder, anywhere on the way, and makes nothing where it points" do
      Dir.mkdir("#{@tmp}/elsewhere")
      File.symlink("#{@tmp}/elsewhere", "#{root}/movies")
      expect { helper.do_mkdir_p("#{root}/movies/x") }.to raise_error(AmahiHelper::Failed, /is a symbolic link/)
      expect { helper.do_mkdir_p("#{root}/movies/x/y") }.to raise_error(AmahiHelper::Failed, /is a symbolic link/)
      expect(Dir.children("#{@tmp}/elsewhere")).to eq([])
      expect { helper.do_own_dir("#{root}/movies", me, my_group, '2775') }.to raise_error(AmahiHelper::Failed, /is not a folder/)
      expect(File.stat(@tmp).mode & 0o7777).not_to eq(0o2775)
    end

    it "stops at a file in place of a folder, and makes every folder through the one above it" do
      File.write("#{root}/notes", '')
      expect { helper.do_mkdir_p("#{root}/notes/x") }.to raise_error(AmahiHelper::Failed, /is not a folder/)
      expect(File.file?("#{root}/notes")).to be true
      # Through handles: the paths given to mkdir and open are /proc/self/fd/<the folder above>/<part>
      made = []
      allow(Dir).to receive(:mkdir).and_wrap_original { |m, path, *args| made << path; m.call(path, *args) }
      helper.do_mkdir_p("#{root}/a/b")
      expect(made).to all(match(%r{\A/proc/self/fd/\d+/[ab]\z}))
      expect(File.directory?("#{root}/a/b")).to be true
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

    # Not `enable --now`, which starts nothing for a service with only an init script (Greyhole's).
    it 'enables then starts, and disables then stops, as two steps' do
      expect(steps('services.enable', { 'service' => 'greyhole' }))
        .to eq([%w[/usr/bin/systemctl enable greyhole.service], %w[/usr/bin/systemctl start greyhole.service]])
      expect(steps('services.disable', { 'service' => 'dnsmasq' }))
        .to eq([%w[/usr/bin/systemctl disable dnsmasq.service], %w[/usr/bin/systemctl stop dnsmasq.service]])
    end

    it 'refuses other services and unit names' do
      %w[sshd amahi-kai mariadb smbd.service ../x].each do |name|
        expect(refusal('services.restart', { 'service' => name })).to include("isn't one Amahi-kai manages"), name
      end
      expect(refusal('services.stop', {})).to eq('service is missing')
    end
  end

  describe 'system' do
    it "starts System Update's job, once it is installed" do
      Tempfile.create('unit') do |unit|
        stub_const('AmahiHelper::UPDATE_UNIT', unit.path)
        expect(steps('system.update', {})).to eq([%w[/usr/bin/systemctl start amahi-kai-update.service]])
      end
      stub_const('AmahiHelper::UPDATE_UNIT', '/nonexistent/amahi-kai-update.service')
      expect(refusal('system.update', {})).to eq("System Update's job isn't installed yet")
      expect(refusal('system.update', { 'branch' => 'x' })).to eq('unexpected argument branch')
    end

    it 'leaves the repair flag for the update script when asked to repair' do
      Tempfile.create('unit') do |unit|
        stub_const('AmahiHelper::UPDATE_UNIT', unit.path)
        expect(steps('system.update', { 'repair' => true }))
          .to eq([[:install, '/run/amahi-kai-update.repair', "repair\n", nil, '0600'],
                  %w[/usr/bin/systemctl start amahi-kai-update.service]])
        expect(steps('system.update', { 'repair' => false })).to eq([%w[/usr/bin/systemctl start amahi-kai-update.service]])
        expect(refusal('system.update', { 'repair' => 'yes' })).to eq('repair must be true or false')
      end
    end

    describe 'checking for updates' do
      let(:repo) { Dir.mktmpdir }
      let(:env_file) { "#{repo}/amahi.env" }

      def git(*args)
        out, err, status = Open3.capture3('git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', *args)
        raise err unless status.success?

        out.strip
      end

      def commit(subject, changelog, version)
        File.write("#{repo}/CHANGELOG.md", changelog)
        File.write("#{repo}/VERSION", "#{version}\n")
        git('add', 'CHANGELOG.md', 'VERSION')
        git('commit', '-q', '-m', subject)
        git('rev-parse', 'HEAD')
      end

      def channel(name)
        File.write(env_file, "SECRET_KEY_BASE=x\nAMAHI_UPDATE_CHANNEL=#{name}\n")
      end

      def releases(*tags)
        allow(helper).to receive(:newest_release) do |pre|
          picks = tags.reject { |t| !pre && t.include?('rc') }.map { |t| { tag: t, version: t.delete_prefix('v') } }
          [picks.max_by { |r| helper.release_key(r[:version]) }, nil]
        end
      end

      before do
        git('init', '-q', '-b', 'main')
        @running = commit('Old (#1)', "# Changelog\n\n- **Old entry.**\n", '0.9.1')
        git('tag', 'v0.9.1')
        commit('Drive temperatures (#2)', "# Changelog\n\n- **Old entry.**\n- **Temperatures.** Detail.\n", '0.9.1')
        @latest = commit('Update window (#3)', "# Changelog\n\n- **Old entry.**\n- **Temperatures.** Detail.\n- **Window.**\n", '0.9.2')
        git('tag', 'v0.9.2')
        git('checkout', '-q', @running)
        stub_const('AmahiHelper::GIT_OPTIONS', ['-c', 'core.hooksPath=/dev/null', '-C', repo])
        stub_const('AmahiHelper::GIT', ENV['PATH'].split(':').map { |d| File.join(d, 'git') }.find { |f| File.executable?(f) })
        stub_const('AmahiHelper::ENV_FILE', env_file)
        allow(helper).to receive(:git_fetch).and_return(nil) # the tags and branches are already here
        channel('releases')
        releases('v0.9.1', 'v0.9.2')
      end

      after { FileUtils.rm_rf(repo) }

      it 'plans one action each, with no arguments' do
        expect(steps('system.check_update', {})).to eq([[:check_update], [:refresh_catalog], [:check_security_updates]])
        expect(refusal('system.check_update', { 'branch' => 'x' })).to eq('unexpected argument branch')
        expect(steps('system.update_target', {})).to eq([[:update_target]])
        expect(refusal('system.update_target', { 'tag' => 'v1' })).to eq('unexpected argument tag')
      end

      it "goes to the newest release, listing its merged changes and changelog entries" do
        expect(helper.do_update_target['target']).to eq('channel' => 'releases', 'commit' => @latest, 'version' => '0.9.2',
                                                        'tag' => 'v0.9.2', 'error' => nil)
        status = helper.update_status
        expect(status).to include('channel' => 'releases', 'current' => @running, 'current_version' => '0.9.1',
                                  'latest' => @latest, 'latest_version' => '0.9.2', 'tag' => 'v0.9.2',
                                  'available' => true, 'behind' => 2, 'error' => nil)
        expect(status['commits'].map { |c| c['subject'] }).to eq(['Update window (#3)', 'Drive temperatures (#2)'])
        expect(status['changelog']).to eq(['**Temperatures.** Detail.', '**Window.**'])
      end

      it 'never goes back: a release no newer than the running version is nothing to install' do
        git('checkout', '-q', @latest)
        releases('v0.9.1')
        expect(helper.update_target).to include('commit' => @latest, 'version' => '0.9.2', 'tag' => nil, 'error' => nil)
        expect(helper.update_status).to include('available' => false, 'behind' => 0, 'commits' => [], 'changelog' => [])
      end

      it 'takes release candidates only on the candidates channel, after their release' do
        rc = commit('Candidate (#4)', "# Changelog\n", '0.9.3rc1')
        git('tag', 'v0.9.3rc1')
        git('checkout', '-q', @running)
        releases('v0.9.2', 'v0.9.3rc1')
        expect(helper.update_target['tag']).to eq('v0.9.2')
        channel('candidates')
        expect(helper.update_target).to include('commit' => rc, 'version' => '0.9.3rc1', 'tag' => 'v0.9.3rc1')
        expect(%w[0.9.3 0.9.3rc2 0.9.3rc10 0.10.0 0.9.2].sort_by { |v| helper.release_key(v) })
          .to eq(%w[0.9.2 0.9.3rc2 0.9.3rc10 0.9.3 0.10.0])
      end

      it "follows the dev branch on the development channel, nothing new while it's already in what runs" do
        channel('development')
        git('update-ref', 'refs/remotes/origin/dev', @latest)
        expect(helper.update_target).to include('channel' => 'development', 'commit' => @latest, 'version' => '0.9.2', 'tag' => nil)
        expect(helper.update_status).to include('available' => true, 'behind' => 2, 'tag' => nil)
        git('update-ref', 'refs/remotes/origin/dev', @running)
        git('checkout', '-q', @latest)
        expect(helper.update_target).to include('commit' => @latest, 'error' => nil)
        expect(helper.update_status['available']).to be(false)
      end

      it "fails the target, rather than saying there's nothing new, when it can't find one" do
        releases
        expect(helper.update_target).to include('commit' => @running, 'error' => 'no release is published yet')
        expect { helper.do_update_target }.to raise_error(AmahiHelper::Failed, 'no release is published yet')
        allow(helper).to receive(:newest_release).and_return([nil, "couldn't read the releases from GitHub: offline"])
        expect(helper.update_status).to include('available' => false, 'error' => "couldn't read the releases from GitHub: offline")
      end

      it "refuses a release whose tag's VERSION names another version" do
        File.write("#{repo}/VERSION", "0.9.9\n")
        git('commit', '-q', '-am', 'Wrong version')
        git('tag', 'v0.9.5')
        git('checkout', '-q', @running)
        releases('v0.9.5')
        expect(helper.update_target['error']).to eq('v0.9.5\'s VERSION file says "0.9.9", not 0.9.5')
      end

      it 'reads the channel from amahi.env, releases unless it names another' do
        { "AMAHI_UPDATE_CHANNEL=development\n" => 'development', "AMAHI_UPDATE_CHANNEL=\"Candidates\"\n" => 'candidates',
          "AMAHI_UPDATE_CHANNEL=nightly\n" => 'releases', "OTHER=1\n" => 'releases' }.each do |text, want|
          File.write(env_file, text)
          expect(helper.update_channel).to eq(want), text
        end
        FileUtils.rm_f(env_file)
        expect(helper.update_channel).to eq('releases')
      end

      it "reads GitHub's releases: the highest version, no drafts, pre-releases when asked" do
        list = [{ 'tag_name' => 'v0.9.2', 'draft' => false, 'prerelease' => false },
                { 'tag_name' => 'v0.10.0', 'draft' => true, 'prerelease' => false },
                { 'tag_name' => 'v0.9.3rc1', 'draft' => false, 'prerelease' => true },
                { 'tag_name' => 'nightly', 'draft' => false, 'prerelease' => false }]
        allow(helper).to receive(:newest_release).and_call_original
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, %w[/usr/bin/timeout /usr/bin/timeout], '30', '/usr/bin/curl', any_args)
                                          .and_return([JSON.generate(list), '', instance_double(Process::Status, success?: true)])
        expect(helper.newest_release(false)).to eq([{ tag: 'v0.9.2', version: '0.9.2' }, nil])
        expect(helper.newest_release(true)).to eq([{ tag: 'v0.9.3rc1', version: '0.9.3rc1' }, nil])
      end

      it 'writes the status for the app, and skips while an update holds the lock' do
        dir = Dir.mktmpdir
        stub_const('AmahiHelper::UPDATE_LOCK', "#{dir}/lock")
        stub_const('AmahiHelper::UPDATE_STATUS', "#{dir}/status.json")
        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }

        reply = helper.do_check_update
        expect(reply['update']).to include('available' => true, 'tag' => 'v0.9.2')
        expect(JSON.parse(File.read("#{dir}/status.json"))['behind']).to eq(2)

        File.open("#{dir}/lock", File::RDWR | File::CREAT) do |held|
          held.flock(File::LOCK_EX)
          expect(helper.do_check_update).to include('skipped' => 'System Update is running')
        end
        expect(helper).to have_received(:newest_release).once
      ensure
        FileUtils.rm_rf(dir)
      end
    end

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
    it "sets the hostname to one DNS label, and names it in /etc/hosts" do
      hosts = Tempfile.new('hosts')
      hosts.write("127.0.0.1 localhost\n127.0.1.1 troy\n\n::1 ip6-localhost ip6-loopback\n")
      hosts.close
      stub_const('AmahiHelper::HOSTS', hosts.path)
      expect(steps('network.set_hostname', { 'hostname' => 'amahi-kai' })).to eq(
        [%w[/usr/bin/hostnamectl set-hostname amahi-kai],
         [:install, hosts.path, "127.0.0.1 localhost\n127.0.1.1 amahi-kai\n\n::1 ip6-localhost ip6-loopback\n", nil]]
      )
      File.write(hosts.path, '127.0.0.1 localhost') # no 127.0.1.1 line, nor a final newline
      expect(helper.hosts_naming('kai')).to eq("127.0.0.1 localhost\n127.0.1.1 kai\n")
      ['my nas', '-nas', 'nas-', 'nas.lan', 'x' * 64, "nas\n"].each do |name|
        expect(refusal('network.set_hostname', { 'hostname' => name })).not_to be_nil, name.inspect
      end
    end

    let(:dnsmasq_conf) do
      DnsmasqService.write_config!(net: '192.168.1', first: 100, last: 254, router: 1, lease_time: 14_400,
                                   interface: 'ens18', dhcp_enabled: true)
      Privileged.calls.find { |op, _| op == 'network.write_dnsmasq_config' }.last[:content]
    end

    it "accepts dnsmasq's generated config and installs it with a dnsmasq check" do
      allow(DnsmasqService).to receive(:running?).and_return(false)
      expect(steps('network.write_dnsmasq_config', { 'content' => dnsmasq_conf })).to eq([[:dnsmasq_config, dnsmasq_conf]])
    end

    it 'refuses dnsmasq lines that could run scripts, read files or redirect DNS' do
      ['dhcp-script=/tmp/x', 'conf-file=/etc/shadow', 'conf-dir=/tmp', 'addn-hosts=/tmp/h', 'server=8.8.8.8',
       'dhcp-range=192.168.1.100,192.168.1.300,600s', 'domain=bad domain', 'except-interface=eth0',
       "local=/x/\nuser=root"].each do |line|
        expect(refusal('network.write_dnsmasq_config', { 'content' => "#{line}\n" })).to include('not one Amahi-kai writes'), line
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

  # Network → DNS: Unbound's config is written by DnsService, checked line by line here and by
  # unbound-checkconf, and UFW lets DNS in to the addresses Unbound listens on.
  describe 'Unbound (Network → DNS)' do
    let(:lan) { NetworkInterfaces::Address.new(ip: IPAddr.new('10.99.0.1'), prefix: 24) }
    let(:ula) { NetworkInterfaces::Address.new(ip: IPAddr.new('fd99::1'), prefix: 64) }
    let(:unbound_conf) do
      allow(NetworkInterfaces).to receive(:lan).and_return('ens19' => [lan, ula])
      allow(NetworkInterfaces).to receive(:addresses).with('ens19').and_return([lan, ula])
      allow(NetworkInterfaces).to receive(:addresses).with('tailscale0')
        .and_return([NetworkInterfaces::Address.new(ip: IPAddr.new('100.64.96.4'), prefix: 32)])
      allow(DnsService).to receive(:rewrite!)
      allow(DnsmasqService).to receive(:rewrite_config!)
      Setting.set('dns_interface', 'ens19')
      Setting.set('net', '10.99.0')
      Host.create!(name: 'printer', mac: 'aa:bb:cc:dd:ee:01', address: '20')
      DnsAlias.create!(name: 'files', address: '10.99.0.30')
      DnsAlias.create!(name: 'nas', address: '')
      DnsService.config
    end

    before { allow(helper).to receive(:installed!).and_call_original }

    it "accepts DnsService's config, for each provider, and installs it with a check" do
      allow(helper).to receive(:installed!).with(AmahiHelper::UNBOUND).and_return(true)
      expect(steps('dns.write_config', { 'content' => unbound_conf })).to eq([[:dns_config, unbound_conf]])
      (DnsService::PROVIDERS.keys - ['quad9']).each do |key|
        Setting.set('dns_provider', key)
        expect(refusal('dns.write_config', { 'content' => DnsService.config })).to be_nil, key
      end
      Setting.set('dns_provider', 'custom')
      Setting.set('dns_custom_addresses', '192.168.1.53 fd00::53')
      Setting.set('dns_custom_tls_name', 'dns.example.org')
      expect(refusal('dns.write_config', { 'content' => DnsService.config })).to be_nil
    end

    it "refuses until Unbound is installed" do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(AmahiHelper::UNBOUND).and_return(false)
      expect(refusal('dns.write_config', { 'content' => "server:\n" })).to include("unbound isn't installed")
    end

    it 'refuses lines that could load code, read or write files, open the control port, or answer everyone' do
      allow(helper).to receive(:installed!).with(AmahiHelper::UNBOUND).and_return(true)
      ['module-config: "python validator iterator"', 'python-script: "/tmp/x.py"', 'include: "/etc/shadow"',
       'chroot: ""', 'username: root', 'logfile: "/etc/passwd"', 'control-enable: yes', 'remote-control:',
       'auto-trust-anchor-file: "/tmp/key"', 'tls-cert-bundle: "/tmp/certs"', 'interface: 0.0.0.0', 'interface: ::',
       'interface: eth0', 'access-control: 0.0.0.0/0 allow', 'access-control: ::/0 allow',
       'access-control: 10.0.0.0/8 allow_snoop', 'forward-addr: 8.8.8.8', 'forward-addr: 8.8.8.8@53#dns.google',
       'forward-tls-upstream: no', 'local-zone: "." static', 'local-zone: "x." redirect',
       'local-data: "x. IN TXT hello"', 'local-data: "x. IN A fd00::1"', 'local-data: "x. IN A 1.2.3.4" extra',
       'local-data-ptr: "1.2.3.4 x. y."', 'private-address: 10.0.0.0/8 x', 'serve-expired-ttl: -1',
       "server:\nverbosity: 5"].each do |line|
        expect(refusal('dns.write_config', { 'content' => "#{line}\n" })).to include('not one Amahi-kai writes'), line
      end
    end

    it "removes the config and its firewall rules when DNS is turned off" do
      expect(steps('dns.remove_config', {})).to eq([[:dns_config, nil]])
    end

    describe 'installing it' do
      let(:dir) { Dir.mktmpdir }
      let(:ran) { [] }

      before do
        @conf = "#{dir}/amahi-kai.conf"
        stub_const('AmahiHelper::UNBOUND_CONF', @conf)
        allow(helper).to receive(:check_unbound_conf)
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(true)
        allow(helper).to receive(:run_command) { |argv| ran << argv.dup && nil }
      end

      after { FileUtils.rm_rf(dir) }

      def ufw_rules = ran.select { |argv| argv.first == AmahiHelper::UFW }.map { |argv| argv.drop(1).reject { |a| a.is_a?(Hash) }.join(' ') }

      it 'lets DNS in to the addresses Unbound listens on, and no longer to those it stopped listening on' do
        helper.do_dns_config("server:\n  interface: 127.0.0.1\n  interface: ::1\n  interface: 10.99.0.1\n  interface: fd99::1\n")
        expect(File.read(@conf)).to include('interface: 10.99.0.1')
        expect(helper).to have_received(:check_unbound_conf)
        expect(ufw_rules).to eq(['allow to 10.99.0.1 port 53', 'allow to fd99::1 port 53'])
        # UFW with its IPv6 off refuses IPv6 rules; IPv4 still gets in
        expect(ran.last.last).to eq(allow_failure: true)

        ran.clear
        helper.do_dns_config("server:\n  interface: 127.0.0.1\n  interface: 10.99.0.2\n")
        expect(ufw_rules).to eq(['delete allow to 10.99.0.1 port 53', 'delete allow to fd99::1 port 53',
                                 'allow to 10.99.0.2 port 53'])

        ran.clear
        helper.do_dns_config(nil)
        expect(File.exist?(@conf)).to be false
        expect(ufw_rules).to eq(['delete allow to 10.99.0.2 port 53'])
      end

      it "leaves the firewall alone where UFW isn't installed" do
        allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(false)
        helper.do_dns_config("server:\n  interface: 10.99.0.1\n")
        expect(ran).to be_empty
      end
    end

    it 'checks the config with the real unbound-checkconf where Unbound is installed' do
      skip 'Unbound is not installed' unless File.executable?(AmahiHelper::UNBOUND_CHECKCONF)
      Dir.mktmpdir do |dir|
        conf = "#{dir}/amahi-kai.conf"
        File.write(conf, unbound_conf)
        expect { helper.check_unbound_conf(conf) }.not_to raise_error
        File.write(conf, "server:\n  interfase: 10.99.0.1\n")
        expect { helper.check_unbound_conf(conf) }.to raise_error(AmahiHelper::Refused, /unbound-checkconf rejected/)
      end
    end
  end

  # Network → DNS & DHCP's DHCP: dnsmasq's config with its firewall rule and the watch on its
  # leases, the leases' names for Unbound, and the check for another DHCP server.
  describe 'DHCP (Network → DNS & DHCP)' do
    let(:dir) { Dir.mktmpdir }
    let(:ran) { [] }

    before do
      %w[DNSMASQ_CONF DNSMASQ_LEASES UNBOUND_CONF UNBOUND_LEASES DHCP_NAMES_PATH DHCP_NAMES_SERVICE UNBOUND_RELOADED].each do |name|
        stub_const("AmahiHelper::#{name}", "#{dir}/#{name.downcase}")
      end
      stub_const('AmahiHelper::BLOCKLIST_DIR', dir)
      allow(helper).to receive(:check_dnsmasq_conf)
      allow(helper).to receive(:check_unbound_conf)
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(true)
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) }.join(' ') && nil }
    end

    after { FileUtils.rm_rf(dir) }

    def dhcp_on(interface) = "port=0\ninterface=#{interface}\nbind-interfaces\ndhcp-range=10.99.0.100,10.99.0.200,14400s\n"

    it 'checks the interface it will look for DHCP servers on' do
      expect(steps('dhcp.check_servers', { 'interface' => 'lo' })).to eq([[:dhcp_servers, 'lo']])
      ['eth99nothere', 'ens 18', '../x', ''].each do |name|
        expect(refusal('dhcp.check_servers', { 'interface' => name })).not_to be_nil, name.inspect
      end
      expect(steps('dns.sync_leases', {})).to eq([[:sync_leases]])
    end

    it "lets DHCP in on dnsmasq's interface, watches its leases for names, and undoes both when it stops" do
      allow(helper).to receive(:do_sync_leases)
      helper.do_dnsmasq_config(dhcp_on('ens19'))
      expect(ran).to eq(['/usr/sbin/ufw allow in on ens19 to any port 67 proto udp', '/usr/bin/systemctl daemon-reload',
                         '/usr/bin/systemctl enable --now dhcp_names_path'])
      expect(File.read(AmahiHelper::DHCP_NAMES_PATH)).to include('PathModified=/var/lib/misc/dnsmasq.leases')
      expect(File.read(AmahiHelper::DHCP_NAMES_SERVICE)).to include('ExecStart=/usr/local/sbin/amahi-helper dns.sync_leases',
                                                                     'StandardInputText={}')
      expect(helper).to have_received(:do_sync_leases)

      ran.clear
      helper.do_dnsmasq_config(dhcp_on('ens18'))
      expect(ran.first(2)).to eq(['/usr/sbin/ufw delete allow in on ens19 to any port 67 proto udp',
                                  '/usr/sbin/ufw allow in on ens18 to any port 67 proto udp'])

      ran.clear
      File.write(AmahiHelper::UNBOUND_LEASES, "server:\n")
      helper.do_dnsmasq_config("port=0\nbind-interfaces\nexcept-interface=lo\n")
      expect(ran).to eq(['/usr/sbin/ufw delete allow in on ens18 to any port 67 proto udp',
                         '/usr/bin/systemctl disable --now dhcp_names_path', '/usr/bin/systemctl is-active --quiet unbound',
                         "#{AmahiHelper::UNBOUND_CONTROL} reload_keep_cache"])
      expect(File.exist?(AmahiHelper::UNBOUND_LEASES)).to be false
    end

    describe "the leases' names" do
      before do
        File.write(AmahiHelper::UNBOUND_CONF, %(server:\n  local-zone: "home.arpa." static\n  local-data: "kai.home.arpa. IN A 10.99.0.1"\n))
        File.write(AmahiHelper::DNSMASQ_LEASES, <<~LEASES)
          1792700000 bc:24:11:c1:dc:cf 10.99.0.150 client 01:bc:24:11:c1:dc:cf
          1792700001 aa:bb:cc:dd:ee:01 10.99.0.151 * *
          1792700002 aa:bb:cc:dd:ee:02 10.99.0.152 Kai *
          1792700003 aa:bb:cc:dd:ee:03 10.99.0.153 bad.name *
          1792700004 aa:bb:cc:dd:ee:04 10.99.0.154 Phone *
          1792700005 aa:bb:cc:dd:ee:05 10.99.0.155 phone *
        LEASES
      end

      it "answer as name.<domain> and name, unless they're taken or not one label" do
        helper.do_sync_leases
        content = File.read(AmahiHelper::UNBOUND_LEASES)
        expect(content).to include('local-data: "client.home.arpa. IN A 10.99.0.150"', 'local-data: "client. IN A 10.99.0.150"',
                                   'local-data-ptr: "10.99.0.150 client.home.arpa."', 'local-data: "phone.home.arpa. IN A 10.99.0.154"')
        expect(content).not_to include('10.99.0.151', '10.99.0.152', '10.99.0.153', '10.99.0.155')
        expect { helper.unbound_conf(content) }.not_to raise_error
        expect(ran).to eq(['/usr/bin/systemctl is-active --quiet unbound', "#{AmahiHelper::UNBOUND_CONTROL} reload_keep_cache"])
      end

      it 'reload Unbound only when they change' do
        helper.do_sync_leases
        ran.clear
        helper.do_sync_leases
        expect(ran).to be_empty
      end

      it 'wait for DNS to be on' do
        File.unlink(AmahiHelper::UNBOUND_CONF)
        expect(helper.do_sync_leases).to eq('DNS is off')
        expect(File.exist?(AmahiHelper::UNBOUND_LEASES)).to be false
      end

      it 'go when DNS is turned off' do
        helper.do_sync_leases
        allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(false)
        helper.do_dns_config(nil)
        expect(File.exist?(AmahiHelper::UNBOUND_LEASES)).to be false
      end
    end

    describe 'looking for another DHCP server' do
      let(:discover) { helper.dhcp_discover(0x12345678, 'bc:24:11:c1:dc:cf') }

      def offer(options, xid: 0x12345678)
        packet = discover.dup
        packet.setbyte(0, 2)
        packet[4, 4] = [xid].pack('N')
        packet[240..] = options.pack('C*').ljust(60, "\0".b)
        packet
      end

      it 'sends a DHCPDISCOVER from the MAC, asking for broadcast replies' do
        expect(discover.bytesize).to eq(300)
        expect(discover.unpack('CCC')).to eq([1, 1, 6])
        expect(discover[10, 2].unpack1('n')).to eq(0x8000)
        expect(discover[28, 6].unpack1('H*')).to eq('bc2411c1dccf')
        expect(discover[236, 4].unpack1('N')).to eq(0x63825363)
        expect(discover[240, 3].bytes).to eq([53, 1, 1])
      end

      it "reads an offer's server, by its identifier or where it came from" do
        expect(helper.dhcp_offer_from(offer([53, 1, 2, 54, 4, 10, 99, 0, 7, 255]), 0x12345678, '10.99.0.9')).to eq('10.99.0.7')
        expect(helper.dhcp_offer_from(offer([53, 1, 2, 255]), 0x12345678, '10.99.0.9')).to eq('10.99.0.9')
      end

      it "ignores what isn't an offer for this discover" do
        expect(helper.dhcp_offer_from(offer([53, 1, 2, 255], xid: 1), 0x12345678, 'x')).to be_nil
        expect(helper.dhcp_offer_from(offer([53, 1, 5, 255]), 0x12345678, 'x')).to be_nil # an ACK
        expect(helper.dhcp_offer_from(discover, 0x12345678, 'x')).to be_nil
        expect(helper.dhcp_offer_from('short', 0x12345678, 'x')).to be_nil
      end
    end
  end

  # Network → DNS & DHCP's blocking: the lists chosen, downloaded daily and made into Unbound's
  # blocklist (each domain answers 0.0.0.0, with its subdomains), the allowlist, and pausing.
  describe 'DNS blocklists (Network → DNS & DHCP)' do
    let(:dir) { Dir.mktmpdir }
    let(:ran) { [] }
    let(:blocklist) { File.read(AmahiHelper::UNBOUND_BLOCKLIST) }
    let(:lists) do
      { 'hagezi-normal' => "# HaGeZi\nads.example.com\ndeep.ads.example.com\nexample.net\nsub.example.net\n*.wild.example.org\n" \
                           "track.example.com # a note\nBAD LINE\n1.2.3.4\nlocalhost\nnas.home.arpa\nuse-application-dns.net\n",
        'hagezi-tif-mini' => "malware.example\nads.example.com\nphish.example.com.\n" }
    end

    before do
      stub_const('AmahiHelper::BLOCKLIST_DIR', dir)
      stub_const('AmahiHelper::BLOCKLIST_CHOSEN', "#{dir}/chosen.json")
      stub_const('AmahiHelper::BLOCKLIST_STATUS', "#{dir}/status.json")
      stub_const('AmahiHelper::BLOCKLIST_PAUSED', "#{dir}/blocklist.paused")
      stub_const('AmahiHelper::UNBOUND_RELOADED', "#{dir}/reloaded_at")
      stub_const('AmahiHelper::BLOCKLIST_SERVICE', "#{dir}/amahi-kai-blocklists.service")
      stub_const('AmahiHelper::BLOCKLIST_TIMER', "#{dir}/amahi-kai-blocklists.timer")
      stub_const('AmahiHelper::UNBOUND_BLOCKLIST', "#{dir}/amahi-kai-blocklist.conf")
      stub_const('AmahiHelper::UNBOUND_CONF', "#{dir}/amahi-kai.conf")
      File.write(AmahiHelper::UNBOUND_CONF, %(server:\n  local-zone: "home.arpa." static\n  local-zone: "use-application-dns.net." always_nxdomain\n))
      allow(helper).to receive(:check_unbound_conf)
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) }.join(' ') && nil }
      allow(helper).to receive(:fetch_blocklist) { |key, copy| File.write(copy, lists.fetch(key)) && nil }
    end

    after { FileUtils.rm_rf(dir) }

    def choose(lists, allow = []) = File.write(AmahiHelper::BLOCKLIST_CHOSEN, JSON.generate('lists' => lists, 'allow' => allow))

    it 'takes only lists it knows, and domains for the allowlist' do
      allow(helper).to receive(:installed!).and_call_original
      allow(helper).to receive(:installed!).with(AmahiHelper::UNBOUND).and_return(true)
      expect(steps('dns.set_blocklists', { 'lists' => %w[hagezi-normal], 'allow' => %w[example.com] }))
        .to eq([[:set_blocklists, %w[hagezi-normal], %w[example.com]]])
      [[%w[evil-list], []], [[], []], ['hagezi-normal', []], [%w[hagezi-normal], ['not a domain']], [%w[hagezi-normal], ['10.0.0.1']]].each do |lists, allow|
        expect(refusal('dns.set_blocklists', { 'lists' => lists, 'allow' => allow })).not_to be_nil, [lists, allow].inspect
      end
      stub_const('AmahiHelper::ALLOWLIST_MAX', 1)
      expect(refusal('dns.set_blocklists', { 'lists' => %w[hagezi-normal], 'allow' => %w[a.example b.example] })).to include('at most 1')
    end

    it 'saves the choice, sets the daily refresh, and starts one in the background' do
      helper.do_set_blocklists(%w[hagezi-normal], %w[example.com])
      expect(JSON.parse(File.read(AmahiHelper::BLOCKLIST_CHOSEN))).to eq('lists' => %w[hagezi-normal], 'allow' => %w[example.com])
      expect(File.read(AmahiHelper::BLOCKLIST_TIMER)).to include('OnCalendar=*-*-* 04:00', 'Persistent=true')
      expect(File.read(AmahiHelper::BLOCKLIST_SERVICE)).to include('ExecStart=/usr/local/sbin/amahi-helper dns.refresh_blocklists')
      expect(ran).to eq(['/usr/bin/systemctl daemon-reload', '/usr/bin/systemctl enable --now amahi-kai-blocklists.timer',
                         '/usr/bin/systemctl start --no-block amahi-kai-blocklists.service'])
    end

    it 'makes the blocklist: every domain once, the allowlist let through, its own zones left alone' do
      choose(%w[hagezi-normal hagezi-tif-mini], %w[example.net home.arpa])
      expect(helper.do_refresh_blocklists).to eq('blocked' => 6)
      zones = blocklist.scan(/local-zone: "([^"]+)\." always_null/).flatten
      # deep.ads.example.com is under ads.example.com; sub.example.net stays, listed itself
      expect(zones).to eq(%w[ads.example.com malware.example phish.example.com sub.example.net track.example.com wild.example.org])
      expect(blocklist).to include('local-zone: "example.net." transparent')
      expect(blocklist).not_to include('home.arpa', 'use-application-dns', '1.2.3.4', 'localhost', 'deep.ads')
      expect { helper.unbound_conf(blocklist.lines.grep_v(/always_null|transparent/).join) }.not_to raise_error
      expect(helper).to have_received(:check_unbound_conf).with(AmahiHelper::UNBOUND_MAIN)
      expect(ran.last).to eq("#{AmahiHelper::UNBOUND_CONTROL} reload_keep_cache")
      status = JSON.parse(File.read(AmahiHelper::BLOCKLIST_STATUS))
      expect(status['blocked']).to eq(6)
      expect(status['lists']['hagezi-normal']['domains']).to eq(8) # the names it lists, before the others' and the allowlist
      expect(File.stat(AmahiHelper::BLOCKLIST_STATUS).mode & 0o777).to eq(0o644)
    end

    it "keeps a list's last copy when it can't be downloaded, and says why" do
      choose(%w[hagezi-tif-mini])
      helper.do_refresh_blocklists
      File.utime(Time.now - (2 * 86_400), Time.now - (2 * 86_400), "#{dir}/hagezi-tif-mini.txt")
      allow(helper).to receive(:fetch_blocklist).and_return('curl exited 22: The requested URL returned error: 503')
      helper.do_refresh_blocklists
      list = JSON.parse(File.read(AmahiHelper::BLOCKLIST_STATUS))['lists']['hagezi-tif-mini']
      expect(list).to include('domains' => 3, 'error' => 'curl exited 22: The requested URL returned error: 503')
      expect(list['downloaded_at']).to be_a(Integer)
    end

    it "downloads a list again only once its copy is a day old" do
      choose(%w[hagezi-tif-mini])
      helper.do_refresh_blocklists
      helper.do_refresh_blocklists
      expect(helper).to have_received(:fetch_blocklist).once
    end

    it 'refuses more domains than fit, and keeps the blocklist it had when Unbound refuses the new one' do
      choose(%w[hagezi-normal])
      stub_const('AmahiHelper::BLOCKLIST_MAX_DOMAINS', 2)
      expect { helper.do_refresh_blocklists }.to raise_error(AmahiHelper::Failed, /at most 2/)
      stub_const('AmahiHelper::BLOCKLIST_MAX_DOMAINS', 1_000_000)
      File.write(AmahiHelper::UNBOUND_BLOCKLIST, "server:\n")
      allow(helper).to receive(:check_unbound_conf) { |path| raise AmahiHelper::Refused, 'duplicate local-zone' if path == AmahiHelper::UNBOUND_MAIN }
      expect { helper.do_refresh_blocklists }.to raise_error(AmahiHelper::Refused, 'duplicate local-zone')
      expect(blocklist).to eq("server:\n")
      expect(JSON.parse(File.read(AmahiHelper::BLOCKLIST_STATUS))['error']).to eq('duplicate local-zone')
    end

    it "pauses: the blocklist leaves Unbound's config, and systemd brings it back after five minutes" do
      choose(%w[hagezi-tif-mini])
      helper.do_refresh_blocklists
      ran.clear
      expect(helper.do_pause_blocking['until']).to be_within(5).of(Time.now.to_i + 300)
      expect(File.exist?(AmahiHelper::UNBOUND_BLOCKLIST)).to be false
      expect(File.read(AmahiHelper::BLOCKLIST_PAUSED)).to include('malware.example')
      expect(ran).to include('/usr/bin/systemd-run --unit=amahi-kai-dns-resume --on-active=300 --timer-property=AccuracySec=5s ' \
                             '/usr/local/sbin/amahi-helper dns.resume_blocking')

      helper.do_refresh_blocklists # a refresh while paused stays paused
      expect(File.exist?(AmahiHelper::UNBOUND_BLOCKLIST)).to be false

      helper.do_resume_blocking
      expect(blocklist).to include('malware.example')
      expect(File.exist?(AmahiHelper::BLOCKLIST_PAUSED)).to be false
    end

    it 'turns off, and goes when DNS does' do
      choose(%w[hagezi-tif-mini])
      helper.do_set_blocklists(%w[hagezi-tif-mini], [])
      helper.do_refresh_blocklists
      helper.do_blocking_off
      expect(%w[UNBOUND_BLOCKLIST BLOCKLIST_CHOSEN BLOCKLIST_STATUS].map { |c| File.exist?(AmahiHelper.const_get(c)) }).to all(be false)
      expect(ran).to include('/usr/bin/systemctl disable --now amahi-kai-blocklists.timer')

      helper.do_set_blocklists(%w[hagezi-tif-mini], [])
      helper.do_refresh_blocklists
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(false)
      helper.do_dns_config(nil)
      expect(File.exist?(AmahiHelper::UNBOUND_BLOCKLIST)).to be false
    end

    it "reads Unbound's totals, since its start or the last reload, whichever came later" do
      stats = "total.num.queries=1200\ntotal.num.cachehits=900\nnum.answer.secure=300\nnum.answer.bogus=2\ntime.up=7200.5\n"
      allow(helper).to receive(:capture).with([AmahiHelper::UNBOUND_CONTROL, 'stats_noreset']).and_return(stats)
      expect(helper.do_dns_stats).to include('running' => true, 'queries' => 1200, 'answered_here' => 900, 'secure' => 300, 'bogus' => 2,
                                             'since' => be_within(2).of(Time.now.to_i - 7200))
      helper.unbound_reload
      expect(helper.do_dns_stats['since']).to be_within(2).of(Time.now.to_i)
      allow(helper).to receive(:run_command).and_return('ignored: systemctl exited 3')
      expect(helper.do_dns_stats).to eq('running' => false)
    end

    it 'reads a line of a list' do
      { 'ads.example.com' => 'ads.example.com', '*.Wild.Example.org.' => 'wild.example.org', 'x.example.com # why' => 'x.example.com',
        '# a comment' => nil, '' => nil, '10.0.0.1' => nil, 'localhost' => nil, 'localhost.localdomain' => nil,
        '0.0.0.0 ads.example.com' => nil, 'under_score.example.com' => 'under_score.example.com' }.each do |line, name|
        expect(helper.blocklist_domain(line)).to eq(name), line.inspect
      end
    end
  end

  # Network → DNS & DHCP's IPv6: radvd announcing the NAS as the IPv6 DNS server, the NAS's own
  # unique local address, and what the routers announce.
  describe 'IPv6 (Network → DNS & DHCP)' do
    let(:dir) { Dir.mktmpdir }
    let(:ran) { [] }

    before do
      stub_const('AmahiHelper::ULA_UNIT', "#{dir}/amahi-kai-ula.service")
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) }.join(' ') && nil }
    end

    after { FileUtils.rm_rf(dir) }

    it "accepts DnsService's radvd config, and refuses announcing a router, public ranges or other lines" do
      allow(NetworkInterfaces).to receive(:lan).and_return('ens19' => [])
      allow(NetworkInterfaces).to receive(:default_name).and_return('ens19')
      allow(helper).to receive(:installed!).and_call_original
      allow(helper).to receive(:installed!).with(AmahiHelper::RADVD).and_return(true)
      conf = DnsService.radvd_config
      expect(steps('dns.write_radvd_config', { 'content' => conf })).to eq([[:install, AmahiHelper::RADVD_CONF, conf, :radvd]])
      ['AdvDefaultLifetime 1800;', 'AdvSendAdvert off;', 'prefix 2600:1700:abcd::/64 {', 'prefix fd00::/48 {', 'RDNSS 2606:4700:4700::1111 {',
       'RDNSS 9.9.9.9 {', 'DNSSL not a domain {', 'AdvManagedFlag on;', 'interface ens19 { AdvSendAdvert on; };'].each do |line|
        expect(refusal('dns.write_radvd_config', { 'content' => "#{line}\n" })).to include('not one Amahi-kai writes'), line
      end
    end

    it 'puts only a unique local address on a real interface' do
      expect(steps('dns.set_own_address', { 'interface' => 'lo', 'address' => 'fdab:cdef:1234:0::53' })).to eq([[:set_ula, 'lo', 'fdab:cdef:1234::53']])
      [%w[lo 2600:1700::53], %w[lo 10.0.0.53], %w[lo fdab::53/64], %w[eth99nothere fdab::53]].each do |interface, address|
        expect(refusal('dns.set_own_address', { 'interface' => interface, 'address' => address })).not_to be_nil, address
      end
      expect(steps('dns.check_routers', { 'interface' => 'lo' })).to eq([[:ipv6_advertisers, 'lo']])
    end

    it "keeps the NAS's own address on the interface at every boot, and takes it away" do
      helper.do_set_ula('ens19', 'fdab:cdef:1234::53')
      unit = File.read(AmahiHelper::ULA_UNIT)
      expect(unit).to include("ExecStartPre=-#{AmahiHelper::IP} -6 route del fdab:cdef:1234::/64 dev lo",
                              "ExecStart=#{AmahiHelper::IP} -6 addr replace fdab:cdef:1234::53/64 dev ens19",
                              "ExecStop=#{AmahiHelper::IP} -6 addr del fdab:cdef:1234::53/64 dev ens19", 'WantedBy=multi-user.target')
      expect(ran).to eq(['/usr/bin/systemctl daemon-reload', '/usr/bin/systemctl enable amahi-kai-ula.service',
                         '/usr/bin/systemctl restart amahi-kai-ula.service'])
      ran.clear
      helper.do_set_ula('ens19', 'fdab:cdef:1234::53')
      expect(ran).to be_empty # nothing changed
      helper.do_set_ula('ens18', 'fdab:cdef:1234::53')
      expect(ran.first).to eq('/usr/bin/systemctl stop amahi-kai-ula.service') # the old address goes first
      ran.clear
      helper.do_remove_ula
      expect(File.exist?(AmahiHelper::ULA_UNIT)).to be false
      expect(ran).to eq(['/usr/bin/systemctl disable --now amahi-kai-ula.service', '/usr/bin/systemctl daemon-reload'])
    end

    it "reads a router advertisement: whether it's a router, its ranges, DNS servers and search domains" do
      advert = [134, 0, 0, 64, 0, 1800, 0, 0].pack('CCnCCnNN') +
               [3, 4, 64, 0xc0, 86_400, 14_400, 0].pack('CCCCNNN') + IPAddr.new('2600:1700:abcd::').hton +
               [25, 5, 0, 1200].pack('CCnN') + IPAddr.new('2600:1700:abcd::1').hton + IPAddr.new('fd99::1').hton +
               [31, 3, 0, 1200].pack('CCnN') + "\x04home\x04arpa\x00".b.ljust(16, "\0".b)
      expect(helper.router_advertisement(advert)).to eq('lifetime' => 1800, 'prefixes' => ['2600:1700:abcd::/64'],
                                                         'dns' => %w[2600:1700:abcd::1 fd99::1], 'domains' => ['home.arpa'])
      expect(helper.router_advertisement([135, 0, 0, 0].pack('CCnN') + ("\0".b * 16))).to be_nil # a neighbor solicitation
      expect(helper.router_advertisement(advert.byteslice(0, 40))['prefixes']).to eq([]) # cut short
    end
  end

  # Network → DNS & DHCP's router mode: the internet interface's address, forwarding, UFW's NAT
  # block and rules, and the way back.
  describe 'router mode (Network → DNS & DHCP)' do
    let(:dir) { Dir.mktmpdir }
    let(:ran) { [] }
    let(:forwards) { [{ protocol: 'tcp', port: 8080, address: '10.99.0.60', to_port: 80 }] }
    let(:before_rules) { "# rules.before\n*filter\n:ufw-before-input - [0:0]\n-A ufw-before-input -i lo -j ACCEPT\nCOMMIT\n" }

    before do
      stub_const('AmahiHelper::WAN_NETPLAN', "#{dir}/70-amahi-kai-wan.yaml")
      stub_const('AmahiHelper::ROUTER_SYSCTL', "#{dir}/90-amahi-kai-router.conf")
      stub_const('AmahiHelper::ROUTER_STATE', "#{dir}/router.json")
      stub_const('AmahiHelper::UFW_CONF', "#{dir}/ufw.conf")
      stub_const('AmahiHelper::UFW_BEFORE_RULES', "#{dir}/before.rules")
      File.write("#{dir}/ufw.conf", "ENABLED=yes\n")
      File.write("#{dir}/before.rules", before_rules)
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(AmahiHelper::UFW).and_return(true)
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) }.join(' ') && nil }
    end

    after { FileUtils.rm_rf(dir) }

    it 'takes two different real interfaces, the firewall on, and forwards to private addresses' do
      allow(helper).to receive(:installed!).and_call_original
      allow(helper).to receive(:installed!).with(AmahiHelper::NETPLAN).and_return(true)
      args = { 'lan' => 'lo', 'wan' => 'lo', 'forwards' => [] }
      expect(refusal('network.router_on', args)).to include('must differ')
      real = Socket.getifaddrs.map(&:name).uniq.find { |n| n != 'lo' } or skip 'no second interface here'
      args['wan'] = real
      expect(steps('network.router_on', args)).to eq([[:router_on, 'lo', real, []]])
      File.write("#{dir}/ufw.conf", "ENABLED=no\n")
      expect(refusal('network.router_on', args)).to include('firewall must be on')
      File.write("#{dir}/ufw.conf", "ENABLED=yes\n")
      [[{ 'protocol' => 'tcp', 'port' => 8080, 'address' => '10.99.0.60', 'to_port' => 80 }], []].each do |list|
        expect(refusal('network.router_on', args.merge('forwards' => list))).to be_nil
      end
      [{ 'protocol' => 'icmp', 'port' => 1, 'address' => '10.0.0.1', 'to_port' => 1 },
       { 'protocol' => 'tcp', 'port' => 0, 'address' => '10.0.0.1', 'to_port' => 1 },
       { 'protocol' => 'tcp', 'port' => '80', 'address' => '10.0.0.1', 'to_port' => 80 },
       { 'protocol' => 'tcp', 'port' => 80, 'address' => '8.8.8.8', 'to_port' => 80 },
       { 'protocol' => 'tcp', 'port' => 80, 'address' => 'nas', 'to_port' => 80 }].each do |bad|
        expect(refusal('network.router_on', args.merge('forwards' => [bad]))).not_to be_nil, bad.inspect
      end
      expect(steps('network.router_off', {})).to eq([[:router_off]])
    end

    it "puts the internet interface's address, forwarding, the NAT block and the rules in place" do
      helper.do_router_on('ens19', 'ens20', forwards)
      expect(File.read(AmahiHelper::WAN_NETPLAN)).to include('    ens20:', 'dhcp4: true', 'dhcp6: false', 'route-metric: 50')
      expect(File.stat(AmahiHelper::WAN_NETPLAN).mode & 0o777).to eq(0o600)
      expect(File.read(AmahiHelper::ROUTER_SYSCTL)).to eq("net.ipv4.ip_forward = 1\n")
      rules = File.read(AmahiHelper::UFW_BEFORE_RULES)
      expect(rules).to start_with("# rules.before\n# BEGIN amahi-kai router\n*nat\n")
      expect(rules).to include('-A PREROUTING -i ens20 -p tcp --dport 8080 -j DNAT --to-destination 10.99.0.60:80',
                               '-A POSTROUTING -o ens20 -j MASQUERADE', "COMMIT\n# END amahi-kai router\n*filter\n")
      expect(rules).to end_with(before_rules.delete_prefix("# rules.before\n"))
      expect(ran).to eq(["#{AmahiHelper::NETPLAN} generate", "#{AmahiHelper::NETPLAN} apply", '/usr/sbin/sysctl -q -w net.ipv4.ip_forward=1',
                         '/usr/sbin/ufw route allow in on ens19 out on ens20',
                         '/usr/sbin/ufw route allow in on ens20 out on ens19 to 10.99.0.60 port 80 proto tcp',
                         '/usr/sbin/ufw insert 1 deny in on ens20', '/usr/sbin/ufw reload'])
      expect(JSON.parse(File.read(AmahiHelper::ROUTER_STATE))).to eq('lan' => 'ens19', 'wan' => 'ens20',
                                                                      'forwards' => [{ 'protocol' => 'tcp', 'port' => 8080, 'address' => '10.99.0.60', 'to_port' => 80 }])
    end

    it 'takes the old rules out before putting changed ones in, and the block out of before.rules once' do
      helper.do_router_on('ens19', 'ens20', forwards)
      ran.clear
      helper.do_router_on('ens19', 'ens21', [])
      expect(ran).to include('/usr/sbin/ufw delete deny in on ens20', '/usr/sbin/ufw route delete allow in on ens19 out on ens20',
                             '/usr/sbin/ufw route delete allow in on ens20 out on ens19 to 10.99.0.60 port 80 proto tcp',
                             '/usr/sbin/ufw route allow in on ens19 out on ens21', '/usr/sbin/ufw insert 1 deny in on ens21')
      rules = File.read(AmahiHelper::UFW_BEFORE_RULES)
      expect(rules.scan('BEGIN amahi-kai router').size).to eq(1)
      expect(rules).to include('-o ens21 -j MASQUERADE')
      expect(rules).not_to include('ens20', 'DNAT')
    end

    it "refuses a netplan file netplan won't take, and leaves nothing behind" do
      allow(helper).to receive(:run_command) { |argv| raise AmahiHelper::Failed, 'netplan exited 1' if argv[1] == 'generate' }
      expect { helper.do_router_on('ens19', 'ens20', []) }.to raise_error(AmahiHelper::Failed, /netplan exited 1/)
      expect(File.exist?(AmahiHelper::WAN_NETPLAN)).to be false
      expect(File.exist?(AmahiHelper::ROUTER_STATE)).to be false
    end

    it 'takes everything out again, the interface address included' do
      helper.do_router_on('ens19', 'ens20', forwards)
      ran.clear
      helper.do_router_off
      expect(ran).to eq(['/usr/sbin/ufw delete deny in on ens20', '/usr/sbin/ufw route delete allow in on ens19 out on ens20',
                         '/usr/sbin/ufw route delete allow in on ens20 out on ens19 to 10.99.0.60 port 80 proto tcp', '/usr/sbin/ufw reload',
                         '/usr/sbin/sysctl -q -w net.ipv4.ip_forward=0', "#{AmahiHelper::NETPLAN} apply", "#{AmahiHelper::IP} -4 addr flush dev ens20"])
      expect(File.read(AmahiHelper::UFW_BEFORE_RULES)).to eq(before_rules)
      expect(%w[WAN_NETPLAN ROUTER_SYSCTL ROUTER_STATE].map { |c| File.exist?(AmahiHelper.const_get(c)) }).to all(be false)
      ran.clear
      helper.do_router_off # nothing in place: nothing to do
      expect(ran).to be_empty
    end

    it "leaves the internet interface out of the apps' LAN subnets while the NAS is the router" do
      allow(helper).to receive(:capture).with([AmahiHelper::IP, '-j', '-4', 'addr', 'show']).and_return(JSON.generate([
        { 'ifname' => 'ens19', 'addr_info' => [{ 'local' => '10.99.0.1', 'prefixlen' => 24 }] },
        { 'ifname' => 'ens20', 'addr_info' => [{ 'local' => '10.77.0.134', 'prefixlen' => 24 }] }
      ]))
      expect(helper.lan_subnets).to eq(['10.99.0.0/24', '10.77.0.0/24'])
      File.write(AmahiHelper::ROUTER_STATE, JSON.generate('lan' => 'ens19', 'wan' => 'ens20', 'forwards' => []))
      expect(helper.lan_subnets).to eq(['10.99.0.0/24'])
    end
  end

  # Every drive check reads lsblk's tree. lsblk only nests partitions and volumes under their
  # disk with NAME as the first column; with PATH first it listed every device flat, so a disk
  # seemed to have nothing mounted from it and the system disk passed the checks.
  describe 'the device tree' do
    it "reads this machine's lsblk as a tree: partitions and volumes under their disk" do
      skip 'no lsblk here' unless File.executable?('/usr/bin/lsblk')
      tree = helper.block_tree
      expect(tree.map { |node| node['type'] }).not_to include('part', 'lvm')
      root_disk = tree.find { |disk| helper.mountpoints(disk).include?('/') }
      skip "/ isn't on a disk the helper manages here" unless root_disk && root_disk['path'].match?(AmahiHelper::DISK_DEVICE)
      expect(refusal('disks.format', { 'device' => root_disk['path'] })).to include('on a disk the system uses')
    end

    it 'refuses a flat list rather than read it' do
      flat = { 'blockdevices' => [{ 'path' => '/dev/sda', 'type' => 'disk', 'mountpoints' => [nil] },
                                  { 'path' => '/dev/sda1', 'type' => 'part', 'mountpoints' => ['/'] }] }.to_json
      allow(helper).to receive(:capture).with(%w[/usr/bin/lsblk -J -o NAME,PATH,TYPE,FSTYPE,MOUNTPOINTS]).and_return(flat)
      expect { helper.block_tree }.to raise_error(AmahiHelper::Failed, 'lsblk listed /dev/sda1 on its own, not under its disk')
    end
  end

  describe 'data drives' do
    # sda: the OS disk. sdb: a data drive mounted under /mnt. sdc: a disk used only for
    # swap. sdd: an unmounted data drive. nvme0n1: an unmounted NVMe drive.
    let(:tree) do
      [{ 'path' => '/dev/sda', 'type' => 'disk', 'mountpoints' => [nil],
         'children' => [{ 'path' => '/dev/sda1', 'type' => 'part', 'mountpoints' => ['/boot/efi'] },
                        { 'path' => '/dev/sda2', 'type' => 'part', 'mountpoints' => [nil],
                          'children' => [{ 'path' => '/dev/mapper/vg-root', 'type' => 'lvm', 'mountpoints' => ['/'] }] }] },
       { 'path' => '/dev/sdb', 'type' => 'disk', 'mountpoints' => [nil],
         'children' => [{ 'path' => '/dev/sdb1', 'type' => 'part', 'mountpoints' => ['/mnt/storage-1'] }] },
       { 'path' => '/dev/sdc', 'type' => 'disk', 'mountpoints' => [nil],
         'children' => [{ 'path' => '/dev/sdc1', 'type' => 'part', 'mountpoints' => ['[SWAP]'] }] },
       { 'path' => '/dev/sdd', 'type' => 'disk', 'mountpoints' => [nil],
         'children' => [{ 'path' => '/dev/sdd1', 'type' => 'part', 'mountpoints' => [nil] }] },
       { 'path' => '/dev/nvme0n1', 'type' => 'disk', 'mountpoints' => [nil],
         'children' => [{ 'path' => '/dev/nvme0n1p1', 'type' => 'part', 'mountpoints' => [nil] }] }]
    end
    let(:dir) { Dir.mktmpdir }
    let(:mnt) { "#{dir}/mnt" }
    let(:fstab) { "#{dir}/fstab" }

    before do
      Dir.mkdir(mnt)
      File.write(fstab, "UUID=os / ext4 defaults 0 1\n")
      stub_const('AmahiHelper::MNT', mnt)
      stub_const('AmahiHelper::FSTAB', fstab)
      # The tree's data drive is mounted under the stubbed /mnt.
      tree[1]['children'][0]['mountpoints'] = ["#{mnt}/storage-1"]
      allow(helper).to receive(:block_tree).and_return(tree)
      allow(File).to receive(:blockdev?).and_call_original
      allow(File).to receive(:blockdev?).with(a_string_starting_with('/dev/')).and_return(true)
      allow(helper).to receive(:probe).and_return('TYPE' => 'ext4', 'UUID' => 'u-1')
    end

    after { FileUtils.rm_rf(dir) }

    it 'formats an unmounted data drive as ext4' do
      expect(steps('disks.format', { 'device' => '/dev/sdd1' }))
        .to eq([%w[/usr/sbin/mkfs.ext4 -F /dev/sdd1], ['/usr/bin/udevadm', 'settle', { allow_failure: true }]])
      expect(steps('disks.format', { 'device' => '/dev/nvme0n1' })).to start_with(%w[/usr/sbin/mkfs.ext4 -F /dev/nvme0n1])
    end

    it 'refuses any drive the system uses, whole disk or partition' do
      %w[/dev/sda /dev/sda1 /dev/sda2 /dev/sdc /dev/sdc1].each do |device|
        expect(refusal('disks.format', { 'device' => device })).to include('on a disk the system uses'), device
      end
    end

    it 'refuses a mounted data drive' do
      expect(refusal('disks.format', { 'device' => '/dev/sdb1' })).to eq("/dev/sdb1 is mounted at #{mnt}/storage-1; unmount it first")
      expect(refusal('disks.format', { 'device' => '/dev/sdb' })).to include('unmount it first')
    end

    describe 'drive temperatures' do
      let(:ata) do
        <<~OUT
          ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
            9 Power_On_Hours          0x0032   095   095   000    Old_age   Always       -       21854
          190 Airflow_Temperature_Cel 0x0022   066   051   000    Old_age   Always       -       34
          194 Temperature_Celsius     0x0022   064   045   000    Old_age   Always       -       36 (Min/Max 18/55)
        OUT
      end
      let(:outputs) do
        { '/dev/sda' => ata, '/dev/sdb' => "Current Drive Temperature:     41 C\n",
          '/dev/sdc' => "190 Airflow_Temperature_Cel 0x0022   070   045   045    Old_age   Always       -       30\n",
          '/dev/sdd' => "Smartctl open device: /dev/sdd failed: SMART not supported\n",
          '/dev/nvme0n1' => "Temperature:                        44 Celsius\nTemperature Sensor 1: 48 Celsius\n" }
      end

      before do
        allow(Open3).to receive(:capture3) do |_env, _cmd, *args, **_opts|
          [outputs.fetch(args.last), '', instance_double(Process::Status, success?: false)]
        end
      end

      it 'takes no arguments and plans one read-only action' do
        expect(steps('disks.temperatures', {})).to eq([[:drive_temperatures]])
        expect(refusal('disks.temperatures', { 'device' => '/dev/sda; reboot' })).to eq('unexpected argument device')
      end

      it 'reads every whole disk lsblk lists, through timeout, whatever smartctl exits with' do
        reply = helper.do_drive_temperatures
        expect(reply['temperatures']).to eq('/dev/sda' => 36, '/dev/sdb' => 41, '/dev/sdc' => 30,
                                            '/dev/sdd' => nil, '/dev/nvme0n1' => 44)
        expect(Open3).to have_received(:capture3)
          .with(AmahiHelper::ENV_MIN, ['/usr/bin/timeout', '/usr/bin/timeout'], '5', '/usr/sbin/smartctl', '-A', '/dev/sda',
                unsetenv_others: true, chdir: '/')
      end

      it 'reports nil when smartctl is missing' do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
        expect(helper.do_drive_temperatures['temperatures'].values.uniq).to eq([nil])
      end
    end

    it 'refuses names that are not disks or partitions, missing devices and ones lsblk does not list' do
      ['/dev/sdd1; reboot', '/dev/loop0', '/dev/mapper/vg-root', '/dev/sdd1/../sda1', 'sdd1', '/dev/md0', ''].each do |device|
        expect(refusal('disks.format', { 'device' => device })).not_to be_nil, device.inspect
      end
      allow(File).to receive(:blockdev?).with('/dev/sdz').and_return(false)
      expect(refusal('disks.format', { 'device' => '/dev/sdz' })).to eq("/dev/sdz doesn't exist")
      expect(refusal('disks.format', { 'device' => '/dev/sdq' })).to eq("lsblk doesn't list /dev/sdq")
    end

    it 'mounts a data drive at /mnt/<name> by UUID' do
      expect(steps('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/storage-2" }))
        .to eq([[:mount_drive, '/dev/sdd1', "#{mnt}/storage-2", 'ext4', 'u-1']])
    end

    it 'mounts only filesystems it knows' do
      allow(helper).to receive(:probe).and_return({})
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/a" })).to include('has no filesystem; format it first')
      allow(helper).to receive(:probe).and_return('TYPE' => 'crypto_LUKS')
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/a" })).to include("which Amahi-kai doesn't mount")
    end

    it 'refuses mount points outside /mnt, nested, hidden, in use or taken in fstab' do
      ['/etc', "#{mnt}/../etc", "#{mnt}/a/b", "#{mnt}/.a", "#{mnt}/", mnt, "#{mnt}/a b"].each do |mp|
        expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => mp })).to include('must be'), mp
      end
      File.write("#{mnt}/file", 'x')
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/file" })).to include('is not a folder')
      File.symlink('/etc', "#{mnt}/link")
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/link" })).to include('is not a folder')
      FileUtils.mkdir_p("#{mnt}/full/data")
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/full" })).to include("isn't empty")
      allow(helper).to receive(:mount_point?).and_return(true)
      Dir.mkdir("#{mnt}/busy")
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/busy" })).to include('already a mount point')
    end

    it "refuses a mount point fstab gives another drive, but takes back the drive's own" do
      File.write(fstab, "UUID=other #{mnt}/storage-2 ext4 defaults 0 2\nUUID=u-1 #{mnt}/storage-3 ext4 defaults 0 2\n")
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/storage-2" }))
        .to eq("#{mnt}/storage-2 belongs to another drive in /etc/fstab (UUID=other)")
      expect(refusal('disks.mount', { 'device' => '/dev/sdd1', 'mount_point' => "#{mnt}/storage-3" })).to be_nil
    end

    it 'unmounts a mounted data drive' do
      expect(steps('disks.unmount', { 'device' => '/dev/sdb1' })).to eq([[:unmount_drive, ["#{mnt}/storage-1"], 'u-1']])
      expect(refusal('disks.unmount', { 'device' => '/dev/sdd1' })).to eq("/dev/sdd1 isn't mounted")
      expect(refusal('disks.unmount', { 'device' => '/dev/sda1' })).to include('on a disk the system uses')
    end

    it 'previews an unmounted data drive' do
      expect(steps('disks.preview', { 'device' => '/dev/sdd1' })).to eq([[:preview_drive, '/dev/sdd1', 'ext4']])
      expect(refusal('disks.preview', { 'device' => '/dev/sdb1' })).to include('unmount it first')
    end

    it "won't unmount, preview or format a drive an app's container still has mounted, and names the app" do
      allow(helper).to receive(:drive_holders).and_return(['amahi-bittube'])
      expect(refusal('disks.unmount', { 'device' => '/dev/sdb1' }))
        .to eq('/dev/sdb1 is still in use by the app bittube, which has folders on it mounted: restart or stop it on Apps, then unmount it')
      expect(refusal('disks.preview', { 'device' => '/dev/sdd1' })).to end_with('then preview it')
      expect(refusal('disks.format', { 'device' => '/dev/sdd1' })).to end_with('then format it')
    end

    it "finds the containers that have a drive mounted in their own view of the mounts" do
      stat = instance_double(File::Stat, blockdev?: true, rdev_major: 8, rdev_minor: 16)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with('/dev/sdb').and_return(stat)
      id = 'a' * 64
      allow(helper).to receive(:system_peer_groups).and_return(%w[45 46])
      allow(helper).to receive(:other_mount_views).and_return(
        [{ mountinfo: "505 456 8:16 /Test /mnt/storage-2/Test ro - ext4 /dev/sdb rw\n", cgroup: "0::/system.slice/docker-#{id}.scope\n", comm: 'bittube' },
         { mountinfo: "12 1 8:0 / /mnt/storage-1 rw - ext4 /dev/sda rw\n", cgroup: "0::/x\n", comm: 'other' },
         # a service systemd sandboxes: its copy follows the system's mount, so an unmount takes it along
         { mountinfo: "133 111 8:16 / /mnt/storage-2 ro,nosuid shared:179 master:45 - ext4 /dev/sdb rw\n",
           cgroup: "0::/system.slice/systemd-logind.service\n", comm: 'systemd-logind' }]
      )
      allow(helper).to receive(:container_names).and_return(id => 'amahi-bittube')
      expect(helper.drive_holders('/dev/sdb')).to eq(['amahi-bittube'])
      allow(helper).to receive(:container_names).and_return({})
      expect(helper.drive_holders('/dev/sdb')).to eq(['bittube']) # no container by that id: its program
      allow(helper).to receive(:other_mount_views).and_return([])
      expect(helper.drive_holders('/dev/sdb')).to eq([])
    end

    describe 'disks.secure_mounts' do
      let(:files) { "#{dir}/files" }
      let(:ours) { "UUID=u-1 #{mnt}/storage-1 ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2\n" }
      let(:theirs) { "UUID=u-2 #{mnt}/media ext4 defaults,nofail 0 2\n" }
      let(:done) { "UUID=u-3 #{mnt}/storage-3 ext4 defaults,nofail,nosuid,nodev,x-systemd.device-timeout=10s 0 2\n" }

      before do
        Dir.mkdir(files)
        stub_const('AmahiHelper::SHARE_ROOT', files)
        stub_const('AmahiHelper::SHARE_ROOT_FSTAB', "#{files} #{files} none bind,nosuid,nodev 0 0")
        stub_const('AmahiHelper::RUN_DIR', dir)
        File.write(fstab, "UUID=os / ext4 defaults 0 1\n#{ours}#{theirs}#{done}")
        File.chmod(0o644, fstab)
      end

      it 'plans the fstab change, then the remounts' do
        expect(steps('disks.secure_mounts', {})).to eq([[:secure_fstab], [:secure_mounts]])
      end

      it "gives the lines it wrote nosuid,nodev once, leaves others alone, binds the share root, and keeps a backup" do
        before = File.read(fstab)
        expect(helper.do_secure_fstab).to eq('fstab_changed' => 2)
        expect(File.read(fstab)).to eq(
          "UUID=os / ext4 defaults 0 1\nUUID=u-1 #{mnt}/storage-1 ext4 defaults,nofail,nosuid,nodev,x-systemd.device-timeout=10s 0 2\n" \
          "#{theirs}#{done}#{files} #{files} none bind,nosuid,nodev 0 0\n"
        )
        expect(File.read("#{fstab}.amahi-backup")).to eq(before)
        expect(File.stat(fstab).mode & 0o777).to eq(0o644)
        after = File.read(fstab)
        expect(helper.do_secure_fstab).to eq('fstab_changed' => 0)
        expect(File.read(fstab)).to eq(after)
      end

      it 'refuses a new fstab that would not parse, and keeps the old one' do
        allow(helper).to receive(:fstab_entries).and_return([]) # as if the bind line were missing
        stub_const('AmahiHelper::SHARE_ROOT_FSTAB', "#{files} #{files}")
        expect { helper.do_secure_fstab }.to raise_error(AmahiHelper::Failed, /bad line/)
        expect(File.read(fstab)).to include(ours)
      end

      it "refuses a new fstab that findmnt finds new errors in" do
        skip 'findmnt is not installed' unless File.executable?(AmahiHelper::FINDMNT)
        stub_const('AmahiHelper::SHARE_ROOT_FSTAB', "#{files} #{dir}/nowhere none bind,nosuid,nodev 0 0")
        expect { helper.do_secure_fstab }.to raise_error(AmahiHelper::Failed, /errors the old one didn't/)
        expect(File.read(fstab)).to include(ours)
      end

      it 'remounts the drives whose lines have the options but whose mounts lack them, and binds the share root' do
        ran = []
        live = { "#{mnt}/storage-1" => %w[rw relatime], "#{mnt}/storage-3" => %w[rw nosuid nodev relatime] }
        allow(helper).to receive(:mount_options) { |path| live.fetch(path, []) }
        allow(helper).to receive(:mount_point?) { |path| live.key?(path) }
        allow(helper).to receive(:run_command) do |argv|
          ran << argv
          live[argv.last] = %w[rw relatime] if argv[1] == '--bind'
          live[argv.last] = %w[rw nosuid nodev relatime] if argv[1] == '-o'
          nil
        end
        helper.do_secure_fstab
        expect(helper.do_secure_mounts).to eq('remounted' => ["#{mnt}/storage-1", files], 'protected' => [])
        expect(ran).to eq([['/usr/bin/mount', '-o', 'remount,nosuid,nodev', "#{mnt}/storage-1"],
                           ['/usr/bin/mount', '--bind', files, files],
                           ['/usr/bin/mount', '-o', 'remount,bind,nosuid,nodev', files]])
        ran.clear
        expect(helper.do_secure_mounts).to eq('remounted' => [], 'protected' => [])
        expect(ran).to eq([])
      end

      it "makes a missing drive's empty mount point immutable, so nothing lands on the system disk there" do
        ran = []
        allow(helper).to receive(:mount_options) { |path| path == files ? %w[rw nosuid nodev] : [] }
        allow(helper).to receive(:mount_point?).and_return(false)
        allow(helper).to receive(:run_command) { |argv| ran << argv && nil }
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(AmahiHelper::CHATTR).and_return(true)
        File.write(fstab, "UUID=os / ext4 defaults 0 1\nUUID=u-1 #{mnt}/storage-1 ext4 defaults,nofail,nosuid,nodev 0 2\n" \
                          "UUID=u-2 #{mnt}/storage-2 ext4 defaults,nofail,nosuid,nodev 0 2\n")
        FileUtils.mkdir_p(["#{mnt}/storage-1", "#{mnt}/storage-2/.gh_metastore_backup"])
        File.write("#{mnt}/storage-2/.gh_metastore_backup/backup", 'x') # Greyhole's folder, not empty
        expect(helper.do_secure_mounts['protected']).to eq(["#{mnt}/storage-1"])
        expect(ran).to include([AmahiHelper::CHATTR, '+i', "#{mnt}/storage-1", { allow_failure: true }])
        expect(ran.flatten).not_to include("#{mnt}/storage-2")
        expect(File.exist?("#{mnt}/storage-2/.gh_metastore_backup/backup")).to be true

        # Greyhole's folder empty, as its job remakes it every minute: it goes, and the folder is protected
        File.delete("#{mnt}/storage-2/.gh_metastore_backup/backup")
        expect(helper.do_secure_mounts['protected']).to include("#{mnt}/storage-2")
        expect(Dir.empty?("#{mnt}/storage-2")).to be true

        # Anything else there stays, and the folder isn't protected
        FileUtils.mkdir_p("#{mnt}/storage-3/.gh_metastore_backup")
        File.write("#{mnt}/storage-3/notes.txt", 'mine')
        File.write(fstab, "UUID=u-3 #{mnt}/storage-3 ext4 defaults,nofail,nosuid,nodev 0 2\n")
        expect(helper.do_secure_mounts['protected']).to eq([])
        expect(Dir.children("#{mnt}/storage-3").sort).to eq(%w[.gh_metastore_backup notes.txt])
      end

      it 'reads a mount\'s options from the mounts list, the newest first' do
        mounts = "#{dir}/mounts"
        File.write(mounts, "/dev/sda2 / ext4 rw,relatime 0 0\n/dev/sda2 #{files} ext4 rw,relatime 0 0\n/dev/sda2 #{files} ext4 rw,nosuid,nodev,relatime 0 0\n")
        expect(helper.mount_options(files, mounts)).to eq(%w[rw nosuid nodev relatime])
        expect(helper.mount_options("#{mnt}/none", mounts)).to eq([])
      end
    end

    describe 'mounting and unmounting' do
      let(:ran) { [] }
      let(:mounted) { [] }

      before do
        allow(helper).to receive(:run_command) do |argv|
          ran << argv
          path = argv.grep(String).last
          mounted << path if argv.first == '/usr/bin/mount'
          mounted.delete(path) if argv.first == '/usr/bin/umount'
          nil
        end
        allow(helper).to receive(:mount_point?) { |path| mounted.include?(path) }
      end

      it 'mounts, and adds the PR #13 fstab line (nofail, short timeout) once' do
        mp = "#{mnt}/storage-2"
        expect(helper.do_mount_drive('/dev/sdd1', mp, 'ext4', 'u-1')).to eq('mount_point' => mp)
        expect(ran).to eq([[AmahiHelper::CHATTR, '+i', mp, { allow_failure: true }], # its empty folder, before
                           ['/usr/bin/mount', '-o', 'nosuid,nodev', '/dev/sdd1', mp]])
        expect(File.read(fstab).lines.last).to eq("UUID=u-1 #{mp} ext4 defaults,nofail,nosuid,nodev,x-systemd.device-timeout=10s 0 2\n")

        mounted.clear
        helper.do_mount_drive('/dev/sdd1', mp, 'ext4', 'u-1')
        expect(File.read(fstab).scan('UUID=u-1').size).to eq(1)
      end

      it 'mounts NTFS with ntfs-3g' do
        helper.do_mount_drive('/dev/sdd1', "#{mnt}/win", 'ntfs', 'A1B2')
        expect(ran.last).to eq(['/usr/bin/mount', '-t', 'ntfs-3g', '-o', 'nosuid,nodev', '/dev/sdd1', "#{mnt}/win"])
        expect(File.read(fstab)).to include("UUID=A1B2 #{mnt}/win ntfs-3g defaults,nofail")
      end

      it 'removes the folder it made and leaves fstab alone when the mount fails' do
        allow(helper).to receive(:run_command).and_raise(AmahiHelper::Failed, 'mount exited 32: wrong fs type')
        expect { helper.do_mount_drive('/dev/sdd1', "#{mnt}/storage-2", 'ext4', 'u-1') }.to raise_error(AmahiHelper::Failed)
        expect(File.exist?("#{mnt}/storage-2")).to be false
        expect(File.read(fstab)).to eq("UUID=os / ext4 defaults 0 1\n")
      end

      it "unmounts, removes only the drive's fstab line (keeping a backup) and its empty storage folder" do
        Dir.mkdir("#{mnt}/storage-1")
        Dir.mkdir("#{mnt}/media")
        mounted.push("#{mnt}/storage-1", "#{mnt}/media")
        before = "UUID=os / ext4 defaults 0 1\nUUID=u-1 #{mnt}/storage-1 ext4 defaults,nofail 0 2\n" \
                 "UUID=u-12 #{mnt}/media ext4 defaults,nofail 0 2\n"
        File.write(fstab, before)
        File.chmod(0o644, fstab)

        helper.do_unmount_drive(["#{mnt}/storage-1"], 'u-1')
        helper.do_unmount_drive(["#{mnt}/media"], nil)

        expect(ran).to eq([['/usr/bin/umount', "#{mnt}/storage-1"], [AmahiHelper::CHATTR, '-i', "#{mnt}/storage-1", { allow_failure: true }],
                           ['/usr/bin/umount', "#{mnt}/media"]])
        expect(File.read(fstab)).to eq("UUID=os / ext4 defaults 0 1\nUUID=u-12 #{mnt}/media ext4 defaults,nofail 0 2\n")
        expect(File.stat(fstab).mode & 0o777).to eq(0o644)
        expect(File.read("#{fstab}.amahi-backup")).to eq(before)
        expect(File.exist?("#{mnt}/storage-1")).to be false
        expect(File.directory?("#{mnt}/media")).to be true
      end

      it 'previews read-only without replaying the journal, then unmounts and cleans up' do
        stub_const('AmahiHelper::RUN_DIR', dir)
        reply = helper.do_preview_drive('/dev/sdd1', 'ext4')
        mount, umount = ran
        expect(mount.first(3)).to eq(['/usr/bin/mount', '-o', 'ro,nosuid,nodev,noexec,noload'])
        expect(mount[3]).to eq('/dev/sdd1')
        expect(umount.first(2)).to eq(['/usr/bin/umount', mount[4]])
        expect(File.exist?(mount[4])).to be false
        expect(reply).to include('entries' => [], 'partial' => false)
      end
    end

    it 'sums the top level of a drive, skipping hidden entries and lost+found' do
      FileUtils.mkdir_p("#{dir}/top/Movies/sub")
      File.write("#{dir}/top/Movies/a.mkv", 'x' * 100)
      File.write("#{dir}/top/Movies/sub/b.mkv", 'x' * 50)
      File.write("#{dir}/top/notes.txt", 'x' * 7)
      FileUtils.mkdir_p("#{dir}/top/lost+found")
      File.write("#{dir}/top/.hidden", 'x')

      summary = helper.directory_summary("#{dir}/top")

      expect(summary['entries']).to eq([{ 'name' => 'Movies', 'type' => 'directory', 'size' => 150, 'file_count' => 2 },
                                        { 'name' => 'notes.txt', 'type' => 'file', 'size' => 7, 'file_count' => 1 }])
      expect(summary).to include('total_used' => 157, 'file_count' => 3, 'partial' => false)

      stub_const('AmahiHelper::PREVIEW_LIMIT', { entries: 1, seconds: 30 })
      expect(helper.directory_summary("#{dir}/top")['partial']).to be true
    end
  end

  describe 'Greyhole' do
    let(:conf) do
      "# Greyhole configuration - generated by Amahi-kai\n\ndb_host = localhost\ndb_user = amahi\ndb_pass = s3cret pass\n" \
        "db_name = greyhole\n\nstorage_pool_drive = /mnt/storage-1, min_free: 10gb\n" \
        "storage_pool_drive = /mnt/media/pool, min_free: 0gb\n\nnum_copies[Movies [HD]] = 2\nnum_copies[Backups] = max"
    end

    it 'installs the config root:amahi 0640, since it holds the database password, and a copy without it for anyone' do
      pool = "# Greyhole configuration - generated by Amahi-kai\n\n\nstorage_pool_drive = /mnt/storage-1, min_free: 10gb\n" \
             "storage_pool_drive = /mnt/media/pool, min_free: 0gb\n\nnum_copies[Movies [HD]] = 2\nnum_copies[Backups] = max"
      expect(steps('greyhole.write_config', { 'content' => conf }))
        .to eq([[:install, '/etc/greyhole.conf', conf, nil, '0640', 'amahi'],
                [:install, '/etc/amahi-kai/greyhole-pool.conf', pool, nil, '0644']])
    end

    it "keeps the copy without the password up to date when Samba's config is written" do
      file = Tempfile.new('greyhole.conf')
      File.write(file.path, conf)
      stub_const('AmahiHelper::GREYHOLE_CONF', file.path)
      allow(helper).to receive(:do_install)
      helper.do_refresh_greyhole_pool
      expect(helper).to have_received(:do_install).with('/etc/amahi-kai/greyhole-pool.conf', satisfy { |text| text.include?('storage_pool_drive') && !text.include?('db_') }, nil, '0644')
      stub_const('AmahiHelper::GREYHOLE_CONF', '/nonexistent/greyhole.conf')
      helper.do_refresh_greyhole_pool
      expect(helper).to have_received(:do_install).once
    ensure
      file&.close!
    end

    it "takes the usage report to greyhole.net out of Greyhole's weekly job, keeping its file check" do
      Dir.mktmpdir do |dir|
        cron = "#{dir}/greyhole"
        stub_const('AmahiHelper::GREYHOLE_WEEKLY_CRON', cron)
        helper.do_stop_greyhole_stats # no job: nothing to do
        expect(File.exist?(cron)).to be false
        File.write(cron, <<~CRON)
          #!/bin/sh

          # Weekly fsck
          /usr/bin/greyhole --fsck --email-report --dont-walk-metadata-store --disk-usage-report > /dev/null

          # This calls home to report anonymous data about Greyhole usage.
          # It sends the output of 'greyhole --stats' to the greyhole.net server.
          # Please leave this here... We use it to get usage stats for Greyhole.
          /usr/bin/greyhole --getuid > /tmp/greyhole.stats ; /usr/bin/greyhole --stats --json >> /tmp/greyhole.stats; curl -s --data @/tmp/greyhole.stats https://www.greyhole.net/usage_stats.php > /dev/null ; rm /tmp/greyhole.stats
        CRON
        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
        helper.do_stop_greyhole_stats
        expect(File.read(cron)).to eq(<<~CRON)
          #!/bin/sh

          # Weekly fsck
          /usr/bin/greyhole --fsck --email-report --dont-walk-metadata-store --disk-usage-report > /dev/null

          # Amahi-kai took out the weekly report of Greyhole's usage stats to greyhole.net.
        CRON
        expect(helper).to have_received(:do_install).with(cron, anything, nil, '0755').once
        helper.do_stop_greyhole_stats # already done
        expect(helper).to have_received(:do_install).once
      end
    end

    it 'refuses lines Amahi-kai does not write, and pool drives outside /mnt' do
      ['df_command = rm -rf /', 'log_to_stderr = yes', 'db_host = db.example.com', 'db_user = root', 'include = /etc/shadow',
       'storage_pool_drive = /, min_free: 10gb', 'storage_pool_drive = /etc, min_free: 10gb',
       'storage_pool_drive = /mnt/../etc, min_free: 10gb', 'num_copies[x] = 2; df_command = y'].each do |line|
        expect(refusal('greyhole.write_config', { 'content' => "#{line}\n" })).to include('is not one Amahi-kai writes'), line
      end
      expect(refusal('greyhole.write_config', { 'content' => "storage_pool_drive = /mnt/a/../../etc, min_free: 1gb\n" }))
        .to include('must be a normalized path')
    end

    it 'keeps the database password out of refusals and logs' do
      expect(refusal('greyhole.write_config', { 'content' => "db_pass = hunter2\tx\n" })).to eq('greyhole.conf line "db_pass = ..." is not one Amahi-kai writes')
      expect(helper.describe([:install, '/etc/greyhole.conf', conf, nil, '0640', 'amahi']).to_s).not_to include('s3cret')
    end

    it "tells Greyhole to use the drive mounted at one of its folders, and won't unmount its drives" do
      conf = Tempfile.new('greyhole.conf')
      stub_const('AmahiHelper::GREYHOLE_CONF', conf.path)
      File.write(conf.path, "storage_pool_drive = /mnt/storage-1, min_free: 10gb\nstorage_pool_drive = /mnt/storage-2, min_free: 10gb\n")
      allow(AmahiHelper).to receive(:installed!).and_return(true)
      allow(AmahiHelper).to receive(:mount_point?).and_return(false)
      expect(refusal('greyhole.replace_drive', { 'path' => '/etc' })).to eq("/etc isn't one of Greyhole's drives")
      expect(refusal('greyhole.replace_drive', { 'path' => '/mnt/storage-1' }))
        .to eq('nothing is mounted at /mnt/storage-1: mount the drive on Disks → Devices first')
      allow(AmahiHelper).to receive(:mount_point?).with('/mnt/storage-1').and_return(true)
      expect(steps('greyhole.replace_drive', { 'path' => '/mnt/storage-1' })).to eq([['/usr/bin/greyhole', '--replaced=/mnt/storage-1']])

      expect(steps('greyhole.remove_drive', { 'path' => '/mnt/storage-1', 'available' => true }))
        .to eq([['/usr/bin/greyhole', '--remove=/mnt/storage-1', { stdin: "yes\n" }]])
      expect(steps('greyhole.remove_drive', { 'path' => '/mnt/storage-2', 'available' => false }))
        .to eq([['/usr/bin/greyhole', '--remove=/mnt/storage-2', { stdin: "no\n" }]])
      expect(refusal('greyhole.remove_drive', { 'path' => '/mnt/storage-2', 'available' => true }))
        .to eq('nothing is mounted at /mnt/storage-2: mount the drive on Disks → Devices first')
      expect(refusal('greyhole.remove_drive', { 'path' => '/mnt/other', 'available' => false })).to eq("/mnt/other isn't one of Greyhole's drives")

      # Checking the pool takes nothing from the app
      expect(steps('greyhole.fsck', {})).to eq([['/usr/bin/greyhole', '--fsck', '--dont-walk-metadata-store']])

      allow(AmahiHelper).to receive(:probe).and_return('UUID' => 'u-1')
      allow(AmahiHelper).to receive(:data_device) { |device| [device, { 'path' => device, 'mountpoints' => ['/mnt/storage-2'] }] }
      expect(refusal('disks.unmount', { 'device' => '/dev/sdb' }))
        .to eq("/mnt/storage-2 is one of Greyhole's drives; remove it from the pool on Disks → Greyhole Pool first")
      allow(AmahiHelper).to receive(:data_device) { |device| [device, { 'path' => device, 'mountpoints' => ['/mnt/storage-3'] }] }
      expect(refusal('disks.unmount', { 'device' => '/dev/sdc' })).to be_nil
    ensure
      conf&.close!
    end

    describe 'taking a share out of the pool' do
      let(:dir) { Dir.mktmpdir }
      let(:folder) { "#{dir}/photos" }

      before do
        FileUtils.mkdir_p([folder, "#{dir}/drive/Photos"])
        File.write("#{dir}/drive/Photos/a.jpg", 'x' * 3000)
        File.symlink("#{dir}/drive/Photos/a.jpg", "#{folder}/a.jpg")
        File.write("#{folder}/landed.txt", 'x' * 500)
        File.write("#{dir}/greyhole.conf", "num_copies[Photos] = 2\nnum_copies[Odd's] = 1\n")
        stub_const('AmahiHelper::GREYHOLE_CONF', "#{dir}/greyhole.conf")
        allow(helper).to receive(:installed!).and_return(true)
        allow(helper).to receive(:samba_shares)
          .and_return('photos' => { name: 'Photos', path: folder, pooled: true }, "odd's" => { name: "Odd's", path: folder, pooled: true })
        allow(helper).to receive(:free_space).with(folder).and_return(10_000)
      end

      after { FileUtils.rm_rf(dir) }

      it 'has Greyhole move the files back when the folder has room for them, counting the ones on the drives' do
        expect(helper.folder_size(folder)).to eq(3500)
        expect(steps('greyhole.remove_share', { 'share' => 'Photos' })).to eq([['/usr/bin/greyhole', '--remove-share=Photos']])
        allow(helper).to receive(:free_space).with(folder).and_return(3000)
        expect(refusal('greyhole.remove_share', { 'share' => 'Photos' })).to start_with("the share's folder doesn't have room for its files")
      end

      it "refuses shares Greyhole doesn't pool, and names Greyhole can't take out safely" do
        expect(refusal('greyhole.remove_share', { 'share' => 'Movies' })).to eq("Movies isn't a share Greyhole pools")
        expect(refusal('greyhole.remove_share', { 'share' => "Odd's" })).to include('letters, digits, spaces, - and _')
        expect(refusal('greyhole.remove_share', { 'share' => nil })).to eq('share is missing')
      end
    end

    describe 'the pool trash' do
      let(:dir) { Dir.mktmpdir }
      let(:drives) { ["#{dir}/storage-1", "#{dir}/storage-2"] }
      let(:folder) { "#{dir}/photos" }

      before do
        drives.each do |drive|
          FileUtils.mkdir_p("#{drive}/.gh_trash/Photos/2026")
          File.write("#{drive}/.gh_trash/Photos/2026/beach [1].jpg", 'picture')
        end
        FileUtils.mkdir_p(folder)
        File.write("#{dir}/greyhole.conf", "num_copies[Photos] = 2\n")
        stub_const('AmahiHelper::GREYHOLE_CONF', "#{dir}/greyhole.conf")
        allow(helper).to receive(:greyhole_drives).and_return(drives)
        allow(helper).to receive(:installed!).and_return(true)
        allow(helper).to receive(:samba_shares).and_return('photos' => { name: 'Photos', path: folder, pooled: true })
      end

      after { FileUtils.rm_rf(dir) }

      it 'finds a file by share and path, every copy, reached through no link' do
        copies = drives.map { |d| "#{d}/.gh_trash/Photos/2026/beach [1].jpg" }
        expect(steps('greyhole.trash_delete', { 'share' => 'Photos', 'path' => '2026/beach [1].jpg' }))
          .to eq([[:remove_trash_copies, 'Photos', copies]])
        expect(steps('greyhole.trash_restore', { 'share' => 'Photos', 'path' => '2026/beach [1].jpg' }))
          .to eq([[:restore_from_trash, 'Photos', '2026/beach [1].jpg', copies]])
        expect(steps('greyhole.trash_empty', {})).to eq([%w[/usr/bin/greyhole --empty-trash]])

        FileUtils.mkdir_p("#{dir}/elsewhere")
        File.write("#{dir}/elsewhere/secret", 'x')
        File.symlink("#{dir}/elsewhere", "#{drives[0]}/.gh_trash/Photos/out")
        File.symlink("#{dir}/elsewhere/secret", "#{drives[1]}/.gh_trash/Photos/secret")
        expect(refusal('greyhole.trash_restore', { 'share' => 'Photos', 'path' => 'out/secret' })).to eq("Photos/out/secret isn't in the pool's trash")
        expect(refusal('greyhole.trash_delete', { 'share' => 'Photos', 'path' => 'secret' })).to eq("Photos/secret isn't in the pool's trash")
        ['../x', '/etc/passwd', 'a//b', './a', ''].each do |path|
          expect(refusal('greyhole.trash_delete', { 'share' => 'Photos', 'path' => path })).not_to be_nil, path
        end
        expect(refusal('greyhole.trash_delete', { 'share' => '../Photos', 'path' => '2026/beach [1].jpg' })).to include("isn't a share name")
        # Would read as an option on greyhole's command line
        expect(refusal('greyhole.trash_delete', { 'share' => '--empty-trash', 'path' => 'x' })).to include("isn't a share name")
      end

      it "restores only into a share that's still pooled and has no file by that name" do
        File.write("#{dir}/greyhole.conf", "num_copies[Other] = 2\n")
        expect(refusal('greyhole.trash_restore', { 'share' => 'Photos', 'path' => '2026/beach [1].jpg' }))
          .to eq("Photos isn't in the pool any more: turn its copies back on to restore its files")
        File.write("#{dir}/greyhole.conf", "num_copies[Photos] = 2\n")
        FileUtils.mkdir_p("#{folder}/2026")
        File.symlink('/somewhere', "#{folder}/2026/beach [1].jpg")
        expect(refusal('greyhole.trash_restore', { 'share' => 'Photos', 'path' => '2026/beach [1].jpg' }))
          .to eq('Photos has a 2026/beach [1].jpg now: rename or move it, then restore')
      end

      it 'stages a copy for greyhole --cp, then deletes the copies and the folders they leave empty' do
        copies = drives.map { |d| "#{d}/.gh_trash/Photos/2026/beach [1].jpg" }
        File.write("#{drives[0]}/.gh_trash/Photos/2026/keep.jpg", 'other')
        staged = nil
        allow(helper).to receive(:run_command).and_call_original
        allow(helper).to receive(:run_command).with(array_including('/usr/bin/greyhole')) do |argv|
          staged = File.read(argv[2])
          expect(argv).to eq(['/usr/bin/greyhole', '--cp', argv[2], 'Photos/2026/'])
          expect(argv[2]).to start_with("#{drives[0]}/.amahi-restore/").and end_with('/beach [1].jpg')
          nil
        end
        helper.do_restore_from_trash('Photos', '2026/beach [1].jpg', copies)
        expect(staged).to eq('picture')
        expect(copies.map { |copy| File.exist?(copy) }).to eq([false, false])
        expect(File.exist?("#{drives[0]}/.gh_trash/Photos/2026/keep.jpg")).to be true
        expect(File.directory?("#{drives[1]}/.gh_trash/Photos/2026")).to be false
        expect(Dir.children("#{drives[0]}/.amahi-restore")).to be_empty
      end

      it 'keeps the Trash setting, and deletes what has been in a trash longer, without following links' do
      expect(steps('trash.set_days', { 'days' => 14 })).to eq([[:install, '/etc/amahi-kai/trash-days', "14\n", nil, '0644']])
      expect(refusal('trash.set_days', { 'days' => -1 })).to include('whole number from 0 to 3650')
      expect(steps('trash.expire', {})).to eq([[:expire_trash]])

      bin = "#{dir}/docs/.recycle"
      FileUtils.mkdir_p("#{bin}/old")
      File.write("#{bin}/old/fresh.txt", 'kept: just deleted')
      stub_const('AmahiHelper::TRASH_DAYS', "#{dir}/trash-days")
      allow(helper).to receive(:samba_shares)
        .and_return('docs' => { name: 'Docs', path: "#{dir}/docs", pooled: false }, 'photos' => { name: 'Photos', path: folder, pooled: true })
      ran = []
      allow(helper).to receive(:run_command).and_wrap_original { |original, argv| ran << argv; original.call(argv) }
      helper.do_expire_trash # 30 days unless set
      expect(ran).to include(['/usr/bin/find', "#{drives[0]}/.gh_trash", '-type', 'f', '-cmin', '+43200', '-delete'],
                             ['/usr/bin/find', bin, '-type', 'f', '-cmin', '+43200', '-delete'],
                             ['/usr/bin/find', bin, '-mindepth', '1', '-type', 'd', '-empty', '-delete'])
      expect(ran.map { |argv| argv[1] }).not_to include("#{folder}/.recycle") # a pooled share's is Greyhole's
      expect(File.read("#{bin}/old/fresh.txt")).to eq('kept: just deleted')

      File.write("#{dir}/trash-days", "0\n")
      ran.clear
      helper.do_expire_trash
      expect(ran).to be_empty
    end

    it "won't stage a file it reaches through a link" do
        copy = "#{drives[0]}/.gh_trash/Photos/2026/beach [1].jpg"
        File.unlink(copy)
        File.symlink("#{dir}/greyhole.conf", copy)
        allow(helper).to receive(:run_command)
        expect { helper.do_restore_from_trash('Photos', '2026/beach [1].jpg', [copy]) }.to raise_error(AmahiHelper::Failed, /couldn't restore/)
        expect(helper).not_to have_received(:run_command)
      end
    end

    it "refreshes apt's package lists, installing nothing" do
      expect(steps('packages.refresh', {})).to eq([['/usr/bin/apt-get', 'update', { env: AmahiHelper::APT_ENV, stream: true }],
                                                   [:check_security_updates]])
    end

    it 'uninstalls Greyhole only when its config lists no drives and no share keeping copies' do
      conf = Tempfile.new('greyhole.conf')
      stub_const('AmahiHelper::GREYHOLE_CONF', conf.path)
      allow(AmahiHelper).to receive(:installed!).and_return(true)
      File.write(conf.path, "db_name = greyhole\nstorage_pool_drive = /mnt/storage-1/gh, min_free: 10gb\n")
      expect(refusal('greyhole.uninstall', {})).to eq('Greyhole still has drives in its pool; take them out on Disks → Greyhole Pool first')
      File.write(conf.path, "db_name = greyhole\nnum_copies[Photos] = 2\n")
      expect(refusal('greyhole.uninstall', {})).to eq('the share Photos still keeps copies with Greyhole; turn that off on Shares first')
      File.write(conf.path, "db_name = greyhole\n")
      expect(steps('greyhole.uninstall', {})).to eq(
        [['/usr/bin/systemctl', 'disable', '--now', 'greyhole.service', { allow_failure: true }],
         ['/usr/bin/apt-get', '-y', '-o', 'DPkg::Lock::Timeout=300', 'purge', 'greyhole', { env: AmahiHelper::APT_ENV, stream: true }],
         [:remove_files, conf.path, '/etc/amahi-kai/greyhole-pool.conf', '/etc/apt/sources.list.d/greyhole.list',
          '/usr/share/keyrings/greyhole-archive-keyring.asc']]
      )
    ensure
      conf&.close!
    end

    it 'installs files with the mode and group asked for' do
      skip 'chown to root needs root' unless Process.euid.zero?
      Dir.mktmpdir do |dir|
        allow(helper).to receive(:group_id).with('amahi').and_return(Process.gid)
        helper.do_install("#{dir}/greyhole.conf", 'x', nil, '0640', 'amahi')
        stat = File.stat("#{dir}/greyhole.conf")
        expect([stat.mode & 0o7777, stat.uid, stat.gid]).to eq([0o640, 0, Process.gid])
      end
    end

    describe 'the database' do
      let(:dir) { Dir.mktmpdir }
      let(:ran) { [] }

      before do
        stub_const('AmahiHelper::GREYHOLE_SCHEMA', "#{dir}/schema-mysql.sql")
        allow(helper).to receive(:run_command) { |argv| ran << argv }
      end

      after { FileUtils.rm_rf(dir) }

      it "is created for the app's MariaDB user, and the schema loaded once the package has put it in place" do
        helper.do_greyhole_database
        expect(ran).to eq([['/usr/bin/mysql', '-u', 'root', '--batch', '-e', AmahiHelper::GREYHOLE_DB_SQL]])
        expect(AmahiHelper::GREYHOLE_DB_SQL).to include("TO 'amahi'@'localhost'")

        File.write("#{dir}/schema-mysql.sql", 'CREATE TABLE settings (x INT);')
        allow(helper).to receive(:capture).and_return("0\n")
        helper.do_greyhole_database
        expect(ran.last).to eq(['/usr/bin/mysql', '-u', 'root', 'greyhole', { stdin: 'CREATE TABLE settings (x INT);' }])

        ran.clear
        allow(helper).to receive(:capture).and_return("12\n")
        expect(helper.do_greyhole_database).to eq('schema already loaded')
        expect(ran.size).to eq(1)
      end
    end
  end

  describe 'packages' do
    describe 'updates (Settings → System Dependencies)' do
      let(:apt_list) do
        "Listing...\nsamba/noble-updates,noble-security 2:4.19.5-4ubuntu9.3 amd64 [upgradable from: 2:4.19.5-4ubuntu9.2]\n" \
          "apparmor/noble-updates 4.0.1-0ubuntu0.8 amd64 [upgradable from: 4.0.1-0ubuntu0.5]\n"
      end
      let(:ok) { instance_double(Process::Status, success?: true) }
      let(:opts) { { env: AmahiHelper::UPGRADE_ENV, stream: true } }

      before do
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(AmahiHelper::ENV_MIN, '/usr/bin/apt', 'list', '--upgradable', any_args).and_return([apt_list, '', ok])
        allow(Open3).to receive(:capture3).with(AmahiHelper::ENV_MIN, '/usr/bin/dpkg-query', '-W', any_args) do |*args|
          names = args.drop(4).grep(String)
          [names.map { |n| "#{n}\t#{%w[samba apparmor greyhole].include?(n) ? 'ii ' : 'un '}\n" }.join, '', ok]
        end
        allow(helper).to receive(:capture).with(['/usr/bin/apt-mark', 'showhold']).and_return("greyhole\n")
      end

      it 'updates installed packages with an update waiting, only those, with needrestart just listing restarts' do
        expect(AmahiHelper::UPGRADE_ENV).to include('NEEDRESTART_MODE' => 'l', 'DEBIAN_FRONTEND' => 'noninteractive')
        expect(steps('packages.upgrade', { 'packages' => %w[samba apparmor samba] })).to eq(
          [['/usr/bin/apt-get', '-y', '-o', 'Dpkg::Options::=--force-confold', '-o', 'DPkg::Lock::Timeout=300',
            'install', '--only-upgrade', 'samba', 'apparmor', opts],
           [:check_security_updates]]
        )
      end

      it "refuses a package that isn't installed, has no update, is held, or isn't a package name" do
        expect(refusal('packages.upgrade', { 'packages' => ['tailscale'] })).to eq("tailscale isn't installed")
        expect(refusal('packages.upgrade', { 'packages' => ['greyhole'] })).to eq('greyhole has no update waiting')
        allow(Open3).to receive(:capture3).with(AmahiHelper::ENV_MIN, '/usr/bin/apt', 'list', '--upgradable', any_args)
                                          .and_return(["#{apt_list}greyhole/stable 0.15.29 all [upgradable from: 0.15.28]\n", '', ok])
        expect(refusal('packages.upgrade', { 'packages' => ['greyhole'] })).to eq('greyhole is held at its version; release it first')
        [['-o'], ['samba', '--purge'], ['Samba'], ['../x'], [], 'samba', nil, ['samba'] * 201].each do |list|
          expect(refusal('packages.upgrade', { 'packages' => list })).not_to be_nil, list.inspect
        end
      end

      it 'updates everything but held packages, adding the new packages an update needs, removing none' do
        expect(steps('packages.upgrade_all', {})).to eq(
          [['/usr/bin/apt-get', '-y', '-o', 'Dpkg::Options::=--force-confold', '-o', 'DPkg::Lock::Timeout=300',
            '--with-new-pkgs', 'upgrade', opts],
           [:check_security_updates]]
        )
        expect(refusal('packages.upgrade_all', { 'packages' => ['samba'] })).to eq('unexpected argument packages')
      end

      it 'holds and releases installed packages' do
        expect(steps('packages.hold', { 'packages' => ['samba'], 'held' => true })).to eq([%w[/usr/bin/apt-mark hold samba]])
        expect(steps('packages.hold', { 'packages' => ['greyhole'], 'held' => false })).to eq([%w[/usr/bin/apt-mark unhold greyhole]])
        expect(refusal('packages.hold', { 'packages' => ['tailscale'], 'held' => true })).to eq("tailscale isn't installed")
        expect(refusal('packages.hold', { 'packages' => ['samba'], 'held' => 'yes' })).to eq('held must be true or false')
      end

      it 'turns automatic updates on or off, leaving the daily package list refresh on' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/usr/bin/unattended-upgrade').and_return(true)
        expect(steps('updates.set_automatic', { 'enabled' => false })).to eq(
          [[:install, AmahiHelper::AUTO_UPGRADES, %(APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "0";\n), nil]]
        )
        expect(steps('updates.set_automatic', { 'enabled' => true }).first[2]).to include('Unattended-Upgrade "1"')
        allow(File).to receive(:exist?).with('/usr/bin/unattended-upgrade').and_return(false)
        expect(refusal('updates.set_automatic', { 'enabled' => true })).to eq('unattended-upgrades is not installed')
        expect(steps('updates.set_automatic', { 'enabled' => false }).size).to eq(1)
        expect(refusal('updates.set_automatic', { 'enabled' => 1 })).to eq('enabled must be true or false')
      end

      it 'records the security updates waiting, keeping when each was first seen while its version is the same' do
        dir = Dir.mktmpdir
        stub_const('AmahiHelper::SECURITY_UPDATES', "#{dir}/security-updates.json")
        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
        first = Time.utc(2026, 10, 1, 12)
        helper.do_check_security_updates(first)
        expect(JSON.parse(File.read("#{dir}/security-updates.json"))['updates'])
          .to eq('samba' => { 'available' => '2:4.19.5-4ubuntu9.3', 'first_seen' => '2026-10-01T12:00:00Z' })

        helper.do_check_security_updates(first + 3.days)
        expect(JSON.parse(File.read("#{dir}/security-updates.json"))['updates']['samba']['first_seen']).to eq('2026-10-01T12:00:00Z')

        allow(Open3).to receive(:capture3).with(AmahiHelper::ENV_MIN, '/usr/bin/apt', 'list', '--upgradable', any_args)
                                          .and_return(["samba/noble-security 2:4.19.5-4ubuntu9.4 amd64 [upgradable from: 2:4.19.5-4ubuntu9.2]\n", '', ok])
        helper.do_check_security_updates(first + 4.days)
        data = JSON.parse(File.read("#{dir}/security-updates.json"))
        expect(data['updates']['samba']).to eq('available' => '2:4.19.5-4ubuntu9.4', 'first_seen' => '2026-10-05T12:00:00Z')
        expect(data['checked_at']).to eq('2026-10-05T12:00:00Z')
        expect(helper).to have_received(:do_install).with("#{dir}/security-updates.json", anything, nil, '0640', 'amahi').exactly(3).times
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it 'adds only the apt repositories it lists' do
      expect(steps('packages.add_repository', { 'repository' => 'greyhole' })).to eq([[:add_apt_repository, 'greyhole']])
      expect(refusal('packages.add_repository', { 'repository' => 'evil' })).to eq('repository "evil" isn\'t one Amahi-kai uses')
    end

    it 'installs only the packages it lists, non-interactively, keeping changed config files, with output streamed' do
      expect(AmahiHelper::APT_ENV).to include('DEBIAN_FRONTEND' => 'noninteractive', 'PATH' => '/usr/sbin:/usr/bin:/sbin:/bin')
      opts = { env: AmahiHelper::APT_ENV, stream: true }
      expect(steps('packages.install', { 'packages' => %w[greyhole php8.3-mysql greyhole] })).to eq(
        [['/usr/bin/apt-get', 'update', opts],
         ['/usr/bin/apt-get', '-y', '-o', 'Dpkg::Options::=--force-confold', '-o', 'DPkg::Lock::Timeout=300',
          'install', 'greyhole', 'php8.3-mysql', opts]]
      )
    end

    it 'refuses other packages and malformed lists' do
      [['openssh-server'], ['greyhole', '-o'], ['./x.deb'], [], 'greyhole', nil, ['greyhole'] * 11].each do |list|
        expect(refusal('packages.install', { 'packages' => list })).not_to be_nil, list.inspect
      end
    end

    it 'pins every repository it knows, and lists only packages from Ubuntu or those repositories' do
      expect(AmahiHelper::APT_REPOSITORIES.keys).to contain_exactly('greyhole', 'cloudflared', 'tailscale', 'docker')
      expect(AmahiHelper::PACKAGES).to include('cloudflared', 'tailscale', 'docker-ce', 'dnsmasq', 'fail2ban', 'unattended-upgrades')
    end

    describe 'a repository signing key' do
      let(:dir) { Dir.mktmpdir }
      let(:key) { "-----BEGIN PGP PUBLIC KEY BLOCK-----\nKEY\n-----END PGP PUBLIC KEY BLOCK-----\n" }
      let(:urls) { [] }
      let(:repo) do
        { key_url: 'https://example.com/%<codename>s.key', fingerprints: ['A' * 40, 'C' * 40], keyring: "#{dir}/keyring.asc",
          list: "#{dir}/x.list", source: "deb [arch=%<arch>s signed-by=#{dir}/keyring.asc] https://example.com/deb %<codename>s main" }
      end
      let(:listing) { "pub:-:4096:1:ABC:::::::scESC:\nfpr:::::::::#{'A' * 40}:\nsub:-:4096:1:DEF::::::::e:\nfpr:::::::::#{'C' * 40}:\n" }

      before do
        stub_const('AmahiHelper::RUN_DIR', dir)
        allow(helper).to receive(:repository_vars).and_return(codename: 'noble', arch: 'amd64')
        allow(helper).to receive(:run_command) do |argv|
          if argv.include?('--dearmor')
            File.binwrite(argv[argv.index('--output') + 1], "\x99BINARY")
          else
            expect(argv).to include('--proto', '=https')
            urls << argv.last
            File.write(argv[argv.index('-o') + 1], key)
          end
          nil
        end
        allow(helper).to receive(:capture).and_return(listing)
      end

      after { FileUtils.rm_rf(dir) }

      it 'is installed with the source list, for this release and architecture, when its fingerprints are the pinned ones' do
        stub_const('AmahiHelper::APT_REPOSITORIES', { 'x' => repo })
        helper.do_add_apt_repository('x')
        expect(urls).to eq(['https://example.com/noble.key'])
        expect(File.read("#{dir}/keyring.asc")).to eq(key)
        expect(File.read("#{dir}/x.list")).to eq("deb [arch=amd64 signed-by=#{dir}/keyring.asc] https://example.com/deb noble main\n")
      end

      it 'is stored binary in a .gpg keyring (dearmored if it came armored), armored in a .asc one' do
        stub_const('AmahiHelper::APT_REPOSITORIES', { 'x' => repo.merge(keyring: "#{dir}/keyring.gpg") })
        helper.do_add_apt_repository('x')
        expect(File.binread("#{dir}/keyring.gpg")).to eq("\x99BINARY".b)

        allow(helper).to receive(:run_command) { |argv| File.binwrite(argv[argv.index('-o') + 1], "\x99RAW") && nil }
        helper.do_add_apt_repository('x')
        expect(File.binread("#{dir}/keyring.gpg")).to eq("\x99RAW".b)

        stub_const('AmahiHelper::APT_REPOSITORIES', { 'x' => repo })
        expect { helper.do_add_apt_repository('x') }.to raise_error(AmahiHelper::Failed, /must be an armored key/)
      end

      it 'is refused when its fingerprints differ, or another key was added to the file' do
        stub_const('AmahiHelper::APT_REPOSITORIES', { 'x' => repo })
        ["fpr:::::::::#{'B' * 40}:\n", "fpr:::::::::#{'A' * 40}:\n",
         "fpr:::::::::#{'A' * 40}:\nfpr:::::::::#{'C' * 40}:\nfpr:::::::::#{'B' * 40}:\n"].each do |other|
          allow(helper).to receive(:capture).and_return(other)
          expect { helper.do_add_apt_repository('x') }.to raise_error(AmahiHelper::Failed, /not the pinned ones/)
        end
        expect(File.exist?("#{dir}/keyring.asc")).to be false
      end

      it 'pins the key and subkey fingerprints of every repository' do
        AmahiHelper::APT_REPOSITORIES.each_key do |name|
          expect(AmahiHelper::APT_REPOSITORIES[name][:fingerprints]).to all(match(/\A\h{40}\z/))
          expect(AmahiHelper::APT_REPOSITORIES[name][:fingerprints].size).to eq(2)
        end
      end

      it 'is not even downloaded when no fingerprint is pinned' do
        stub_const('AmahiHelper::APT_REPOSITORIES', { 'x' => repo.merge(fingerprints: []) })
        expect { helper.do_add_apt_repository('x') }.to raise_error(AmahiHelper::Failed, /isn't pinned/)
        expect(helper).not_to have_received(:run_command)
      end
    end

    it 'reads the release codename and architecture apt sources are written for' do
      Tempfile.create('os-release') do |f|
        f.write(%(NAME="Ubuntu"\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=noble\n))
        f.flush
        stub_const('AmahiHelper::OS_RELEASE', f.path)
        allow(helper).to receive(:capture).with(%w[/usr/bin/dpkg --print-architecture]).and_return("amd64\n")
        expect(helper.repository_vars).to eq(codename: 'noble', arch: 'amd64')
        allow(helper).to receive(:capture).with(%w[/usr/bin/dpkg --print-architecture]).and_return("amd64 ; x\n")
        expect { helper.repository_vars }.to raise_error(AmahiHelper::Failed, /unexpected architecture/)
      end
    end
  end

  describe 'the Cloudflare Tunnel' do
    let(:token) { "eyJhIjoiYWJjIiwidCI6ImRlZiIsInMiOiJnaGkifQ#{'x' * 40}==" }

    before do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/bin/cloudflared').and_return(true)
    end

    it 'saves the token where only root can read it, writes its own unit, and (re)starts the tunnel' do
      planned = steps('tunnel.configure', { 'token' => " #{token}\n" })
      expect(planned).to eq([
                              [:make_dir, '/etc/amahi-kai', '0755'],
                              [:install, '/etc/amahi-kai/tunnel.token', token, nil, '0600'],
                              [:install, '/etc/systemd/system/cloudflared.service', AmahiHelper::TUNNEL_UNIT_CONTENT, nil],
                              %w[/usr/bin/systemctl daemon-reload],
                              %w[/usr/bin/systemctl enable cloudflared.service],
                              %w[/usr/bin/systemctl restart cloudflared.service]
                            ])
      expect(AmahiHelper::TUNNEL_UNIT_CONTENT).to include('run --token-file /etc/amahi-kai/tunnel.token')
      expect(planned.map { |step| helper.describe(step) }.to_s).not_to include(token)
    end

    it 'refuses tokens that are not one, and works only once cloudflared is installed' do
      ['short', "#{token} --url http://x", "#{token}\nExecStartPre=/bin/sh", 'x' * 5000].each do |bad|
        expect(refusal('tunnel.configure', { 'token' => bad })).not_to be_nil, bad[0, 40]
      end
      allow(File).to receive(:executable?).with('/usr/bin/cloudflared').and_return(false)
      expect(refusal('tunnel.configure', { 'token' => token })).to eq("cloudflared isn't installed")
      expect(refusal('tunnel.start', {})).to eq("cloudflared isn't installed")
    end

    it 'starts, stops and restarts only cloudflared' do
      expect(steps('tunnel.start', {})).to eq([%w[/usr/bin/systemctl start cloudflared.service]])
      expect(steps('tunnel.stop', {})).to eq([%w[/usr/bin/systemctl stop cloudflared.service]])
      expect(steps('tunnel.restart', {})).to eq([%w[/usr/bin/systemctl restart cloudflared.service]])
      expect(refusal('tunnel.start', { 'unit' => 'ssh' })).to eq('unexpected argument unit')
    end
  end

  describe 'Tailscale and Docker' do
    before do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/bin/tailscale').and_return(true)
    end

    it 'runs fixed tailscale commands, giving `tailscale up` 10 seconds and streaming its output' do
      expect(steps('tailscale.start', {})).to eq([%w[/usr/bin/systemctl enable --now tailscaled.service]])
      expect(steps('tailscale.up', {})).to eq([['/usr/bin/timeout', '10', '/usr/bin/tailscale', 'up', { stream: true, allow_failure: true }]])
      expect(steps('tailscale.down', {})).to eq([%w[/usr/bin/tailscale down]])
      expect(steps('tailscale.logout', {})).to eq([['/usr/bin/tailscale', 'logout', { allow_failure: true }],
                                                   %w[/usr/bin/systemctl stop tailscaled.service]])
      expect(refusal('tailscale.up', { 'flags' => '--ssh' })).to eq('unexpected argument flags')
      allow(File).to receive(:executable?).with('/usr/bin/tailscale').and_return(false)
      expect(refusal('tailscale.up', {})).to eq("tailscale isn't installed")
    end
  end

  describe 'security fixes' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(dir) }

    before do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/sbin/ufw').and_return(true)
    end

    # DNS and DHCP get in by their own rules, on their addresses and interface (dns.write_config,
    # network.write_dnsmasq_config), which UFW keeps while it's off.
    it 'turns UFW on with SSH, the web UI, HTTPS, Samba and mDNS let in' do
      stub_const('AmahiHelper::DNSMASQ_CONF', "#{dir}/amahi.conf")
      ufw = '/usr/sbin/ufw'
      base = [[ufw, 'default', 'deny', 'incoming'], [ufw, 'allow', '22/tcp'], [ufw, 'allow', '3000/tcp'],
              [ufw, 'allow', '443/tcp'], [ufw, 'allow', '445/tcp'], [ufw, 'allow', '139/tcp'], [ufw, 'allow', '137:138/udp'],
              [ufw, 'allow', '5353/udp']]
      expect(steps('security.enable_firewall', {})).to eq([*base, [ufw, '--force', 'enable']])
      File.write("#{dir}/amahi.conf", "dhcp-range=192.168.1.100,192.168.1.254,14400s\n")
      expect(steps('security.enable_firewall', {})).to eq([*base, [ufw, '--force', 'enable']])
    end

    it 'turns off SSH root login' do
      expect(steps('security.harden_ssh', { 'setting' => 'root_login' })).to eq([[:harden_ssh, { 'PermitRootLogin' => 'no' }]])
      expect(refusal('security.harden_ssh', { 'setting' => 'PermitRootLogin yes' })).to include("isn't one Amahi-kai uses")
    end

    it 'turns off SSH password login only while an account that can log in has a key' do
      allow(helper).to receive(:ssh_key_holders).and_return([])
      expect(refusal('security.harden_ssh', { 'setting' => 'password_login' })).to include('would lock everyone out of SSH')
      allow(helper).to receive(:ssh_key_holders).and_return(['casey'])
      expect(steps('security.harden_ssh', { 'setting' => 'password_login' }))
        .to eq([[:harden_ssh, { 'PasswordAuthentication' => 'no', 'KbdInteractiveAuthentication' => 'no' }]])
    end

    it 'finds accounts with a login shell and a key, not system or nologin accounts or comments' do
      shells = "#{dir}/shells"
      File.write(shells, "# /etc/shells\n/bin/sh\n/bin/bash\n/usr/bin/bash\n")
      allow(File).to receive(:readlines).and_call_original
      allow(File).to receive(:readlines).with('/etc/shells', chomp: true).and_return(File.readlines(shells, chomp: true))
      people = { 'casey' => [1000, '/bin/bash', "ssh-ed25519 AAAAC3Nza casey@laptop\n"],
                 'ann' => [1001, '/usr/sbin/nologin', "ssh-ed25519 AAAAC3Nza ann\n"],
                 'bob' => [1002, '/bin/bash', "# ssh-ed25519 AAAAC3Nza old key\n"],
                 'svc' => [999, '/bin/bash', "ssh-rsa AAAAB3Nza svc\n"],
                 'eve' => [1003, '/bin/bash', nil] }
      entries = people.map do |name, (uid, shell, keys)|
        home = "#{dir}/#{name}"
        FileUtils.mkdir_p("#{home}/.ssh")
        File.write("#{home}/.ssh/authorized_keys", keys) if keys
        Etc::Passwd.new(name, 'x', uid, 100, '', home, shell)
      end
      allow(Etc).to receive(:passwd) { |&block| entries.each(&block) }
      expect(helper.ssh_key_holders).to eq(['casey'])
    end

    describe 'the sshd drop-in' do
      let(:dropin) { "#{dir}/10-amahi-kai.conf" }
      let(:ran) { [] }

      before do
        stub_const('AmahiHelper::SSHD_DROPIN', dropin)
        allow(Dir).to receive(:mkdir).and_call_original
        allow(Dir).to receive(:mkdir).with('/run/sshd', 0o755)
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with('/run/sshd').and_return(true)
        allow(helper).to receive(:run_command) { |argv| ran << argv && nil }
        allow(helper).to receive(:capture).with(%w[/usr/sbin/sshd -t]).and_return('')
        allow(helper).to receive(:capture).with(%w[/usr/sbin/sshd -T])
                                          .and_return("port 22\npermitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\n")
      end

      it 'keeps earlier settings, is checked with sshd -t, reloads ssh and replies with the effective settings' do
        helper.do_harden_ssh('PermitRootLogin' => 'no')
        reply = helper.do_harden_ssh('PasswordAuthentication' => 'no', 'KbdInteractiveAuthentication' => 'no')
        expect(File.read(dropin).lines.drop(1).join)
          .to eq("PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n")
        expect(ran.last).to eq(%w[/usr/bin/systemctl try-reload-or-restart ssh.service])
        expect(reply).to eq('ssh' => { 'permitrootlogin' => 'no', 'passwordauthentication' => 'no', 'kbdinteractiveauthentication' => 'no' })
      end

      it 'puts the old drop-in back if sshd rejects the config, and reloads nothing' do
        File.write(dropin, "PermitRootLogin no\n")
        allow(helper).to receive(:capture).with(%w[/usr/sbin/sshd -t]).and_raise(AmahiHelper::Failed, 'sshd exited 255: bad')
        expect { helper.do_harden_ssh('PasswordAuthentication' => 'no') }.to raise_error(AmahiHelper::Failed)
        expect(File.read(dropin)).to eq("PermitRootLogin no\n")
        expect(ran).to be_empty

        File.unlink(dropin)
        expect { helper.do_harden_ssh('PasswordAuthentication' => 'no') }.to raise_error(AmahiHelper::Failed)
        expect(File.exist?(dropin)).to be false
      end
    end

    it "reports UFW's state and sshd's effective settings" do
      allow(File).to receive(:executable?).with('/usr/sbin/sshd').and_return(true)
      allow(Dir).to receive(:mkdir).and_call_original
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with('/run/sshd').and_return(true)
      allow(helper).to receive(:capture).with(%w[/usr/sbin/ufw status]).and_return("Status: active\n\nTo  Action  From\n")
      allow(helper).to receive(:capture).with(%w[/usr/sbin/sshd -T]).and_return("permitrootlogin without-password\nport 22\n")
      expect(steps('security.report', {})).to eq([[:security_report]])
      expect(helper.do_security_report).to eq('firewall' => 'active', 'ssh' => { 'permitrootlogin' => 'without-password' })
      allow(File).to receive(:executable?).with('/usr/sbin/ufw').and_return(false)
      expect(helper.do_security_report['firewall']).to eq('not installed')
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

    it 'notes an allowed failure instead of raising, a missing command included' do
      expect(helper.run_command(['/bin/sh', '-c', 'exit 4', { allow_failure: true }])).to start_with('ignored: sh exited 4')
      expect(helper.run_command(['/nonexistent/udevadm', 'settle', { allow_failure: true }])).to start_with('ignored: /nonexistent/udevadm')
    end

    it 'streams output to stderr as it runs, in the environment given' do
      script = '[ "$DEBIAN_FRONTEND" = noninteractive ] && echo one && echo two >&2'
      env = { 'PATH' => '/usr/bin:/bin', 'DEBIAN_FRONTEND' => 'noninteractive' }
      expect { helper.run_command(['/bin/sh', '-c', script, { env: env, stream: true }]) }.to output("one\ntwo\n").to_stderr
      expect { helper.run_command(['/bin/sh', '-c', 'echo E: no space; exit 100', { stream: true }]) }
        .to raise_error(AmahiHelper::Failed, 'sh exited 100: E: no space').and output.to_stderr
    end
  end

  describe 'the reply' do
    before do
      allow(helper).to receive(:check_environment!)
      allow(helper).to receive(:log)
      allow(Process).to receive(:euid).and_return(0)
      allow(helper).to receive(:plan).and_return([[:a], [:b], [:c]])
      allow(helper).to receive(:perform).and_return({ 'mount_point' => '/mnt/a' }, 'ignored: udevadm', nil)
    end

    it "carries the steps' data and notes" do
      expect(helper.execute('system.reboot', {})).to eq('ok' => true, 'mount_point' => '/mnt/a', 'notes' => ['ignored: udevadm'])
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
