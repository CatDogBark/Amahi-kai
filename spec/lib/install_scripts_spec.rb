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

  it 'installs and enables the check for updates' do
    text = File.read(Rails.root.join('bin/amahi-install-helper'))
    expect(text).to include('amahi-kai-update-check.service amahi-kai-update-check.timer')
    expect(text).to include('systemctl enable --now amahi-kai-update-check.timer')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-update-check.service')))
      .to include('ExecStart=/usr/local/sbin/amahi-helper system.check_update')
    expect(File.read(Rails.root.join('config/systemd/amahi-kai-update-check.timer'))).to include('OnUnitActiveSec=6h')
  end

  it 'stops early with nothing new, unless repairing, and shares the lock with the check' do
    text = File.read(Rails.root.join('bin/amahi-update'))
    expect(text).to include('Already up to date', '--repair) REPAIR=true', 'REPAIR_FLAG=/run/amahi-kai-update.repair')
    expect(text).to include('flock -w 90 9', 'refresh_update_status')
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
