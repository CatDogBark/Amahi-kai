require 'rails_helper'
require 'open3'
require 'etc'

# bin/amahi-install, bin/amahi-update and the scripts they run as root. Root owns the
# app's code and never runs anything that loads the app or its gems: the app user can
# write vendor/bundle, so that would hand it root.
RSpec.describe 'install and update scripts' do
  scripts = %w[bin/amahi-install bin/amahi-update bin/amahi-install-helper bin/amahi-set-ownership]

  scripts.each do |script|
    it "#{script} is valid bash" do
      _out, err, status = Open3.capture3('bash', '-n', Rails.root.join(script).to_s)
      expect(status).to be_success, err
    end
  end

  # Commands that load the app or its gems. Each must be an as_app call (the app user).
  app_commands = %r{bin/rails|\bbundle (?:install|exec)|\brails (?:runner|db:|assets:)}

  %w[bin/amahi-install bin/amahi-update].each do |script|
    it "#{script} runs the app's commands only as the app user" do
      offenders = File.readlines(Rails.root.join(script)).each_with_index.filter_map do |line, i|
        code = line.strip
        next if code.start_with?('#', 'echo ') || !code.match?(app_commands)
        "#{i + 1}: #{code}" unless code.match?(/\bas_app "/)
      end
      expect(offenders).to eq([])
    end

    it "#{script} doesn't give the code back to the app user" do
      text = File.read(Rails.root.join(script))
      expect(text).not_to match(/chown -R "\$APP_USER/)
      expect(text).to include('bin/amahi-set-ownership')
    end
  end

  it "gives the first admin password to the seeds in a file, never on a command line, and never the public one" do
    text = File.read(Rails.root.join('bin/amahi-install'))
    expect(text).not_to include(User::SEED_ADMIN_PASSWORD)
    expect(text).to include("AMAHI_FIRST_PASSWORD_FILE='$PW_FILE'")
    expect(text).to match(/install -o "\$APP_USER" -g "\$APP_GROUP" -m 0600 \/dev\/null "\$PW_FILE"/)
    used = text.lines.grep(/\$ADMIN_PASS\b/).map(&:strip)
    expect(used.grep(/as_app|bin\/rails|sudo/)).to eq([])
  end

  describe 'a fresh install' do
    let(:install) { File.read(Rails.root.join('bin/amahi-install')) }

    it 'shows the first password as soon as the seeds have used it, not only at the end' do
      seeded = install.index("bin/rails db:seed")
      shown = install.index("  echo \"  ── The first admin account")
      expect(shown).to be > seeded
      expect(shown).to be < install.index('bin/rails assets:precompile')
    end

    it "sets the server's address and turns automatic updates off only on a new database" do
      fresh = install.index('if $FRESH; then')
      expect(install.index("Setting.set('net'")).to be > fresh
      expect(install.index('20auto-upgrades')).to be > fresh
      expect(install).to include('FRESH=true')
    end

    it "doesn't wait for the VM guest agent's port, which only Proxmox's option adds" do
      expect(install).not_to include('enable --now qemu-guest-agent')
      expect(install).to include('if [ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]; then')
    end

    it "writes Samba's config from the app, as every update does, instead of editing Ubuntu's" do
      expect(install).to include("bin/rails runner 'exit(SambaService.push_config ? 0 : 1)'")
      expect(install).not_to include('wide links = yes')
    end

    it 'restarts the app, running the code just installed, and checks it answers' do
      expect(install).to include("systemctl restart amahi-kai\nif ! app_answers; then")
      expect(install).not_to match(/^systemctl start amahi-kai$/)
    end

    it 'keeps the git history System Update needs, from a checkout as from GitHub' do
      expect(install).not_to include("--exclude='.git'")
      expect(install).to include('clone --quiet --no-hardlinks "$SCRIPT_DIR" "$APP_DIR"', 'remote set-url origin "$REPO_URL"')
    end

    it 'has no --with-greyhole: the wizard or Disks → Greyhole Pool installs Greyhole' do
      expect(install).to include('--with-greyhole is gone')
      expect(install).not_to include('greyhole.list')
    end

    it "leaves the app's own service files to the helper's installer, which updates refresh too" do
      expect(install).not_to include('cat > /etc/systemd/system/amahi-kai')
      helper = File.read(Rails.root.join('bin/amahi-install-helper'))
      expect(helper).to include('for unit in amahi-kai.service amahi-kai-indexer.service amahi-kai-indexer.timer')
      expect(helper).to include('systemctl enable amahi-kai.service', 'systemctl enable amahi-kai-indexer.timer')
      expect(helper).not_to include('enable --now amahi-kai.service')
      expect(File.read(Rails.root.join('config/systemd/amahi-kai.service')))
        .to include('ExecStart=/usr/bin/bundle exec puma -C config/puma.rb', 'EnvironmentFile=/etc/amahi-kai/amahi.env')
      expect(File.read(Rails.root.join('config/systemd/amahi-kai-indexer.timer'))).to include('OnUnitActiveSec=10min')
    end

    it "install.sh hands the installer its options and the code it fetched, from main unless told" do
      script = File.read(Rails.root.join('site/install.sh'))
      expect(script).to include('BRANCH="${AMAHI_BRANCH:-main}"', 'export AMAHI_CODE_FETCHED=1', 'exec bin/amahi-install "$@"')
      expect(install).to include('if [[ "${AMAHI_CODE_FETCHED:-}" == 1 && -d "$APP_DIR/.git" ]]; then')
    end
  end

  it 'installs and enables the check for updates' do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('amahi-kai-update-check.service amahi-kai-update-check.timer')
    expect(text).to include('systemctl enable --now amahi-kai-update-check.timer')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-update-check.service')))
      .to include('ExecStart=/usr/local/sbin/amahi-helper system.check_update')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-update-check.timer'))).to include('OnUnitActiveSec=6h')
  end

  it 'installs Avahi and announces the apps each time Docker starts' do
    expect(File.read(Rails.root.join('bin/amahi-install'))).to include('  avahi-daemon \\')
    expect(File.read(Rails.root.join('bin/amahi-update'))).to include('apt-get install -y -qq --no-install-recommends avahi-daemon')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-app-firewall.service')))
      .to include('ExecStart=/usr/local/sbin/amahi-helper apps.firewall', 'ExecStart=-/usr/local/sbin/amahi-helper apps.announce')
  end

  it "installs and enables the watch that has DNS and Samba follow Tailscale, run as the app user" do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('amahi-kai-tailscale.service amahi-kai-tailscale.path', 'systemctl enable --now amahi-kai-tailscale.path')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-tailscale.path'))).to include('PathChanged=/var/lib/tailscale/tailscaled.state')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-tailscale.service')))
      .to include('User=amahi', 'RuntimeDirectory=amahi-kai-tailscale', 'RuntimeDirectoryPreserve=yes',
                  'ExecStart=/opt/amahi-kai/bin/amahi-follow-tailscale', 'WantedBy=multi-user.target')
    expect(text).to include('systemctl enable amahi-kai-tailscale.service') # once after each boot
    expect(File.stat(Rails.root.join('bin/amahi-follow-tailscale')).mode & 0o111).to eq(0o111)
  end

  # bin/amahi-follow-tailscale with a stand-in `ip` (the interface's addresses, from a file) and
  # a stand-in `bundle` that only records that the app was asked.
  describe 'following Tailscale' do
    let(:dir) { Dir.mktmpdir }
    let(:script) { Rails.root.join('bin/amahi-follow-tailscale').to_s }

    before do
      FileUtils.mkdir_p(["#{dir}/bin", "#{dir}/run", "#{dir}/app"])
      File.write("#{dir}/bin/ip", "#!/bin/sh\ncat #{dir}/addresses 2>/dev/null\n")
      File.write("#{dir}/bin/bundle", "#!/bin/sh\necho \"$*\" >> #{dir}/asked\n")
      FileUtils.chmod(0o755, ["#{dir}/bin/ip", "#{dir}/bin/bundle"])
    end

    after { FileUtils.rm_rf(dir) }

    def follow(addresses)
      addresses ? File.write("#{dir}/addresses", addresses) : FileUtils.rm_f("#{dir}/addresses")
      # The script calls /usr/bin/bundle; the stand-in takes its place by a copy of the script
      copy = "#{dir}/follow"
      File.write(copy, File.read(script).sub('/usr/bin/bundle', "#{dir}/bin/bundle"))
      FileUtils.chmod(0o755, copy)
      env = { 'PATH' => "#{dir}/bin:/usr/bin:/bin", 'APP_DIR' => "#{dir}/app", 'RUNTIME_DIRECTORY' => "#{dir}/run",
              'FOLLOW_TRIES' => '2', 'FOLLOW_WAIT' => '0' }
      _out, err, status = Open3.capture3(env, copy)
      raise "the script failed: #{err}" unless status.success?

      File.exist?("#{dir}/asked") ? File.readlines("#{dir}/asked").size : 0
    end

    it "asks the app only when the addresses change, sign-in, a new address and sign-out alike" do
      line = ->(address) { "4: tailscale0    inet #{address} scope global tailscale0\\       valid_lft forever\n" }
      signed_in = line.call('100.100.32.46/32') + "4: tailscale0    inet6 fe80::1/64 scope link\n"
      expect(follow(nil)).to eq(0) # a boot without Tailscale: nothing seen, nothing there, no app
      expect(follow(signed_in)).to eq(1) # a sign-in (or a boot with Tailscale: smbd started before it)
      expect(File.read("#{dir}/run/addresses")).to eq('100.100.32.46/32 ') # the link-local one left out
      expect(follow(signed_in)).to eq(1) # the same addresses: the app isn't booted
      expect(follow(line.call('100.100.32.47/32'))).to eq(2)
      expect(follow(nil)).to eq(3) # signed out: none
      expect(File.read("#{dir}/run/addresses")).to eq('')
      expect(File.read("#{dir}/asked")).to include("exec rails runner puts TailscaleService.follow!")
    end
  end

  it "removes the app catalog's own timer: the update check fetches the catalog" do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('systemctl disable --now amahi-kai-catalog.timer',
                            'rm -f /etc/systemd/system/amahi-kai-catalog.timer /etc/systemd/system/amahi-kai-catalog.service')
    expect(text).not_to include('enable --now amahi-kai-catalog.timer')
    expect(Rails.root.join('config/systemd/amahi-kai-catalog.timer')).not_to exist
  end

  it 'installs and enables the hourly pool snapshots' do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('amahi-kai-snapshots.service amahi-kai-snapshots.timer', 'systemctl enable --now amahi-kai-snapshots.timer')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-snapshots.service')))
      .to include('ExecStart=/usr/local/sbin/amahi-helper pools.run_snapshots')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-snapshots.timer'))).to include('OnCalendar=hourly', 'Persistent=true')
  end

  it 'installs and enables the storage health check' do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('amahi-kai-storage-check.service amahi-kai-storage-check.timer')
    expect(text).to include('systemctl enable --now amahi-kai-storage-check.timer')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-storage-check.service')))
      .to include('ExecStart=/usr/local/sbin/amahi-helper storage.check_health')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-storage-check.timer'))).to include('OnUnitActiveSec=15min')
    expect(File.read(Rails.root.join('bin/amahi-install'))).to include('  smartmontools \\')
  end

  it 'stops early with nothing new, unless repairing, and shares the lock with the check' do
    text = File.read(Rails.root.join('bin/amahi-update'))
    expect(text).to include('Already up to date', '--repair) REPAIR=true', 'REPAIR_FLAG=/run/amahi-kai-update.repair')
    expect(text).to include('flock -w 90 9', 'refresh_update_status')
  end

  it "works out ZFS's memory cache cap again at every update, when ZFS is installed" do
    text = File.read(Rails.root.join('bin/amahi-update'))
    expect(text).to include("if [[ -x /usr/sbin/zpool ]]; then\n  reply=$(/usr/local/sbin/amahi-helper zfs.setup </dev/null 2>/dev/null)")
  end

  it 'lets smartd start in a virtual machine, at install and every update' do
    expect(File.read(Rails.root.join('bin/amahi-update'))).to include("reply=$(/usr/local/sbin/amahi-helper smart.setup </dev/null 2>/dev/null)")
    expect(File.read(Rails.root.join('bin/amahi-install'))).to include('/usr/local/sbin/amahi-helper smart.setup </dev/null')
  end

  describe 'update channels' do
    let(:update) { File.read(Rails.root.join('bin/amahi-update')) }
    let(:install) { File.read(Rails.root.join('bin/amahi-install')) }

    it "checks out the commit the root helper names for the channel, never main's newest" do
      expect(update).to include('/usr/local/sbin/amahi-helper system.update_target',
                                'checkout --quiet --force --detach "$TARGET_COMMIT"')
      # Only an installed helper from before channels (the update that brings them) pulls main, once
      expect(update.scan('pull origin main').size).to eq(1)
      expect(update[/legacy\)\n.*?;;/m]).to include('pull origin main')
    end

    it "repairs the version that runs without looking for another" do
      expect(update).to match(/if \$REPAIR; then\n  log "Repairing the version that runs/)
    end

    it "has the network's configs follow the update, after Samba's and before the app restarts" do
      resync = update.index("bin/rails runner 'puts DnsService.resync_report'")
      expect(resync).not_to be_nil
      expect(resync).to be > update.index("bin/rails runner 'exit(SambaService.push_config ? 0 : 1)'")
      expect(resync).to be < update.index('restart_app || rollback')
    end

    it 'records the channel at install (development for a dev install), and a re-run keeps its version' do
      expect(install).to include('AMAHI_UPDATE_CHANNEL=$UPDATE_CHANNEL', '[[ "${AMAHI_BRANCH:-main}" == dev ]] && UPDATE_CHANNEL=development')
      expect(install).not_to include('pull origin main')
    end

    it 'has a VERSION file a release tag must match, and a workflow that publishes the release' do
      expect(File.read(Rails.root.join('VERSION')).strip).to match(/\A\d+\.\d+\.\d+(rc\d+)?\z/)
      workflow = File.read(Rails.root.join('.github/workflows/release.yml'))
      expect(workflow).to include('test "v$version" = "$GITHUB_REF_NAME"', 'gh release create', '--prerelease')
    end
  end

  it 'pulls as root without hooks or an fsmonitor command from the checkout' do
    text = File.read(Rails.root.join('bin/amahi-update'))
    expect(text).to include('git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"')
    expect(text).not_to match(/sudo -u "\$APP_USER" git/)
  end

  describe 'rolling back a failed update' do
    let(:update) { File.read(Rails.root.join('bin/amahi-update')) }

    it 'goes back to the running commit when a step or the new version fails' do
      ['Installing dependencies', 'Backing up the database', 'Running database migrations', 'Precompiling assets']
        .each { |step| expect(update).to include(%(|| rollback "#{step}")).or include(%(rollback "#{step}")) }
      expect(update).to include('restart_app || rollback "Starting the new version" restarted')
      expect(update).to include('reset --hard --quiet "$PREV"')
      expect(update).to include('AMAHI_UPDATE_PREV="$PREV"')
    end

    it 'backs up the database before migrating, and keeps the newest 3' do
      expect(update.index('backup_database 2>&1')).to be < update.index('bin/rails db:migrate')
      expect(update).to include('mysqldump --single-transaction').and include('tail -n +4')
    end

    it 'keeps the running version\'s compiled assets before replacing them' do
      expect(update.index('cp -a public/assets tmp/assets-previous')).to be < update.index('bin/rails assets:precompile')
    end

    # A check for updates holds the same lock during its fetch (a minute at most).
    it 'runs one update at a time, waiting briefly for a check to finish its fetch' do
      expect(update).to include('flock -w 90 9')
    end
  end

  it "installs System Update's job, which writes the log the page follows" do
    unit = File.read(Rails.root.join('config/systemd/amahi-kai-update.service'))
    expect(unit).to include('ExecStart=/opt/amahi-kai/bin/amahi-update --stream')
    expect(unit).to include("StandardOutput=truncate:#{SettingsController::UPDATE_LOG}")
    expect(File.read(Rails.root.join('bin/amahi-install-helper'))).to include('/etc/systemd/system/amahi-kai-update.service')
    rules = File.readlines(Rails.root.join('config/sudoers/amahi-kai')).grep(/\Aamahi /).join
    expect(rules).not_to include('amahi-update')
  end

  # Phase 4 (P4.1): Docker runs only through the helper, so the web app's user has no other
  # way to root, and older installs' docker group membership is taken away.
  it 'gives the app user one sudo rule, for the root helper, and no docker group' do
    rules = File.readlines(Rails.root.join('config/sudoers/amahi-kai')).grep(/\Aamahi /)
    expect(rules).to eq(["amahi ALL=(root) NOPASSWD: /usr/local/sbin/amahi-helper\n"])
    expect(File.read(Rails.root.join('bin/amahi-install-helper'))).to include('gpasswd -d "$APP_USER" docker')
  end

  it 'rotates the app log as the app user' do
    stanza = File.read(Rails.root.join('config/logrotate-amahi-kai.conf'))[/production\.log \{[^}]*\}/]
    expect(stanza).to include('su amahi amahi')
  end

  describe 'bin/amahi-set-ownership' do
    let(:dir) { Dir.mktmpdir }
    let(:app) { "#{dir}/app" }
    let(:outside) { "#{dir}/outside" }
    let(:user) { Etc.getpwnam('nobody') }
    let(:group) { Etc.getgrgid(user.gid) }

    before do
      skip 'needs root' unless Process.euid.zero?
      FileUtils.mkdir_p(["#{app}/bin", "#{app}/.git", "#{app}/tmp/cache", "#{app}/vendor", outside])
      File.write("#{app}/bin/amahi-update", 'echo hi')
      File.chmod(0o775, "#{app}/bin/amahi-update")
      File.write("#{app}/tmp/cache/old", 'left by root')
      File.write("#{outside}/secret", 'x')
      File.symlink("#{outside}/secret", "#{app}/bin/link")
      File.symlink(outside, "#{app}/log")
      FileUtils.chown_R(user.uid, user.gid, [app, outside])
      FileUtils.chown(0, 0, "#{app}/tmp/cache/old")
    end

    after { FileUtils.rm_rf(dir) if Process.euid.zero? }

    def run_script
      env = { 'APP_DIR' => app, 'APP_USER' => user.name, 'APP_GROUP' => group.name,
              'GIT_CONFIG_SYSTEM' => "#{dir}/gitconfig" }
      Open3.capture3(env, Rails.root.join('bin/amahi-set-ownership').to_s)
    end

    def owner(path)
      File.lstat(path).uid
    end

    it "gives root the code and the app user its folders, without following links" do
      _out, err, status = run_script
      expect(status).to be_success, err

      expect(owner(app)).to eq(0)
      expect(owner("#{app}/bin/amahi-update")).to eq(0)
      expect(File.stat("#{app}/bin/amahi-update").mode & 0o777).to eq(0o755)
      expect(owner("#{app}/bin/link")).to eq(0)
      expect(owner("#{outside}/secret")).to eq(user.uid) # the link's target is untouched
      expect(owner("#{app}/.git")).to eq(0)

      %w[tmp log public/assets vendor/bundle tmp/pids].each do |writable|
        expect(File.lstat("#{app}/#{writable}")).to be_directory, writable
        expect(owner("#{app}/#{writable}")).to eq(user.uid), writable
      end
      expect(owner("#{app}/tmp/cache/old")).to eq(user.uid)
      expect(owner(outside)).to eq(user.uid) # log was a link to it; it was replaced, not followed

      expect(File.read("#{app}/.bundle/config")).to include('BUNDLE_PATH: "vendor/bundle"', 'BUNDLE_FROZEN: "true"')
      expect(owner("#{app}/.bundle/config")).to eq(0)
      expect(File.read("#{dir}/gitconfig")).to include("directory = #{app}")
    end

    it 'can run again' do
      run_script
      _out, err, status = run_script
      expect(status).to be_success, err
      expect(File.read("#{dir}/gitconfig").scan("directory = #{app}").size).to eq(1)
    end
  end
end
