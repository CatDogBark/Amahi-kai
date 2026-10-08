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
    stub_const('AmahiHelper::APP_CATALOG', "#{dir}/catalog") # nothing fetched unless a test fetches it
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(true)
  end

  after { FileUtils.rm_rf(dir) }

  # The catalog's own repo (CATALOG_REPO), fetched by the update check. A local repo stands
  # in for GitHub, so the file protocol is let through.
  # Each installed app with a web page announced on the LAN through Avahi (mDNS).
  describe 'announcing apps' do
    let(:avahi) { "#{dir}/avahi" }
    let(:ran) { [] }

    before do
      FileUtils.mkdir_p(avahi)
      stub_const('AmahiHelper::AVAHI_SERVICES', avahi)
      stub_const('AmahiHelper::APP_PORTS', "#{dir}/app-ports.json")
      stub_const('AmahiHelper::UFW', "#{dir}/ufw")
      allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) } }
      allow(helper).to receive(:do_apps_status).and_return('docker' => true, 'apps' => { 'bittube' => {}, 'gitea' => {}, 'transmission' => {} })
    end

    it 'is its own operation, also run after installing and uninstalling' do
      expect(steps('apps.announce', {})).to eq([[:announce_apps]])
      expect(refusal('apps.announce', { 'app' => 'gitea' })).to eq('unexpected argument app')
    end

    it 'announces each installed app on the port it was given, and takes back what is no longer installed' do
      File.write("#{dir}/app-ports.json", { 'gitea' => [{ 'preferred' => 3300, 'host' => 3302, 'container' => 3000, 'protocol' => 'tcp' }] }.to_json)
      File.write("#{avahi}/amahi-app-jellyfin.service", 'from an uninstalled app')
      File.write("#{avahi}/ssh.service", 'not ours')
      expect(helper.do_announce_apps).to eq('announced' => %w[bittube gitea transmission])
      expect(Dir.children(avahi).sort).to eq(%w[amahi-app-bittube.service amahi-app-gitea.service amahi-app-transmission.service ssh.service])

      gitea = File.read("#{avahi}/amahi-app-gitea.service")
      expect(gitea).to include('<name replace-wildcards="yes">Gitea on %h</name>', '<type>_http._tcp</type>',
                               '<subtype>_gitea._sub._http._tcp</subtype>', '<port>3302</port>', '<txt-record>app=gitea</txt-record>')
      expect(File.read("#{avahi}/amahi-app-bittube.service")).to include('<port>8484</port>', '<subtype>_bittube._sub._http._tcp</subtype>')
      expect(ran).to include(['/usr/bin/systemctl', 'try-reload-or-restart', 'avahi-daemon.service'])

      ran.clear
      helper.do_announce_apps
      expect(ran).to be_empty # nothing changed, nothing reloaded
    end

    it "escapes an app's name for Avahi's XML" do
      expect(helper.xml_text('Tom & <Jerry>')).to eq('Tom &amp; &lt;Jerry&gt;')
    end

    it 'lets mDNS through UFW when it is on' do
      File.write("#{dir}/ufw", "#!/bin/sh\necho 'Status: active'\n")
      File.chmod(0o755, "#{dir}/ufw")
      helper.do_announce_apps
      expect(ran).to include(["#{dir}/ufw", 'allow', '5353/udp'])
    end

    it "announces an app whose page is HTTPS (web_tls) as HTTPS" do
      manifests = "#{dir}/manifests"
      FileUtils.mkdir_p(manifests)
      File.write("#{manifests}/bitshare.yml", { 'name' => 'bitShare', 'web_port' => 8443, 'web_tls' => true }.to_yaml)
      stub_const('AmahiHelper::APP_MANIFESTS', manifests)
      stub_const('AmahiHelper::APP_CATALOG', "#{dir}/no-catalog")
      allow(helper).to receive(:do_apps_status).and_return('docker' => true, 'apps' => { 'bitshare' => {} })
      expect(helper.do_announce_apps).to eq('announced' => %w[bitshare])
      expect(File.read("#{avahi}/amahi-app-bitshare.service"))
        .to include('<type>_https._tcp</type>', '<subtype>_bitshare._sub._https._tcp</subtype>', '<port>8443</port>')
    end

    it 'says why when it can announce nothing' do
      allow(helper).to receive(:do_apps_status).and_return('docker' => false, 'apps' => {})
      expect(helper.do_announce_apps).to eq('apps not announced on the LAN: Docker is not running')
      stub_const('AmahiHelper::AVAHI_SERVICES', "#{dir}/none")
      expect(helper.do_announce_apps).to eq('apps not announced on the LAN: avahi-daemon is not installed')
    end
  end

  describe 'the catalog repo' do
    let(:remote) { "#{dir}/remote" }
    let(:gitea) { File.read("#{catalog}/gitea.yml") }
    let(:jellyfin) { File.read("#{catalog}/jellyfin.yml") }
    let(:future) { "name: Future\ndescription: Later.\ncategory: media\nrequires: #{AmahiHelper::CATALOG_FORMAT + 1}\nwidgets: [1]\n" }
    let(:broken) { "name: Broken\ndescription: Unpinned.\ncategory: media\nimage: example/broken:latest\nrun_as: app\n" }

    def git(*args)
      out, err, status = Open3.capture3('git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com', *args, chdir: remote)
      raise "git #{args.join(' ')}: #{err}" unless status.success?

      out.strip
    end

    # Makes the remote's apps/ exactly +files+, commits, and returns the commit.
    def publish(files)
      FileUtils.rm_rf("#{remote}/apps")
      FileUtils.mkdir_p("#{remote}/apps")
      files.each { |name, content| File.write("#{remote}/apps/#{name}", content) }
      git('add', '-A')
      git('commit', '-q', '--allow-empty', '-m', 'Catalog')
      git('rev-parse', 'HEAD')
    end

    def kept
      Dir.children("#{dir}/catalog/apps").sort
    end

    before do
      FileUtils.mkdir_p(remote)
      git('init', '-q', '-b', 'main')
      stub_const('AmahiHelper::CATALOG_REPO', remote)
      stub_const('AmahiHelper::CATALOG_PROTOCOLS', %w[file])
      stub_const('AmahiHelper::CATALOG_SRC', "#{dir}/catalog-src")
      stub_const('AmahiHelper::CATALOG_STATUS', "#{dir}/catalog-status.json")
      stub_const('AmahiHelper::CATALOG_LOCK', "#{dir}/catalog.lock")
      allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
    end

    it "is fetched by the update check, after Amahi-kai's own" do
      expect(steps('system.check_update', {})).to eq([[:check_update], [:refresh_catalog], [:check_security_updates]])
      expect(helper::OPERATIONS).not_to have_key('apps.refresh_catalog')
    end

    it 'keeps the manifests that pass, says why the others were skipped, and is installed from first' do
      commit = publish('gitea.yml' => gitea.sub('memory: 1g', 'memory: 3g'), 'future.yml' => future,
                       'broken.yml' => broken, 'notes.md' => 'not a manifest')
      reply = helper.do_refresh_catalog
      expect(reply['catalog']).to include('commit' => commit, 'apps' => %w[future gitea], 'error' => nil,
                                          'problems' => [{ 'app' => 'broken', 'problem' => 'image must be name:tag@sha256:digest' }])
      expect(JSON.parse(File.read("#{dir}/catalog-status.json"))).to include('commit' => commit)
      expect(kept).to eq(%w[future.yml gitea.yml])

      expect(helper.app_manifest('gitea')[:memory]).to eq('3g')
      expect(helper.app_manifest('jellyfin')[:image]).to eq(AppCatalog.find('jellyfin')[:image]) # not fetched: the code's copy
      expect { helper.app_manifest('future') }
        .to raise_error(AmahiHelper::Refused, 'future needs a newer Amahi-kai: run System Update first')
      expect { helper.app_manifest('broken') }.to raise_error(AmahiHelper::Refused, /isn't in Amahi-kai's catalog/)
    end

    it 'takes a newer commit, and keeps what it has when the fetch fails or nothing passes' do
      publish('gitea.yml' => gitea)
      helper.do_refresh_catalog
      second = publish('gitea.yml' => gitea, 'jellyfin.yml' => jellyfin)
      expect(helper.do_refresh_catalog['catalog']).to include('commit' => second, 'apps' => %w[gitea jellyfin])

      publish('broken.yml' => broken)
      expect(helper.do_refresh_catalog['catalog'])
        .to include('commit' => second, 'apps' => %w[gitea jellyfin], 'error' => 'no app in the fetched catalog passes the checks')
      expect(kept).to eq(%w[gitea.yml jellyfin.yml])

      stub_const('AmahiHelper::CATALOG_REPO', "#{dir}/nowhere")
      status = helper.do_refresh_catalog['catalog']
      expect(status['error']).to start_with("couldn't fetch the catalog from GitHub: ")
      expect(status).to include('commit' => second)
      expect(kept).to eq(%w[gitea.yml jellyfin.yml])
    end

    it 'fetches over the allowed protocols only, and once at a time' do
      publish('gitea.yml' => gitea)
      stub_const('AmahiHelper::CATALOG_PROTOCOLS', %w[https])
      expect(helper.do_refresh_catalog['catalog']['error']).to include("transport 'file' not allowed")
      expect(File.exist?("#{dir}/catalog")).to be(false)

      File.open("#{dir}/catalog.lock", File::RDWR | File::CREAT) do |held|
        held.flock(File::LOCK_EX)
        expect(helper.do_refresh_catalog).to include('skipped' => 'the catalog is being fetched already')
      end
    end

    it "checks what the Apps pages show, and only the listing of an app that needs a newer format" do
      expect(helper.catalog_entry_problem('gitea', gitea)).to be_nil
      expect(helper.catalog_entry_problem('future', future)).to be_nil
      expect(helper.catalog_entry_problem('Gitea_2', gitea)).to eq('not an app id (lowercase letters and digits)')
      expect(helper.catalog_entry_problem('gitea', gitea.sub(/^name: .*$/, 'name: ""'))).to eq('name must be one line of text')
      expect(helper.catalog_entry_problem('gitea', gitea.sub('logo: https://', 'logo: http://'))).to eq('logo must be an https link')
      expect(helper.catalog_entry_problem('gitea', "requires: two\n#{gitea}")).to eq('requires must be a whole number from 1 to 999')
      expect(helper.catalog_entry_problem('gitea', 'name: [unclosed')).to start_with("can't be read")
      expect(helper.catalog_entry_problem('gitea', "#{gitea}# #{'x' * AmahiHelper::CATALOG_MAX_BYTES}")).to eq("over #{AmahiHelper::CATALOG_MAX_BYTES} bytes")
      expect(AmahiHelper::CATALOG_FORMAT).to eq(AppCatalog::FORMAT)
    end

    it "checks a whole catalog for its repo's CI, ports included" do
      out = StringIO.new
      expect(helper.check_catalog(catalog, out)).to eq(0)
      expect(out.string.lines.size).to eq(Dir["#{catalog}/*.yml"].size)

      FileUtils.mkdir_p("#{dir}/check")
      File.write("#{dir}/check/gitea.yml", gitea)
      File.write("#{dir}/check/forge.yml", gitea.sub('name: Gitea', 'name: Forge'))
      File.write("#{dir}/check/broken.yml", broken)
      out = StringIO.new
      expect(helper.check_catalog("#{dir}/check", out)).to eq(1)
      expect(out.string).to include('broken: image must be name:tag@sha256:digest', 'forge and gitea: both list host port 3300/tcp')
    end
  end

  describe 'the catalog' do
    let(:ids) { Dir[File.join(catalog, '*.yml')].map { |path| File.basename(path, '.yml') } }

    it "has the apps Troy chose, each a manifest the helper accepts" do
      expect(ids).to contain_exactly('jellyfin', 'vaultwarden', 'uptimekuma', 'gitea', 'transmission', 'bittube')
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
      # A reinstall (new shares) keeps the version the app runs: the last argument.
      expect(steps('apps.install', { 'app' => 'vaultwarden' }))
        .to eq([[:install_app, 'vaultwarden', helper.app_manifest('vaultwarden'), [], true], [:announce_apps]])
      image = helper.app_manifest('gitea')[:image]
      expect(steps('apps.uninstall', { 'app' => 'gitea' })).to eq([[:uninstall_app, 'gitea', image, false], [:announce_apps]])
      expect(steps('apps.uninstall', { 'app' => 'gitea', 'delete_data' => true })).to eq([[:uninstall_app, 'gitea', image, true], [:announce_apps]])
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
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/data', 'backup' => 'no' }])).to include("backup must be true or false")
      expect(failure('web_port' => 9999)).to include('web_port 9999 must be one of its ports')
      expect(failure('web_port' => 8500, 'web_tls' => 'yes')).to include('web_tls must be true or false')
      expect(failure('web_tls' => true)).to include('web_tls needs a web_port')
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
      stub_const('AmahiHelper::APP_PORTS', "#{dir}/app-ports.json")
      allow(helper).to receive(:port_bindable?).and_return(true)
      allow(helper).to receive(:do_app_firewall)
      allow(helper).to receive(:docker_output).and_return(nil) # the image isn't downloaded yet
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
      expect(helper.do_install_app('vaultwarden', manifest)).to eq(
        'app' => 'vaultwarden', 'container' => 'amahi-vaultwarden', 'image' => manifest[:image],
        'ports' => [{ 'preferred' => 8880, 'host' => 8880, 'container' => 8080, 'protocol' => 'tcp' }]
      )

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
                            '--user', '996:996', '--publish', '0.0.0.0:8880:8080/tcp',
                            '--volume', "#{apps_root}/vaultwarden/data:/data", manifest[:image]])
      expect(create.join(' ')).not_to include(token)

      path, content, mode = env_files.sole
      expect(content.lines(chomp: true)).to contain_exactly('ROCKET_PORT=8080', 'TZ=America/Chicago', "ADMIN_TOKEN=#{token}")
      expect(mode).to eq(0o600)
      expect(File.exist?(path)).to be false
      expect(helper).to have_received(:do_app_firewall)
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
        .to eq(['0.0.0.0:9091:9091/tcp', '0.0.0.0:51413:51413/tcp', '0.0.0.0:51413:51413/udp'])
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

      it "keeps the app's ports for its next install, unless its data goes too" do
        helper.do_uninstall_app('gitea', image, false)
        expect(JSON.parse(File.read("#{dir}/app-ports.json")).keys).to eq(['gitea'])
        helper.do_uninstall_app('gitea', image, true)
        expect(JSON.parse(File.read("#{dir}/app-ports.json"))).to eq({})
      end
    end

    it "lets what an app writes into a share stay editable over SMB, installing acl if needed" do
      share = { name: 'Downloads', path: "#{dir}/downloads", pooled: false, write: true }
      allow(helper).to receive(:app_share_mounts).and_return([])
      allow(File).to receive(:executable?).with('/usr/bin/setfacl').and_return(false)
      helper.do_install_app('transmission', helper.app_manifest('transmission'), [share])
      acl = ran.index { |argv| argv.first == '/usr/bin/find' }
      expect(ran[acl - 1]).to include('/usr/bin/apt-get', 'install', 'acl')
      expect(ran[acl]).to eq(['/usr/bin/find', "#{dir}/downloads", '-xdev', '-type', 'd', '-exec',
                              '/usr/bin/setfacl', '-d', '-m', 'u::rwx,g::rwx,o::rx', '{}', '+'])
      expect(ran.index { |argv| argv[1] == 'start' }).to be > acl
    end

    it "doesn't download an image it has already (so changing shares works offline)" do
      allow(helper).to receive(:docker_output).and_return("sha256:abc\n")
      helper.do_install_app('gitea', helper.app_manifest('gitea'))
      expect(ran.map { |argv| argv[1] }).not_to include('pull')
      expect(helper).to have_received(:docker_output).with('image', 'inspect', '--format', '{{.Id}}',
                                                           start_with('gitea/gitea@sha256:'))
    end

    describe 'updating' do
      let(:backups) { "#{dir}/app-backups" }
      let(:old_image) { "vaultwarden/server:1.37.2@sha256:#{'b' * 64}" }
      let(:manifest) { helper.app_manifest('vaultwarden') }
      let(:running) { { 'vaultwarden' => old_image } }
      let(:data) { "#{apps_root}/vaultwarden/data" }

      before do
        stub_const('AmahiHelper::APP_BACKUPS', backups)
        allow(helper).to receive(:app_image) { |id| running[id] }
        allow(helper).to receive(:disk_usage).and_return(10 * 1024**2)
        allow(helper).to receive(:free_space).and_return(20 * 1024**3)
        allow(helper).to receive(:app_health_problem).and_return(nil)
        allow(helper).to receive(:run_command) { |argv| fake_docker.call(argv) }
        helper.do_install_app('vaultwarden', manifest.merge(image: old_image))
        File.write("#{data}/db.sqlite3", 'before')
        ran.clear
      end

      # Copies for real, and the new version changes its data the way a database upgrade would.
      let(:fake_docker) do
        lambda do |argv|
          ran << argv
          accounts[argv.last] = account(argv.last, 996) if argv.first == '/usr/sbin/useradd'
          FileUtils.cp_r(argv[-2], argv[-1], preserve: true) if argv.first == '/usr/bin/cp'
          if argv[1] == 'create'
            running['vaultwarden'] = argv.last
            File.write("#{data}/db.sqlite3", 'upgraded') if argv.last == manifest[:image]
          end
          nil
        end
      end

      def backup_info
        JSON.parse(File.read("#{backups}/vaultwarden.json"))
      end

      it "copies the data, starts the new version, and keeps the copy for Undo" do
        reply = helper.do_update_app('vaultwarden', manifest, [])
        expect(reply).to include('updated' => true, 'image' => manifest[:image], 'from' => old_image)
        commands = ran.map { |argv| argv.first(2).join(' ') }
        expect(commands.index('/usr/bin/docker stop')).to be < commands.index('/usr/bin/cp -a')
        expect(commands.index('/usr/bin/cp -a')).to be < commands.index('/usr/bin/docker create')
        expect(ran.last).to eq(['/usr/bin/docker', 'image', 'rm', old_image, { allow_failure: true }])
        expect(File.read("#{backups}/vaultwarden/data/db.sqlite3")).to eq('before')
        expect(backup_info).to include('from' => old_image, 'to' => manifest[:image], 'folders' => ['data'])
        expect(File.read("#{data}/db.sqlite3")).to eq('upgraded')
      end

      it "goes back to the old version and its data when the new one isn't healthy" do
        allow(helper).to receive(:app_health_problem).and_return('it stopped (exit code 1)')
        reply = helper.do_update_app('vaultwarden', manifest, [])
        expect(reply).to eq('app' => 'vaultwarden', 'updated' => false, 'image' => old_image, 'problem' => 'it stopped (exit code 1)')
        expect(File.read("#{data}/db.sqlite3")).to eq('before')
        expect(running['vaultwarden']).to eq(old_image)
        expect(File.exist?("#{backups}/vaultwarden.json")).to be false
        expect(ran.map { |argv| argv[1..2] }).not_to include(['image', 'rm'])
      end

      it "goes back too when the new version can't even be created" do
        allow(helper).to receive(:run_command) do |argv|
          raise AmahiHelper::Failed, 'docker exited 125: invalid mount' if argv[1] == 'create' && argv.last == manifest[:image]
          fake_docker.call(argv)
        end
        expect(helper.do_update_app('vaultwarden', manifest, [])).to include('updated' => false, 'problem' => 'docker exited 125: invalid mount')
        expect(running['vaultwarden']).to eq(old_image)
      end

      it "refuses before stopping anything when the copy wouldn't fit, or there's nothing to update" do
        allow(helper).to receive(:free_space).and_return(512 * 1024**2)
        expect { helper.do_update_app('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, /isn't room to copy vaultwarden's data/)
        running['vaultwarden'] = manifest[:image]
        expect { helper.do_update_app('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, /the catalog's version, already/)
        running.delete('vaultwarden')
        expect { helper.do_update_app('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, "vaultwarden isn't installed")
        expect(ran).to be_empty
      end

      it 'leaves out folders the manifest marks backup: false' do
        jellyfin = helper.app_manifest('jellyfin')
        FileUtils.mkdir_p(%W[#{apps_root}/jellyfin/config #{apps_root}/jellyfin/cache])
        expect(helper.app_backup_folders('jellyfin', jellyfin)).to eq(["#{apps_root}/jellyfin/config"])
      end

      it 'undoes the update within 30 days: the old version and data come back, and the copy goes' do
        helper.do_update_app('vaultwarden', manifest, [])
        reply = helper.do_undo_app_update('vaultwarden', manifest, [])
        expect(reply).to include('image' => old_image)
        expect(File.read("#{data}/db.sqlite3")).to eq('before')
        expect(running['vaultwarden']).to eq(old_image)
        expect(File.exist?("#{backups}/vaultwarden")).to be false
        expect { helper.do_undo_app_update('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, 'vaultwarden has no update to undo')
      end

      it 'keeps one copy per app, the newest, and deletes it after 30 days' do
        helper.do_update_app('vaultwarden', manifest, [])
        File.write("#{backups}/vaultwarden.json", backup_info.merge('taken_at' => (Time.now - 31 * 86_400).utc.iso8601).to_json)
        expect { helper.do_undo_app_update('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, /over 30 days old/)
        File.write("#{backups}/stray.json", '{}') # no copy beside it
        expect(helper.do_prune_app_backups).to eq('removed' => %w[stray vaultwarden])
        expect(Dir.children(backups)).to eq([])
      end

      it "keeps the version an app runs when it's installed again (new shares), so only Update changes it" do
        running['vaultwarden'] = old_image
        reply = helper.do_install_app('vaultwarden', manifest, [], true)
        expect(reply['image']).to eq(old_image)
        expect(helper).to have_received(:say).with('Keeping the version it runs (1.37.2)')
      end

      it "uninstalls the image the app runs, and drops its copy with its data" do
        helper.do_update_app('vaultwarden', manifest, [])
        helper.do_uninstall_app('vaultwarden', 'something:else', true)
        expect(ran).to include(['/usr/bin/docker', 'image', 'rm', manifest[:image], { allow_failure: true }])
        expect(File.exist?("#{backups}/vaultwarden.json")).to be false
      end
    end

    describe 'ports' do
      def published(app)
        ran.select { |argv| argv[1] == 'create' && argv.include?("amahi.app=#{app}") }.last
           .each_cons(2).select { |flag, _| flag == '--publish' }.map(&:last)
      end

      def busy(*ports)
        allow(helper).to receive(:port_bindable?) { |port, _protocol| !ports.include?(port) }
      end

      it "gives an app its catalog ports, and records them where the Apps page reads them" do
        helper.do_install_app('gitea', helper.app_manifest('gitea'))
        expect(published('gitea')).to eq(['0.0.0.0:3300:3000/tcp', '0.0.0.0:2222:2222/tcp'])
        expect(JSON.parse(File.read("#{dir}/app-ports.json"))['gitea']).to eq(
          [{ 'preferred' => 3300, 'host' => 3300, 'container' => 3000, 'protocol' => 'tcp' },
           { 'preferred' => 2222, 'host' => 2222, 'container' => 2222, 'protocol' => 'tcp' }]
        )
      end

      it 'takes the next free port when one is in use, says so, and keeps it on the next install' do
        busy(3300, 3301)
        reply = helper.do_install_app('gitea', helper.app_manifest('gitea'))
        expect(reply['ports'].map { |p| p['host'] }).to eq([3302, 2222])
        expect(helper).to have_received(:say).with('Port 3300 is in use, so it gets port 3302')

        busy # 3300 is free again, but the app keeps the port it was given
        helper.do_install_app('gitea', helper.app_manifest('gitea'))
        expect(published('gitea')).to eq(['0.0.0.0:3302:3000/tcp', '0.0.0.0:2222:2222/tcp'])
      end

      it "never gives one app another app's port, even while that app is uninstalled" do
        File.write("#{dir}/app-ports.json", { 'other' => [{ 'preferred' => 9091, 'host' => 9091, 'protocol' => 'tcp' }] }.to_json)
        helper.do_install_app('transmission', helper.app_manifest('transmission'))
        expect(published('transmission').first).to eq('0.0.0.0:9092:9091/tcp')
      end

      it "keeps a TCP and UDP pair on one port, and skips the NAS's own ports" do
        busy(51_413)
        helper.do_install_app('transmission', helper.app_manifest('transmission'))
        expect(published('transmission').drop(1)).to eq(['0.0.0.0:51414:51413/tcp', '0.0.0.0:51414:51413/udp'])
        expect(helper.port_free?(3000, ['tcp'], [])).to be false
        expect(helper.port_free?(80, ['tcp'], [])).to be false
      end
    end
  end

  describe 'shares' do
    let(:files) { "#{dir}/files" }
    let(:drives) { "#{dir}/mnt" }
    let(:smb_conf) do
      <<~CONF
        [global]
        \tworkgroup = HOME
        \tpath = /etc
        [homes]
        \tpath = /home
        [Movies]
        \tcomment = Movies
        \tpath = #{files}/movies
        \tvfs objects = greyhole
        [Downloads]
        \tpath = #{files}/downloads
        [Outside]
        \tpath = /etc
        [Odd, Name]
        \tpath = #{files}/odd
      CONF
    end
    let(:transmission) { helper.app_manifest('transmission') }
    let(:jellyfin) { helper.app_manifest('jellyfin') }

    before do
      FileUtils.mkdir_p(%W[#{files}/movies #{files}/downloads #{files}/odd #{drives}/storage-1/Movies #{drives}/storage-2])
      File.write("#{dir}/smb.conf", smb_conf)
      File.write("#{dir}/greyhole.conf", "storage_pool_drive = #{drives}/storage-1, min_free: 10gb\n" \
                                         "storage_pool_drive = #{drives}/storage-2, min_free: 10gb\n")
      stub_const('AmahiHelper::SMB_CONF', "#{dir}/smb.conf")
      stub_const('AmahiHelper::GREYHOLE_CONF', "#{dir}/greyhole.conf")
      stub_const('AmahiHelper::DRIVES_ROOT', drives)
      allow(helper).to receive(:share_root).and_return(files)
    end

    def choose(manifest, shares)
      helper.app_share_choices(shares, 'transmission', manifest)
    end

    def refused(manifest, shares)
      choose(manifest, shares)
      nil
    rescue AmahiHelper::Refused => e
      e.message
    end

    it "finds shares by name in smb.conf, with their folders and whether Greyhole pools them" do
      expect(choose(transmission, [{ 'name' => 'movies' }, { 'name' => 'Downloads', 'write' => true }])).to eq(
        [{ name: 'Movies', path: "#{files}/movies", pooled: true, write: false },
         { name: 'Downloads', path: "#{files}/downloads", pooled: false, write: true }]
      )
      expect(choose(transmission, nil)).to eq([])
    end

    it 'refuses shares that are not there, writing where the app or Greyhole says no, and odd requests' do
      expect(refused(transmission, [{ 'name' => 'Photos' }])).to eq('"Photos" isn\'t one of the NAS\'s shares')
      expect(refused(transmission, [{ 'name' => 'homes' }])).to eq('"homes" isn\'t one of the NAS\'s shares')
      expect(refused(transmission, [{ 'name' => 'Outside' }])).to include("isn't in the share root")
      expect(refused(transmission, [{ 'name' => 'Odd, Name' }])).to include("name can't be a folder in an app")
      expect(refused(transmission, [{ 'name' => 'Movies', 'write' => true }])).to eq('share Movies is pooled by Greyhole, so apps can only read it')
      expect(refused(jellyfin, [{ 'name' => 'Downloads', 'write' => true }])).to eq('transmission only reads shares')
      expect(refused(transmission, [{ 'name' => 'Downloads', 'path' => '/etc' }])).to include('each share must be')
      expect(refused(transmission, [{ 'name' => 'Downloads' }, { 'name' => 'downloads' }])).to eq('a share is listed twice')
      expect(refused(transmission, 'Downloads')).to include('must be a list')
    end

    it "mounts shares at /shares/<name>, a pooled share with its copy folders, and lets a writer join the users group" do
      allow(helper).to receive(:group_id).and_call_original
      allow(helper).to receive(:group_id).with('users').and_return(100)
      mounts = helper.app_share_mounts(choose(transmission, [{ 'name' => 'Movies' }, { 'name' => 'Downloads', 'write' => true }]))
      expect(mounts).to eq(['--group-add', '100',
                            '--mount', "type=bind,source=#{files}/movies,target=/shares/Movies,readonly",
                            '--mount', "type=bind,source=#{drives}/storage-1/Movies,target=#{drives}/storage-1/Movies,readonly",
                            '--mount', "type=bind,source=#{files}/downloads,target=/shares/Downloads"])
      expect(helper.app_share_mounts(choose(transmission, [{ 'name' => 'Downloads' }])))
        .to eq(['--mount', "type=bind,source=#{files}/downloads,target=/shares/Downloads,readonly"])
    end

    it "is checked when the request comes in" do
      allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(true)
      expect(refusal('apps.install', { 'app' => 'jellyfin', 'shares' => [{ 'name' => 'Downloads', 'write' => true }] }))
        .to eq('jellyfin only reads shares')
      expect(steps('apps.install', { 'app' => 'jellyfin', 'shares' => [{ 'name' => 'Movies' }] }).first[3])
        .to eq([{ name: 'Movies', path: "#{files}/movies", pooled: true, write: false }])
    end
  end

  describe 'health after an update' do
    let(:manifest) { helper.app_manifest('gitea') }
    let(:clock) { [0] }

    before do
      allow(helper).to receive(:pause) { |seconds| clock[0] += seconds }
      allow(helper).to receive(:monotonic_now) { clock[0] }
      allow(helper).to receive(:app_restart_count).and_return(0)
    end

    def states(*list)
      allow(helper).to receive(:app_state).and_return(*list)
    end

    it "trusts Docker's own health check where the image has one" do
      states({ 'Status' => 'running', 'Health' => { 'Status' => 'starting' } }, { 'Status' => 'running', 'Health' => { 'Status' => 'healthy' } })
      expect(helper.app_health_problem('gitea', manifest)).to be_nil
      states({ 'Status' => 'running', 'Health' => { 'Status' => 'unhealthy' } })
      expect(helper.app_health_problem('gitea', manifest)).to eq("Docker's health check for it failed")
    end

    it 'otherwise wants its web page answering, and it still running 10 seconds later' do
      allow(helper).to receive(:app_answers?).and_return(false, true)
      states({ 'Status' => 'running' })
      expect(helper.app_health_problem('gitea', manifest)).to be_nil
      expect(clock[0]).to eq(15)
    end

    it 'gives up when it stops, keeps restarting, or takes over 5 minutes' do
      states({ 'Status' => 'exited', 'ExitCode' => 3 })
      expect(helper.app_health_problem('gitea', manifest)).to eq('it stopped (exit code 3)')
      states({ 'Status' => 'restarting' })
      expect(helper.app_health_problem('gitea', manifest)).to eq("it didn't come up within 5 minutes")
      states(nil)
      expect(helper.app_health_problem('gitea', manifest)).to eq('its container is gone')
    end

    it "asks the app's own port, the one it was given" do
      server = TCPServer.new('127.0.0.1', 0)
      Thread.new { (client = server.accept).readpartial(100) && client.write("HTTP/1.1 302 Found\r\n\r\n") && client.close }
      File.write("#{dir}/app-ports.json", { 'gitea' => [{ 'preferred' => 3300, 'host' => server.addr[1], 'protocol' => 'tcp' }] }.to_json)
      stub_const('AmahiHelper::APP_PORTS', "#{dir}/app-ports.json")
      expect(helper.app_answers?('gitea', manifest)).to be true
      server.close
      expect(helper.app_answers?('gitea', manifest)).to be false
    end
  end

  it 'sees a port as in use while something listens on it, TCP or UDP' do
    server = TCPServer.new('0.0.0.0', 0)
    port = server.addr[1]
    expect(helper.port_bindable?(port, 'tcp')).to be false
    server.close
    expect(helper.port_bindable?(port, 'tcp')).to be true
    udp = UDPSocket.new.tap { |socket| socket.bind('0.0.0.0', 0) }
    expect(helper.port_bindable?(udp.addr[1], 'udp')).to be false
  ensure
    udp&.close
  end

  describe 'the app firewall' do
    let(:ip_output) do
      [{ 'ifname' => 'lo', 'addr_info' => [{ 'family' => 'inet', 'local' => '127.0.0.1', 'prefixlen' => 8 }] },
       { 'ifname' => 'ens18', 'addr_info' => [{ 'family' => 'inet', 'local' => '192.168.1.111', 'prefixlen' => 24 },
                                              { 'family' => 'inet', 'local' => '10.20.0.5', 'prefixlen' => 16 }] },
       { 'ifname' => 'ens19', 'addr_info' => [{ 'family' => 'inet', 'local' => '203.0.113.7', 'prefixlen' => 24 }] },
       { 'ifname' => 'docker0', 'addr_info' => [{ 'family' => 'inet', 'local' => '172.17.0.1', 'prefixlen' => 16 }] },
       { 'ifname' => 'tailscale0', 'addr_info' => [{ 'family' => 'inet', 'local' => '100.64.96.4', 'prefixlen' => 32 }] }].to_json
    end
    let(:ran) { [] }
    let(:jump_exists) { false }

    before do
      allow(File).to receive(:executable?).with('/usr/sbin/iptables').and_return(true)
      allow(helper).to receive(:capture).and_call_original
      allow(helper).to receive(:capture).with(%w[/usr/sbin/ip -j -4 addr show]).and_return(ip_output)
      allow(helper).to receive(:run_command) do |argv|
        ran << argv
        'ignored: iptables exited 1: Bad rule' if argv.include?('-C') && !jump_exists
      end
    end

    it "is run each time Docker starts" do
      expect(steps('apps.firewall', {})).to eq([[:app_firewall]])
      unit = File.read(Rails.root.join('config/systemd/amahi-kai-app-firewall.service'))
      expect(unit).to include('ExecStart=/usr/local/sbin/amahi-helper apps.firewall', 'After=docker.service',
                              'PartOf=docker.service', 'WantedBy=docker.service')
    end

    it "lets in only the NAS's private subnets and Tailscale, and drops the rest" do
      expect(helper.do_app_firewall).to eq('lan' => ['192.168.1.0/24', '10.20.0.0/16'])
      rules = ran.map { |argv| argv.reject { |arg| arg.is_a?(Hash) } }
      expect(rules).to eq([
                            %w[/usr/sbin/iptables -w -N DOCKER-USER], %w[/usr/sbin/iptables -w -N AMAHI-APPS],
                            %w[/usr/sbin/iptables -w -F AMAHI-APPS],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS ! -o docker0 -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -i docker0 -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -i tailscale0 -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -s 192.168.1.0/24 -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -s 10.20.0.0/16 -j RETURN],
                            %w[/usr/sbin/iptables -w -A AMAHI-APPS -j DROP],
                            %w[/usr/sbin/iptables -w -C DOCKER-USER -j AMAHI-APPS],
                            %w[/usr/sbin/iptables -w -I DOCKER-USER 1 -j AMAHI-APPS]
                          ])
    end

    context 'when Docker already jumps to it' do
      let(:jump_exists) { true }

      it 'rebuilds the chain without adding a second jump' do
        helper.do_app_firewall
        expect(ran.map { |argv| argv[2..3] }).not_to include(%w[-I DOCKER-USER])
      end
    end

    it 'reports whether the rules are in place, for the security audit' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/iptables -w -S AMAHI-APPS])
                                        .and_return("-N AMAHI-APPS\n-A AMAHI-APPS -i tailscale0 -j RETURN\n-A AMAHI-APPS -j DROP\n")
      expect(helper.app_firewall_active?).to be false # DOCKER-USER doesn't jump to it
      allow(helper).to receive(:run_command).and_return(nil)
      expect(helper.app_firewall_active?).to be true
      allow(helper).to receive(:capture).with(%w[/usr/sbin/iptables -w -S AMAHI-APPS]).and_raise(AmahiHelper::Failed, 'No chain')
      expect(helper.app_firewall_active?).to be false
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
      allow(helper).to receive(:app_firewall_active?).and_return(false)
      expect(helper.do_docker_ports).to eq('ports' => [], 'limited' => false)
    end

    it "lists every running container's published ports for the security audit" do
      docker_says("amahi-gitea\t0.0.0.0:3300->3000/tcp\nother\t\n")
      allow(helper).to receive(:app_firewall_active?).and_return(true)
      expect(helper.do_docker_ports).to eq('ports' => ["amahi-gitea\t0.0.0.0:3300->3000/tcp", "other\t"], 'limited' => true)
    end
  end
end
