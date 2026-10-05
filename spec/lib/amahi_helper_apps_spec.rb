require 'rails_helper'

# The root helper's app operations (docs/plans/apps.md, P4.1): the web app names an app, and the
# helper builds its container from the catalog's manifest, with the app's own user, folders and
# secrets. Nothing here runs Docker or needs root.
RSpec.describe 'AmahiHelper apps' do
  let(:helper) { AmahiHelper }
  let(:catalog) { Rails.root.join('config/apps').to_s }
  let(:dir) { Dir.mktmpdir }

  before(:all) { Privileged.operations } # loads the helper's source once

  def refusal(op, args)
    helper.validate(op, args)
    nil
  rescue AmahiHelper::Refused => e
    e.message
  end

  def steps(op, args)
    helper.plan(op, helper.validate(op, args))
  end

  def account(name, uid)
    Etc::Passwd.new(name, 'x', uid, uid, '', '/nonexistent', '/usr/sbin/nologin')
  end

  before do
    stub_const('AmahiHelper::APP_MANIFESTS', catalog)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(true)
  end

  after { FileUtils.rm_rf(dir) }

  describe 'the catalog' do
    let(:ids) { Dir[File.join(catalog, '*.yml')].map { |path| File.basename(path, '.yml') } }

    it 'has the five apps Troy chose, each a manifest the helper accepts' do
      expect(ids).to contain_exactly('jellyfin', 'vaultwarden', 'uptimekuma', 'gitea', 'transmission')
      ids.each do |id|
        manifest = helper.app_manifest(id)
        expect(manifest[:image]).to match(/:[^@]+@sha256:\h{64}\z/), "#{id} isn't pinned by tag and digest"
      end
    end

    it 'gives every app host ports of its own' do
      taken = ids.flat_map { |id| helper.app_manifest(id)[:ports].map { |p| [p[:host], p[:protocol]] } }
      expect(taken).to eq(taken.uniq)
    end

    it "lists each app's web port among its ports, and shows the same apps as AppCatalog" do
      AppCatalog.reload!
      AppCatalog.all.each do |app|
        expect(app[:ports].map { |p| p[:host] }).to include(app[:web_port])
      end
      expect(AppCatalog.all.map { |app| app[:identifier] }).to match_array(ids)
    end
  end

  describe 'requests' do
    it 'takes only the name of an app in the catalog' do
      expect(refusal('apps.install', { 'app' => 'Jellyfin' })).to include("isn't one Amahi-kai knows")
      expect(refusal('apps.install', { 'app' => '../jellyfin' })).to include("isn't one Amahi-kai knows")
      expect(refusal('apps.install', { 'app' => 'portainer' })).to eq(%(app "portainer" isn't in Amahi-kai's catalog))
      expect(refusal('apps.install', { 'app' => 'jellyfin', 'image' => 'alpine' })).to eq('unexpected argument image')
    end

    it "refuses while Docker isn't installed" do
      allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(false)
      expect(refusal('apps.start', { 'app' => 'jellyfin' })).to eq("docker isn't installed")
    end

    it 'starts, stops and restarts only the app container' do
      expect(steps('apps.start', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker start amahi-gitea]])
      expect(steps('apps.stop', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker stop --time 30 amahi-gitea]])
      expect(steps('apps.restart', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker restart --time 30 amahi-gitea]])
    end

    it 'installs from the manifest, and uninstalls keeping the data unless asked' do
      expect(steps('apps.install', { 'app' => 'vaultwarden' })).to eq([[:install_app, 'vaultwarden', helper.app_manifest('vaultwarden')]])
      image = helper.app_manifest('gitea')[:image]
      expect(steps('apps.uninstall', { 'app' => 'gitea' })).to eq([[:uninstall_app, 'gitea', image, false]])
      expect(steps('apps.uninstall', { 'app' => 'gitea', 'delete_data' => true })).to eq([[:uninstall_app, 'gitea', image, true]])
      expect(refusal('apps.uninstall', { 'app' => 'gitea', 'delete_data' => 'yes' })).to include('delete_data')
    end
  end

  describe 'manifests' do
    let(:good) do
      { 'image' => "example/app:1.0@sha256:#{'a' * 64}", 'run_as' => 'app',
        'ports' => [{ 'host' => 8500, 'container' => 80 }], 'folders' => [{ 'name' => 'data', 'path' => '/data' }],
        'environment' => { 'TZ' => '{{timezone}}' }, 'secrets' => [{ 'env' => 'TOKEN', 'label' => 'Token' }] }
    end

    def failure(changes)
      stub_const('AmahiHelper::APP_MANIFESTS', dir)
      File.write("#{dir}/test.yml", good.merge(changes).to_yaml)
      helper.app_manifest('test')
      nil
    rescue AmahiHelper::Failed => e
      e.message
    end

    it 'reads a good one, with the default memory limit' do
      expect(failure({})).to be_nil
      expect(helper.app_manifest('test')).to include(memory: '1g', run_as: 'app',
                                                     ports: [{ host: 8500, container: 80, protocol: 'tcp' }],
                                                     secrets: ['TOKEN'])
    end

    it 'fails on anything the helper would have to trust' do
      expect(failure('image' => 'example/app:latest')).to include('image must be name:tag@sha256:digest')
      expect(failure('run_as' => 'root')).to include('run_as must be app or image')
      expect(failure('memory' => 'lots')).to include('memory "lots"')
      expect(failure('ports' => [{ 'host' => 445, 'container' => 445 }])).to include('must be from 1024 to 65535')
      expect(failure('ports' => [{ 'host' => 3000, 'container' => 3000 }])).to include('host port 3000 belongs to the NAS')
      expect(failure('ports' => [{ 'host' => 8500, 'container' => 80 }, { 'host' => 8500, 'container' => 81 }])).to include('listed twice')
      expect(failure('ports' => [{ 'host' => 8500, 'container' => 80, 'protocol' => 'sctp' }])).to include('must be tcp or udp')
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/data/../etc' }])).to include('normalized path')
      expect(failure('folders' => [{ 'name' => '../x', 'path' => '/data' }])).to include('folder name')
      expect(failure('environment' => { 'bad name' => 'x' })).to include("isn't valid")
      expect(failure('environment' => { 'X' => "a\nb" })).to include('one line')
      expect(failure('environment' => { 'TOKEN' => 'fixed' })).to include('set in environment too')
    end
  end

  describe 'installing' do
    let(:apps_root) { "#{dir}/apps" }
    let(:secrets_dir) { "#{dir}/app-secrets" }
    let(:ran) { [] }
    let(:env_files) { [] }
    let(:accounts) { {} }

    before do
      stub_const('AmahiHelper::APPS_ROOT', apps_root)
      stub_const('AmahiHelper::APP_SECRETS', secrets_dir)
      stub_const('AmahiHelper::RUN_DIR', dir)
      allow(helper).to receive(:say)
      allow(helper).to receive(:host_timezone).and_return('America/Chicago')
      allow(helper).to receive(:group_id).and_call_original
      allow(helper).to receive(:group_id).with('amahi').and_return(Process.gid)
      allow(File).to receive(:lchown)
      allow(File).to receive(:chown)
      allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
      allow(helper).to receive(:passwd) { |name| accounts[name] }
      allow(helper).to receive(:run_command) do |argv|
        ran << argv
        accounts[argv.last] = account(argv.last, 996) if argv.first == '/usr/sbin/useradd'
        if argv[1] == 'create'
          path = argv[argv.index('--env-file') + 1]
          env_files << [path, File.read(path), File.stat(path).mode & 0o777]
        end
        nil
      end
    end

    it "creates the app's user and folders, keeps secrets off the command line, and starts the container" do
      manifest = helper.app_manifest('vaultwarden')
      expect(helper.do_install_app('vaultwarden', manifest)).to eq('app' => 'vaultwarden', 'container' => 'amahi-vaultwarden')

      expect(ran.first).to eq(['/usr/sbin/useradd', '--system', '--user-group', '--no-create-home', '--home-dir', '/nonexistent',
                               '--shell', '/usr/sbin/nologin', 'app-vaultwarden'])
      expect(File.stat("#{apps_root}/vaultwarden/data").mode & 0o777).to eq(0o750)
      expect(File).to have_received(:lchown).with(996, 996, "#{apps_root}/vaultwarden/data")

      token = JSON.parse(File.read("#{secrets_dir}/vaultwarden.json"))['ADMIN_TOKEN']
      expect(token).to match(/\A[A-Za-z0-9]{32}\z/)

      docker = ran.drop(1).map(&:first).uniq
      expect(docker).to eq(['/usr/bin/docker'])
      expect(ran.drop(1).map { |argv| argv[1] }).to eq(%w[pull rm create start])
      expect(ran[1]).to eq(['/usr/bin/docker', 'pull', manifest[:image], { stream: true }])
      create = ran.find { |argv| argv[1] == 'create' }
      expect(create).to eq(['/usr/bin/docker', 'create', '--name', 'amahi-vaultwarden', '--restart', 'unless-stopped',
                            '--memory', '512m', '--label', 'amahi.app=vaultwarden', '--env-file', env_files.sole[0],
                            '--user', '996:996', '--publish', '8880:8080/tcp',
                            '--volume', "#{apps_root}/vaultwarden/data:/data", manifest[:image]])
      expect(create.join(' ')).not_to include(token)

      path, content, mode = env_files.sole
      expect(content.lines(chomp: true)).to contain_exactly('ROCKET_PORT=8080', 'TZ=America/Chicago', "ADMIN_TOKEN=#{token}")
      expect(mode).to eq(0o600)
      expect(File.exist?(path)).to be false
    end

    it 'reuses the user, folders and secrets of an earlier install' do
      manifest = helper.app_manifest('vaultwarden')
      helper.do_install_app('vaultwarden', manifest)
      File.write("#{apps_root}/vaultwarden/data/db.sqlite3", 'kept')
      token = JSON.parse(File.read("#{secrets_dir}/vaultwarden.json"))['ADMIN_TOKEN']
      ran.clear

      helper.do_install_app('vaultwarden', manifest)
      expect(ran.map(&:first)).not_to include('/usr/sbin/useradd')
      expect(File.read("#{apps_root}/vaultwarden/data/db.sqlite3")).to eq('kept')
      expect(JSON.parse(File.read("#{secrets_dir}/vaultwarden.json"))['ADMIN_TOKEN']).to eq(token)
    end

    it 'fills in the uid and gid for images that drop to them themselves, and gives no --user' do
      helper.do_install_app('transmission', helper.app_manifest('transmission'))
      create = ran.find { |argv| argv[1] == 'create' }
      expect(create).not_to include('--user')
      expect(create.each_cons(2).select { |flag, _| flag == '--publish' }.map(&:last))
        .to eq(['9091:9091/tcp', '51413:51413/tcp', '51413:51413/udp'])
      expect(env_files.sole[1].lines(chomp: true)).to include('PUID=996', 'PGID=996', 'USER=admin')
      expect(env_files.sole[1]).to match(/^PASS=[A-Za-z0-9]{32}$/)
    end

    it "refuses a symlink where the app's folder should be" do
      FileUtils.mkdir_p(apps_root)
      File.symlink('/etc', "#{apps_root}/gitea")
      expect { helper.do_install_app('gitea', helper.app_manifest('gitea')) }.to raise_error(AmahiHelper::Failed, /isn't a folder/)
    end

    it 'refuses an existing account that is not a system account' do
      accounts['app-gitea'] = account('app-gitea', 1001)
      expect { helper.do_install_app('gitea', helper.app_manifest('gitea')) }.to raise_error(AmahiHelper::Failed, /isn't a system account/)
      expect(ran).to be_empty
    end

    describe 'uninstalling' do
      before do
        helper.do_install_app('gitea', helper.app_manifest('gitea'))
        ran.clear
      end

      let(:image) { helper.app_manifest('gitea')[:image] }

      it 'removes the container and image and keeps the data' do
        expect(helper.do_uninstall_app('gitea', image, false)).to eq('app' => 'gitea', 'data_kept' => true)
        expect(ran).to eq([['/usr/bin/docker', 'rm', '--force', 'amahi-gitea', { allow_failure: true }],
                           ['/usr/bin/docker', 'image', 'rm', image, { allow_failure: true }]])
        expect(File.directory?("#{apps_root}/gitea/data")).to be true
      end

      it 'deletes the folders, secrets file and user when asked' do
        File.write("#{secrets_dir}/gitea.json", '{}')
        expect(helper.do_uninstall_app('gitea', image, true)).to eq('app' => 'gitea', 'data_kept' => false)
        expect(File.exist?("#{apps_root}/gitea")).to be false
        expect(File.exist?("#{secrets_dir}/gitea.json")).to be false
        expect(ran.last).to eq(['/usr/sbin/userdel', 'app-gitea', { allow_failure: true }])
      end
    end
  end

  describe 'status' do
    def docker_says(out, success: true)
      allow(Open3).to receive(:capture3).and_return([out, '', instance_double(Process::Status, success?: success)])
    end

    it "reads each app container's state from its label" do
      docker_says(<<~OUT)
        {"Names":"amahi-gitea","State":"running","Status":"Up 2 hours","Image":"gitea/gitea:1.27.3-rootless","Labels":"amahi.app=gitea,maintainer=x"}
        {"Names":"amahi-jellyfin","State":"exited","Status":"Exited (1) 3 minutes ago","Image":"jellyfin/jellyfin:12.1","Labels":"org.opencontainers.image.title=Jellyfin,amahi.app=jellyfin"}
        not json
      OUT
      expect(helper.do_apps_status).to eq(
        'docker' => true,
        'apps' => { 'gitea' => { 'state' => 'running', 'status' => 'Up 2 hours', 'image' => 'gitea/gitea:1.27.3-rootless' },
                    'jellyfin' => { 'state' => 'exited', 'status' => 'Exited (1) 3 minutes ago', 'image' => 'jellyfin/jellyfin:12.1' } }
      )
    end

    it "says when Docker isn't running" do
      docker_says('', success: false)
      expect(helper.do_apps_status).to eq('docker' => false, 'apps' => {})
      expect(helper.do_docker_ports).to eq('ports' => [])
    end

    it "lists every running container's published ports for the security audit" do
      docker_says("amahi-gitea\t0.0.0.0:3300->3000/tcp\nother\t\n")
      expect(helper.do_docker_ports).to eq('ports' => ["amahi-gitea\t0.0.0.0:3300->3000/tcp", "other\t"])
    end
  end
end
