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
    stub_const('AmahiHelper::APP_DEFINITIONS', "#{dir}/app-definitions")
    stub_const('AmahiHelper::APP_RECORDS_LOCK', "#{dir}/app-records.lock")
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(true)
    # No app's job runs (APP_JOBS) unless a test says so
    allow(helper).to receive(:app_job_running?).and_return(false)
    allow(helper).to receive(:app_jobs_running).and_return([])
    # Vaultwarden, the catalog's, is reached only through Tailscale and given its admin token hashed
    # (format 5, P4.7): Tailscale is ready and argon2 hashes unless a test says otherwise, so no spec
    # reads the machine's own Tailscale (a laptop on a tailnet passed what CI's runner refused)
    allow(helper).to receive(:tailscale_https_name).and_return('amahi-kai.tail1234.ts.net')
    allow(helper).to receive(:argon2_hash) { |secret| "$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$#{secret.reverse}" }
    # Containers get Docker's own DNS unless a test says the NAS's answers on the bridge: CI's
    # runner has a Docker bridge, a laptop may not
    allow(helper).to receive(:app_dns_options).and_return([])
    # A share's folder is on ext4 unless a test puts it on ZFS, whatever the runner's /tmp is
    allow(helper).to receive(:capture).and_call_original
    allow(helper).to receive(:capture).with(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '-T', anything]).and_return("ext4\n")
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
      # How to sign in the first time: one line, or none (a manifest from before it)
      expect(helper.catalog_entry_problem('gitea', gitea.sub(/^sign_in: .*\n/, ''))).to be_nil
      ['sign_in: ""', 'sign_in: "a\\nb"', 'sign_in: [1]', "sign_in: \"#{'x' * 301}\""].each do |line|
        expect(helper.catalog_entry_problem('gitea', gitea.sub(/^sign_in: .*$/, line))).to eq('sign_in must be one line of text'), line
      end
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

  # Whether an app works with files in shares, so Install asks which to give it: a listing field,
  # which an Amahi-kai that doesn't know it ignores (every app asked, as before)
  describe "a manifest's shares" do
    def problem(extra)
      helper.catalog_entry_problem('demo', File.read("#{catalog}/gitea.yml") + extra)
    end

    it 'is true or false when it is there' do
      expect(problem("shares: true\n")).to be_nil
      expect(problem("shares: false\n")).to be_nil
      expect(problem("shares: yes please\n")).to eq('shares must be true or false')
    end
  end

  describe 'the catalog' do
    let(:ids) { Dir[File.join(catalog, '*.yml')].map { |path| File.basename(path, '.yml') } }

    it "has the apps chosen for the catalog, each a manifest the helper accepts" do
      expect(ids).to contain_exactly('jellyfin', 'vaultwarden', 'uptimekuma', 'gitea', 'transmission', 'bittube', 'bitshare', 'pigallery2', 'bitstream')
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
      allow(helper).to receive(:docker_output).with('inspect', '--format', '{{.Id}}', 'amahi-gitea').and_return("abc\n")
      expect(steps('apps.start', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker start amahi-gitea]])
      expect(steps('apps.stop', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker stop --time 30 amahi-gitea]])
      expect(steps('apps.restart', { 'app' => 'gitea' })).to eq([%w[/usr/bin/docker restart --time 30 amahi-gitea]])
    end

    # The catalog moved on or dropped the app: it was stuck until System Update.
    it 'starts, stops and uninstalls an app by its container, whatever the catalog says, and not while a job changes it' do
      allow(helper).to receive(:docker_output).with('inspect', '--format', '{{.Id}}', 'amahi-gone').and_return("abc\n")
      allow(helper).to receive(:docker_output).with('info', '--format', '{{.ServerVersion}}').and_return("27.3.1\n")
      expect(steps('apps.stop', { 'app' => 'gone' })).to eq([%w[/usr/bin/docker stop --time 30 amahi-gone]])
      expect(steps('apps.uninstall', { 'app' => 'gone' })).to eq([[:uninstall_app, 'gone', false], [:announce_apps]])
      allow(helper).to receive(:docker_output).with('inspect', '--format', '{{.Id}}', 'amahi-gone').and_return(nil)
      expect(refusal('apps.start', { 'app' => 'gone' })).to eq('gone has no container: install it again')
      allow(helper).to receive(:app_job_running?).with('gitea').and_return(true)
      expect(refusal('apps.restart', { 'app' => 'gitea' })).to eq("gitea is being changed (an install, update or uninstall runs): try again when it's done")
    end

    it 'installs from the manifest, and uninstalls keeping the data unless asked, only while Docker answers' do
      # A reinstall (new shares) keeps the version the app runs: the last argument.
      expect(steps('apps.install', { 'app' => 'vaultwarden' }))
        .to eq([[:install_app, 'vaultwarden', helper.app_manifest('vaultwarden'), [], true, nil], [:announce_apps]])
      allow(helper).to receive(:docker_output).with('info', '--format', '{{.ServerVersion}}').and_return("27.3.1\n")
      expect(steps('apps.uninstall', { 'app' => 'gitea' })).to eq([[:uninstall_app, 'gitea', false], [:announce_apps]])
      expect(steps('apps.uninstall', { 'app' => 'gitea', 'delete_data' => true })).to eq([[:uninstall_app, 'gitea', true], [:announce_apps]])
      expect(refusal('apps.uninstall', { 'app' => 'gitea', 'delete_data' => 'yes' })).to include('delete_data')
      # Uninstalled while Docker was stopped, the container came back when it started, unlisted
      allow(helper).to receive(:docker_output).with('info', '--format', '{{.ServerVersion}}').and_return(nil)
      expect(refusal('apps.uninstall', { 'app' => 'gitea' })).to eq("Docker isn't running: start it (Apps), then try again")
    end

    # A reinstall made the container from the catalog's newer manifest with the old image.
    it 'installs again from the definition the container was made from, when there is one' do
      kept = helper.app_manifest('vaultwarden')[:source].merge('image' => "vaultwarden/server:1.30.0@sha256:#{'c' * 64}", 'memory' => '256m')
      FileUtils.mkdir_p("#{dir}/app-definitions")
      File.write("#{dir}/app-definitions/vaultwarden.json", kept.to_json)
      manifest = helper.validate('apps.install', { 'app' => 'vaultwarden' })[:manifest]
      expect(manifest).to include(image: kept['image'], memory: '256m')
      File.write("#{dir}/app-definitions/vaultwarden.json", kept.merge('run_as' => 'nobody').to_json) # one that no longer passes
      expect(helper.validate('apps.install', { 'app' => 'vaultwarden' })[:manifest]).to eq(helper.app_manifest('vaultwarden'))
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

    # Docker's mount options split on , : and =, so a folder path with one could add options of its
    # own; two folders at one path failed only after the old container was gone.
    it 'wants folder paths of plain names, not where the shares go, and no two at one path' do
      ['/data,readonly=false', '/data:/etc', '/da ta', '/data=x'].each do |path|
        expect(failure('folders' => [{ 'name' => 'data', 'path' => path }])).to include('must be plain names'), path
      end
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/shares' }])).to include('is where the shares go')
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/shares/Movies' }])).to include('is where the shares go')
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/data' }, { 'name' => 'more', 'path' => '/data' }]))
        .to include('two folders have the same path')
      expect(failure('folders' => [{ 'name' => 'data', 'path' => '/var/lib/app-1.2_x' }])).to be_nil
    end

    it "refuses environment names that would have the image download more code (linuxserver.io's mods)" do
      expect(failure('environment' => { 'DOCKER_MODS' => 'linuxserver/mods:universal-package-install' }))
        .to include('DOCKER_MODS would have the image download more code')
      expect(failure('secrets' => [{ 'env' => 'DOCKER_MODS' }])).to include('DOCKER_MODS would have the image download more code')
    end

    it "wants an app that writes shares to run as the app's user: by --user, or by PUID and PGID set to its own placeholders" do
      expect(failure('writes_shares' => true)).to be_nil
      expect(failure('writes_shares' => true, 'run_as' => 'image',
                     'environment' => { 'PUID' => '{{uid}}', 'PGID' => '{{gid}}', 'TZ' => '{{timezone}}' })).to be_nil
      [{}, { 'PUID' => '0', 'PGID' => '0' }, { 'PUID' => '1000', 'PGID' => '1000' }, { 'PUID' => '{{uid}}' },
       { 'PUID' => '{{gid}}', 'PGID' => '{{uid}}' }, { 'PUID' => '{{uid}}', 'PGID' => '100' }].each do |env|
        expect(failure('writes_shares' => true, 'run_as' => 'image', 'environment' => env)).to include("runs as the app's user"), env.inspect
      end
      expect(failure('writes_shares' => false, 'run_as' => 'image', 'environment' => { 'PUID' => '0' })).to be_nil
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

    # Format 4: some apps name their settings with small letters and dashes (PiGallery2's
    # Users-enforcedUsers), and want a generated password inside one of them
    it 'takes names as the app spells them and secrets inside values, only with requires: 4' do
      spelled = { 'default-Media-folder' => '/shares',
                  'Users-enforcedUsers' => '[{"name":"admin","role":"Admin","password":"{{secret:TOKEN}}"}]' }
      expect(failure('requires' => 4, 'environment' => spelled)).to be_nil
      expect(failure('environment' => { 'default-Media-folder' => '/shares' })).to include('needs requires: 4')
      expect(failure('environment' => { 'X' => 'a {{secret:TOKEN}}' })).to include('needs requires: 4')
      expect(failure('requires' => 4, 'environment' => { 'X' => '{{secret:OTHER}}' })).to include("isn't one of its secrets")
      ['-x', '1x', 'a b', 'a=b', 'a.b', ''].each do |name|
        expect(failure('requires' => 4, 'environment' => { name => '1' })).to include("isn't valid"), name.inspect
      end
      expect(failure('requires' => 4, 'environment' => { 'docker_mods' => 'x' })).to include('download more code')
    end

    # Format 5 (P4.7): an app reached only through Tailscale, over HTTPS, and secrets the
    # container gets hashed. Older Amahi-kais must list them as needing a newer one: one that put a
    # Tailscale-only app on the LAN, or gave it its admin token as it is, would get it wrong.
    it 'takes access: tailscale and hashed secrets only with requires: 5, for a page over plain HTTP on TCP' do
      tailnet = { 'requires' => 5, 'access' => 'tailscale', 'web_port' => 8500, 'environment' => { 'DOMAIN' => '{{tailscale_url}}' } }
      expect(failure(tailnet)).to be_nil
      expect(helper.app_manifest('test')).to include(access: 'tailscale', hashed_secrets: [])
      expect(failure(tailnet.merge('requires' => 4))).to include('access: tailscale needs requires: 5')
      expect(failure(tailnet.merge('access' => 'internet'))).to include('access must be lan or tailscale')
      expect(failure(tailnet.except('web_port'))).to include('access: tailscale needs a web_port')
      expect(failure(tailnet.merge('web_tls' => true))).to include('so web_tls must be false')
      expect(failure(tailnet.merge('ports' => [{ 'host' => 8500, 'container' => 80, 'protocol' => 'udp' }]))).to include('its web port to be TCP')
      expect(failure('requires' => 5, 'environment' => { 'DOMAIN' => '{{tailscale_url}}' }))
        .to include('DOMAIN has {{tailscale_url}}, which is for an app with access: tailscale')

      expect(failure('requires' => 5, 'secrets' => [{ 'env' => 'TOKEN', 'label' => 'Token', 'hash' => 'argon2' }])).to be_nil
      expect(helper.app_manifest('test')).to include(access: 'lan', secrets: ['TOKEN'], hashed_secrets: ['TOKEN'])
      expect(failure('secrets' => [{ 'env' => 'TOKEN', 'hash' => 'argon2' }])).to include("secret TOKEN's hash needs requires: 5")
      expect(failure('requires' => 5, 'secrets' => [{ 'env' => 'TOKEN', 'hash' => 'md5' }])).to include("secret TOKEN's hash must be argon2")
    end
  end

  # What an app reached only through Tailscale needs (P4.7), read from `tailscale status`, as
  # root reads it: what's missing is said, so the Apps page can say what to switch on.
  describe "Tailscale's readiness to serve an app" do
    before { allow(helper).to receive(:tailscale_https_name).and_call_original }

    let(:ready) do
      { 'BackendState' => 'Running', 'Self' => { 'DNSName' => 'amahi-kai.tail1234.ts.net.' },
        'CurrentTailnet' => { 'MagicDNSEnabled' => true }, 'CertDomains' => ['amahi-kai.tail1234.ts.net'] }
    end

    def status_says(data, success: true)
      allow(File).to receive(:executable?).with('/usr/bin/tailscale').and_return(true)
      allow(Open3).to receive(:capture3).with(anything, ['/usr/bin/tailscale', '/usr/bin/tailscale'], 'status', '--json', any_args)
                                        .and_return([data.to_json, '', instance_double(Process::Status, success?: success)])
    end

    def missing
      helper.tailscale_https_name
      nil
    rescue AmahiHelper::Refused => e
      e.message
    end

    it 'names the NAS on its tailnet when Tailscale is connected, with MagicDNS and HTTPS certificates on' do
      status_says(ready)
      expect(helper.tailscale_https_name).to eq('amahi-kai.tail1234.ts.net')
    end

    it 'says what is missing otherwise' do
      allow(File).to receive(:executable?).with('/usr/bin/tailscale').and_return(false)
      expect(missing).to include('install Tailscale on the NAS first')
      status_says(ready.merge('BackendState' => 'NeedsLogin'))
      expect(missing).to include("which isn't connected")
      status_says(ready, success: false)
      expect(missing).to include("which isn't connected")
      status_says(ready.merge('CurrentTailnet' => { 'MagicDNSEnabled' => false }))
      expect(missing).to include('turn on MagicDNS')
      status_says(ready.merge('Self' => { 'DNSName' => 'bad name;x.' }))
      expect(missing).to include('turn on MagicDNS')
      status_says(ready.merge('CertDomains' => nil))
      expect(missing).to include('turn on HTTPS Certificates')
      status_says(ready.merge('CertDomains' => ['other.tail1234.ts.net']))
      expect(missing).to include('turn on HTTPS Certificates')
    end
  end

  describe 'hashing a secret for the container (hash: argon2)' do
    before { allow(helper).to receive(:argon2_hash).and_call_original }

    let(:hash) { '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA' }
    let(:ran) { [] }

    before do
      allow(helper).to receive(:say)
      allow(helper).to receive(:run_command) { |argv| ran << argv.reject { |a| a.is_a?(Hash) } }
    end

    def argon2_says(out, success: true)
      allow(Open3).to receive(:capture3).with(anything, ['/usr/bin/argon2', '/usr/bin/argon2'], any_args)
                                        .and_return([out, 'argon2: error', instance_double(Process::Status, success?: success)])
    end

    it 'gives argon2 the secret on its stdin, a new salt and OWASP settings, installing it the first time' do
      allow(File).to receive(:executable?).with('/usr/bin/argon2').and_return(false)
      argon2_says("#{hash}\n")
      expect(helper.argon2_hash('s3cret')).to eq(hash)
      expect(Open3).to have_received(:capture3).with(anything, ['/usr/bin/argon2', '/usr/bin/argon2'], match(/\A[A-Za-z0-9]{22}\z/),
                                                     '-id', '-k', '19456', '-t', '2', '-p', '1', '-l', '32', '-e',
                                                     stdin_data: 's3cret', unsetenv_others: true, chdir: '/')
      expect(ran.map(&:last)).to eq(%w[update argon2])
    end

    it "doesn't install it again, and fails when it doesn't give a hash" do
      allow(File).to receive(:executable?).with('/usr/bin/argon2').and_return(true)
      argon2_says('', success: false)
      expect { helper.argon2_hash('s3cret') }.to raise_error(AmahiHelper::Failed, "argon2 didn't hash the app's password: argon2: error")
      argon2_says("not a hash\n")
      expect { helper.argon2_hash('s3cret') }.to raise_error(AmahiHelper::Failed, /didn't hash/)
      expect(ran).to be_empty
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
      allow(File).to receive(:executable?).with('/usr/bin/tailscale').and_return(true) # for tailscale serve's removal
      allow(helper).to receive(:run_command) do |argv|
        ran << argv
        accounts[argv.last] = account(argv.last, 996) if argv.first == '/usr/sbin/useradd'
        if argv.first == '/usr/bin/docker' && argv[1] == 'create'
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

      serve = ['/usr/bin/timeout', '30', '/usr/bin/tailscale', 'serve', '--bg', '--https=8880', 'http://127.0.0.1:8880']
      expect(ran.drop(1).map(&:first).uniq).to eq(['/usr/bin/docker', '/usr/bin/timeout'])
      # Made under a name of its own, then swapped in for the old one (none here), and served on the
      # tailnet before it starts
      expect(ran.drop(1).map { |argv| argv == serve ? 'serve' : argv[1..2].join(' ') }).to eq(
        ["pull #{manifest[:image]}", 'rm --force', 'create --name', 'rm --force', 'rename amahi-vaultwarden-next', 'serve', 'start amahi-vaultwarden']
      )
      expect(ran[1]).to eq(['/usr/bin/docker', 'pull', manifest[:image], { stream: true }])
      create = ran.find { |argv| argv[1] == 'create' }
      expect(create).to eq(['/usr/bin/docker', 'create', '--name', 'amahi-vaultwarden-next', '--restart', 'unless-stopped',
                            '--security-opt', 'no-new-privileges', '--cap-drop', 'NET_RAW', '--cap-drop', 'MKNOD',
                            '--pids-limit', '2048', '--log-opt', 'max-size=10m', '--log-opt', 'max-file=3',
                            '--memory', '512m', '--label', 'amahi.app=vaultwarden', '--env-file', env_files.sole[0],
                            '--user', '996:996', '--publish', '127.0.0.1:8880:8080/tcp',
                            '--mount', "type=bind,source=#{apps_root}/vaultwarden/data,target=/data", manifest[:image]])
      expect(ran[-3]).to eq(%w[/usr/bin/docker rename amahi-vaultwarden-next amahi-vaultwarden])
      expect(JSON.parse(File.read("#{dir}/app-definitions/vaultwarden.json"))).to eq(manifest[:source].merge('image' => manifest[:image]))
      expect(create.join(' ')).not_to include(token)

      path, content, mode = env_files.sole
      expect(content.lines(chomp: true)).to contain_exactly('ROCKET_PORT=8080', 'TZ=America/Chicago',
                                                            'DOMAIN=https://amahi-kai.tail1234.ts.net:8880',
                                                            "ADMIN_TOKEN=$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$#{token.reverse}")
      expect(mode).to eq(0o600)
      expect(File.exist?(path)).to be false
      expect(helper).to have_received(:do_app_firewall)
    end

    it "gives the container the NAS's DNS while Unbound answers on Docker's bridge" do
      allow(helper).to receive(:app_dns_options).and_return(['--dns', '172.17.0.1', '--dns-search', 'home.arpa'])
      helper.do_install_app('vaultwarden', helper.app_manifest('vaultwarden'))
      create = ran.find { |argv| argv[1] == 'create' }
      expect(create.each_cons(6).to_a).to include(['--label', 'amahi.app=vaultwarden', '--dns', '172.17.0.1', '--dns-search', 'home.arpa'])
    end

    it 'fills in a secret inside a value, under the name the app spells (format 4), and keeps it out of the definition' do
      stub_const('AmahiHelper::APP_MANIFESTS', "#{dir}/manifests")
      FileUtils.mkdir_p("#{dir}/manifests")
      File.write("#{dir}/manifests/gallery.yml", {
        'name' => 'Gallery', 'description' => 'Photos.', 'category' => 'media', 'requires' => 4,
        'image' => "example/gallery:1.0@sha256:#{'b' * 64}", 'run_as' => 'app',
        'ports' => [{ 'host' => 8510, 'container' => 80 }], 'folders' => [{ 'name' => 'config', 'path' => '/app/data/config' }],
        'secrets' => [{ 'env' => 'ADMIN_PASSWORD', 'label' => 'Admin password' }],
        'environment' => { 'TZ' => '{{timezone}}', 'default-Media-folder' => '/shares',
                           'Users-enforcedUsers' => '[{"name":"admin","role":"Admin","password":"{{secret:ADMIN_PASSWORD}}"}]' }
      }.to_yaml)
      helper.do_install_app('gallery', helper.app_manifest('gallery'))

      password = JSON.parse(File.read("#{secrets_dir}/gallery.json"))['ADMIN_PASSWORD']
      expect(password).to match(/\A[A-Za-z0-9]{32}\z/)
      expect(env_files.sole[1].lines(chomp: true)).to contain_exactly(
        'TZ=America/Chicago', 'default-Media-folder=/shares',
        %(Users-enforcedUsers=[{"name":"admin","role":"Admin","password":"#{password}"}]), "ADMIN_PASSWORD=#{password}"
      )
      definition = File.read("#{dir}/app-definitions/gallery.json")
      expect(definition).to include('{{secret:ADMIN_PASSWORD}}')
      expect(definition).not_to include(password)
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

    # P4.6: an app's dataset folders on a ZFS pool, <pool>/apps/<id>, chosen at install.
    describe 'storage on a ZFS pool' do
      let(:manifests) { "#{dir}/manifests" }
      let(:root) { "#{dir}/pools/tank/apps/store" }
      let(:datasets) { [] }

      def store(required: true)
        FileUtils.mkdir_p(manifests)
        FileUtils.cp(Rails.root.join('config/apps/vaultwarden.yml'), manifests)
        File.write("#{manifests}/store.yml", {
          'image' => "example/store:1.0@sha256:#{'a' * 64}", 'run_as' => 'app', 'requires' => 3,
          'ports' => [{ 'host' => 8600, 'container' => 8443 }],
          'folders' => [{ 'name' => 'config', 'path' => '/config' },
                        { 'name' => 'data', 'path' => '/data', 'kind' => 'dataset', 'required' => required },
                        { 'name' => 'chunks', 'path' => '/chunks', 'kind' => 'dataset', 'backup' => false, 'required' => required }]
        }.to_yaml)
        helper.app_manifest('store')
      end

      before do
        stub_const('AmahiHelper::APP_MANIFESTS', manifests)
        stub_const('AmahiHelper::APP_STORAGE', "#{dir}/app-storage.json")
        stub_const('AmahiHelper::POOL_ROOT', "#{dir}/pools")
        stub_const('AmahiHelper::APP_BACKUPS', "#{dir}/app-backups")
        FileUtils.mkdir_p("#{dir}/pools/tank/apps")
        allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(true)
        allow(helper).to receive(:pool_names).and_return(['tank'])
        allow(helper).to receive(:pool_mountpoint) { |name| "#{dir}/pools/#{name}" } # Amahi-kai's own
        allow(helper).to receive(:zfs_dataset?) { |name| datasets.include?(name) }
        allow(helper).to receive(:capture).and_call_original
        allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs get -H -o value mounted tank/apps/store]).and_return("yes\n")
        allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs get -H -o value mountpoint tank/apps/store]).and_return("#{root}\n")
        allow(helper).to receive(:dataset_mounted?).with('tank/apps/store', root).and_return(true)
      end

      it 'reads which folders go on a pool, and whether the app needs one' do
        expect(store[:folders].map { |f| [f[:name], f[:kind], f[:required]] })
          .to eq([['config', :state, false], ['data', :dataset, true], ['chunks', :dataset, true]])
        expect(store[:storage]).to eq(:required)
        FileUtils.mkdir_p(manifests)
        File.write("#{manifests}/bad.yml", { 'image' => "example/bad:1@sha256:#{'a' * 64}", 'run_as' => 'app',
                                              'folders' => [{ 'name' => 'data', 'path' => '/data', 'kind' => 'pool' }] }.to_yaml)
        expect { helper.app_manifest('bad') }.to raise_error(AmahiHelper::Failed, /kind must be state or dataset/)
        File.write("#{manifests}/bad.yml", { 'image' => "example/bad:1@sha256:#{'a' * 64}", 'run_as' => 'app',
                                              'folders' => [{ 'name' => 'data', 'path' => '/data', 'required' => false }] }.to_yaml)
        expect { helper.app_manifest('bad') }.to raise_error(AmahiHelper::Failed, /required is for a dataset folder/)
        expect(helper.app_manifest('vaultwarden')[:storage]).to be_nil
      end

      it 'takes the pool the first time, and keeps the data on it after' do
        store
        expect(helper.validate('apps.install', { 'app' => 'store', 'pool' => 'tank' })).to include(pool: 'tank')
        expect(refusal('apps.install', { 'app' => 'store' })).to eq('store keeps its data on a ZFS pool: choose one (make one on Disks → ZFS Pools first)')
        expect(refusal('apps.install', { 'app' => 'store', 'pool' => 'nope' })).to eq(%(there's no pool named "nope"))
        allow(helper).to receive(:pool_names).and_return(%w[tank rpool])
        allow(helper).to receive(:pool_mountpoint).with('rpool').and_return('/') # a system's own pool
        expect(refusal('apps.install', { 'app' => 'store', 'pool' => 'rpool' }))
          .to eq("rpool isn't one of Amahi-kai's pools (it mounts at /); manage it from the command line")
        allow(helper).to receive(:pool_names).and_return(['tank'])
        expect(steps('apps.install', { 'app' => 'store', 'pool' => 'tank' }).first.last).to eq('tank')
        expect(helper.validate('apps.install', { 'app' => 'vaultwarden', 'pool' => 'tank' })).to include(pool: nil)

        File.write("#{dir}/app-storage.json", { 'store' => 'tank' }.to_json)
        expect(helper.validate('apps.install', { 'app' => 'store' })).to include(pool: 'tank')
        expect(refusal('apps.install', { 'app' => 'store', 'pool' => 'other' }))
          .to eq("store's data is on the pool tank: uninstall it with its data to move it to other")
      end

      it 'makes the dataset, gives the container its folders from it, and records the pool' do
        helper.do_install_app('store', store, [], true, 'tank')
        expect(ran).to include(%w[/usr/sbin/zfs create -p tank/apps/store])
        create = ran.find { |argv| argv[1] == 'create' && argv.first == '/usr/bin/docker' }
        expect(create.each_cons(2).select { |flag, _| %w[--volume --mount].include?(flag) }).to eq(
          [['--mount', "type=bind,source=#{apps_root}/store/config,target=/config"],
           ['--mount', "type=bind,source=#{root}/data,target=/data"],
           ['--mount', "type=bind,source=#{root}/chunks,target=/chunks"]]
        )
        expect(Dir.exist?("#{apps_root}/store/data")).to be false # not on the system disk
        expect(File.stat("#{root}/data").mode & 0o777).to eq(0o750)
        expect(File).to have_received(:lchown).with(996, 996, "#{root}/chunks")
        expect(JSON.parse(File.read("#{dir}/app-storage.json"))).to eq('store' => 'tank')

        # Made again later (an update, the pool changing): the same pool, the dataset reused.
        datasets << 'tank/apps/store'
        ran.clear
        helper.do_install_app('store', store)
        expect(ran).not_to include(%w[/usr/sbin/zfs create -p tank/apps/store])
        expect(ran.find { |argv| argv.first == '/usr/bin/docker' && argv[1] == 'create' }).to include("type=bind,source=#{root}/data,target=/data")

        allow(helper).to receive(:pool_names).and_return([])
        expect { helper.do_install_app('store', store) }
          .to raise_error(AmahiHelper::Failed, "store's data is on the pool tank, which isn't online: bring it online on Disks → ZFS Pools first")
      end

      it "won't make the container of an app whose folders moved to a dataset after it was installed" do
        expect { helper.do_install_app('store', store) } # an update, or the pool changing: no pool recorded
          .to raise_error(AmahiHelper::Failed, /keeps its data on a ZFS pool now, and has none: uninstall it and install it again on a pool/)
        expect(ran.any? { |argv| argv.first == '/usr/bin/docker' && argv[1] == 'create' }).to be false
      end

      it "leaves an optional dataset's folders out when no pool is chosen" do
        manifest = store(required: false)
        expect(manifest[:storage]).to eq(:optional)
        expect(helper.validate('apps.install', { 'app' => 'store' })).to include(pool: nil)
        helper.do_install_app('store', manifest)
        create = ran.find { |argv| argv.first == '/usr/bin/docker' && argv[1] == 'create' }
        expect(create.join(' ')).not_to include("#{dir}/pools") # the system disk's own folder only
        expect(ran).not_to include(%w[/usr/sbin/zfs create -p tank/apps/store])
        expect(File.exist?("#{dir}/app-storage.json")).to be false
      end

      it 'snapshots the dataset before an update instead of copying it, rolls back to it, and drops it after' do
        datasets << 'tank/apps/store'
        File.write("#{dir}/app-storage.json", { 'store' => 'tank' }.to_json)
        manifest = store
        FileUtils.mkdir_p("#{apps_root}/store/config")
        helper.app_backup('store', manifest, "example/store:0.9@sha256:#{'b' * 64}")
        snapshot = ran.find { |argv| argv[1] == 'snapshot' }&.last
        expect(snapshot).to match(%r{\Atank/apps/store@amahi-update-\d{8}-\d{6}\z})
        info = JSON.parse(File.read("#{dir}/app-backups/store.json"))
        expect(info).to include('snapshot' => snapshot, 'folders' => ['config']) # the dataset isn't copied

        datasets << snapshot
        ran.clear
        helper.app_restore('store', manifest, "example/store:0.9@sha256:#{'b' * 64}", [])
        expect(ran).to include(['/usr/sbin/zfs', 'rollback', '-r', snapshot])
        expect(ran.index(['/usr/sbin/zfs', 'rollback', '-r', snapshot])).to be < ran.index { |argv| argv.first == '/usr/bin/docker' && argv[1] == 'create' }

        ran.clear
        helper.app_forget_backup('store')
        expect(ran).to eq([['/usr/sbin/zfs', 'destroy', snapshot, { allow_failure: true }]])

        File.write("#{dir}/app-backups/store.json", { 'snapshot' => 'tank/apps/other@amahi-update-20261011-120000' }.to_json)
        expect { helper.app_backup_snapshot('store', JSON.parse(File.read("#{dir}/app-backups/store.json"))) }
          .to raise_error(AmahiHelper::Failed, /names a snapshot/)
      end

      it 'deletes the dataset with the data, only while its pool is online' do
        datasets << 'tank/apps/store'
        File.write("#{dir}/app-storage.json", { 'store' => 'tank', 'other' => 'tank' }.to_json)
        helper.do_uninstall_app('store', false)
        expect(ran).not_to include(%w[/usr/sbin/zfs destroy -r tank/apps/store])
        expect(JSON.parse(File.read("#{dir}/app-storage.json"))).to include('store' => 'tank') # kept

        helper.do_uninstall_app('store', true)
        expect(ran).to include(%w[/usr/sbin/zfs destroy -r tank/apps/store])
        expect(JSON.parse(File.read("#{dir}/app-storage.json"))).to eq('other' => 'tank')

        File.write("#{dir}/app-storage.json", { 'store' => 'tank' }.to_json)
        allow(helper).to receive(:pool_names).and_return([])
        ran.clear
        expect { helper.do_uninstall_app('store', true) }
          .to raise_error(AmahiHelper::Failed, "store's data is on the pool tank, which isn't online: bring it online to delete it")
        expect(ran).to be_empty # nothing removed
      end
    end

    describe 'uninstalling' do
      before do
        helper.do_install_app('gitea', helper.app_manifest('gitea'))
        ran.clear
      end

      let(:image) { helper.app_manifest('gitea')[:image] }

      it 'removes the container and the image its definition names, and keeps the data and the definition' do
        expect(helper.do_uninstall_app('gitea', false)).to eq('app' => 'gitea', 'data_kept' => true)
        expect(ran).to eq([['/usr/bin/docker', 'rm', '--force', 'amahi-gitea', { allow_failure: true }],
                           ['/usr/bin/docker', 'image', 'rm', image, { allow_failure: true }]])
        expect(File.directory?("#{apps_root}/gitea/data")).to be true
        expect(File.exist?("#{dir}/app-definitions/gitea.json")).to be true # installed again, it runs this version
      end

      it 'deletes the folders, secrets file, definition and user when asked' do
        File.write("#{secrets_dir}/gitea.json", '{}')
        expect(helper.do_uninstall_app('gitea', true)).to eq('app' => 'gitea', 'data_kept' => false)
        expect(File.exist?("#{apps_root}/gitea")).to be false
        expect(File.exist?("#{secrets_dir}/gitea.json")).to be false
        expect(File.exist?("#{dir}/app-definitions/gitea.json")).to be false
        expect(ran.last).to eq(['/usr/sbin/userdel', 'app-gitea', { allow_failure: true }])
      end

      it "keeps the app's ports for its next install, unless its data goes too" do
        helper.do_uninstall_app('gitea', false)
        expect(JSON.parse(File.read("#{dir}/app-ports.json")).keys).to eq(['gitea'])
        helper.do_uninstall_app('gitea', true)
        expect(JSON.parse(File.read("#{dir}/app-ports.json"))).to eq({})
      end

      it "stops when Docker didn't remove the container, before anything else goes" do
        allow(helper).to receive(:docker_output).with('inspect', '--format', '{{.Id}}', 'amahi-gitea').and_return("abc\n")
        expect { helper.do_uninstall_app('gitea', true) }.to raise_error(AmahiHelper::Failed, "Docker didn't remove amahi-gitea; nothing else of gitea was touched")
        expect(File.directory?("#{apps_root}/gitea/data")).to be true
      end
    end

    # P4.7: published on the NAS itself only, served on the tailnet over HTTPS at the NAS's name
    # and its own port, told that address, and given its admin token hashed.
    describe 'an app reached only through Tailscale' do
      let(:serve) { ['/usr/bin/timeout', '30', '/usr/bin/tailscale', 'serve', '--bg', '--https=8880', 'http://127.0.0.1:8880'] }

      before do
        stub_const('AmahiHelper::APP_MANIFESTS', "#{dir}/manifests")
        FileUtils.mkdir_p("#{dir}/manifests")
        FileUtils.cp(Dir["#{catalog}/*.yml"], "#{dir}/manifests")
        File.write("#{dir}/manifests/vault.yml", {
          'name' => 'Vault', 'description' => 'Passwords.', 'category' => 'security', 'requires' => 5, 'access' => 'tailscale',
          'image' => "example/vault:1.0@sha256:#{'c' * 64}", 'run_as' => 'app', 'web_port' => 8880,
          'ports' => [{ 'host' => 8880, 'container' => 8080 }], 'folders' => [{ 'name' => 'data', 'path' => '/data' }],
          'environment' => { 'DOMAIN' => '{{tailscale_url}}' },
          'secrets' => [{ 'env' => 'ADMIN_TOKEN', 'label' => 'Admin token', 'hash' => 'argon2' }]
        }.to_yaml)
      end

      it 'is published on the NAS itself only, served on the tailnet over HTTPS, and told its address' do
        helper.do_install_app('vault', helper.app_manifest('vault'))
        create = ran.find { |argv| argv[1] == 'create' }
        expect(create.each_cons(2).select { |flag, _| flag == '--publish' }.map(&:last)).to eq(['127.0.0.1:8880:8080/tcp'])
        expect(env_files.sole[1].lines(chomp: true)).to include('DOMAIN=https://amahi-kai.tail1234.ts.net:8880')
        # Served once the new container has taken the app's name, before it starts
        expect(ran.index(serve)).to be > ran.index { |argv| argv[1] == 'rename' }
        expect(ran.index(serve)).to be < ran.index { |argv| argv[1] == 'start' }
      end

      it 'gets its admin token hashed, while the admin pages keep the token itself to sign in with' do
        helper.do_install_app('vault', helper.app_manifest('vault'))
        token = JSON.parse(File.read("#{secrets_dir}/vault.json"))['ADMIN_TOKEN']
        expect(token).to match(/\A[A-Za-z0-9]{32}\z/)
        expect(env_files.sole[1].lines(chomp: true)).to include("ADMIN_TOKEN=$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$#{token.reverse}")
        expect(env_files.sole[1]).not_to include("=#{token}")
      end

      it "is refused before anything changes while Tailscale can't serve it" do
        allow(helper).to receive(:tailscale_https_name)
          .and_raise(AmahiHelper::Refused, "this app is reached over HTTPS through Tailscale: turn on HTTPS Certificates in Tailscale's admin console (DNS)")
        expect(refusal('apps.install', 'app' => 'vault')).to include('turn on HTTPS Certificates')
        expect(refusal('apps.update', 'app' => 'vault')).to include('turn on HTTPS Certificates')
        expect(ran).to be_empty
      end

      # tailscaled holds 8880 on the Tailscale addresses while it serves the app, so a check on
      # 0.0.0.0 moved it to 8881 at each update or change of its shares
      it 'keeps its port while it is served, checking it on 127.0.0.1, where it is published' do
        allow(helper).to receive(:port_bindable?) { |_port, _protocol, address| address == '127.0.0.1' }
        helper.do_install_app('vault', helper.app_manifest('vault'))
        create = ran.find { |argv| argv[1] == 'create' }
        expect(create.each_cons(2).select { |flag, _| flag == '--publish' }.map(&:last)).to eq(['127.0.0.1:8880:8080/tcp'])
        expect(env_files.sole[1]).to include('DOMAIN=https://amahi-kai.tail1234.ts.net:8880')
        expect(helper).to have_received(:port_bindable?).with(8880, 'tcp', '127.0.0.1')
        expect(helper).not_to have_received(:port_bindable?).with(anything, anything, '0.0.0.0')
      end

      it 'comes off the tailnet when uninstalled, at the port it was given' do
        helper.do_install_app('vault', helper.app_manifest('vault'))
        ran.clear
        helper.do_uninstall_app('vault', false)
        expect(ran).to include(['/usr/bin/timeout', '30', '/usr/bin/tailscale', 'serve', '--https=8880', 'off', { allow_failure: true }])
      end

      it "isn't announced on the LAN, where nothing can open it" do
        stub_const('AmahiHelper::APP_PORTS', "#{dir}/app-ports.json")
        expect(helper.app_announcement('vault')).to be_nil
      end

      it 'leaves an app on the LAN as it was' do
        helper.do_install_app('gitea', helper.app_manifest('gitea'))
        create = ran.find { |argv| argv[1] == 'create' }
        expect(create.each_cons(2).select { |flag, _| flag == '--publish' }.map(&:last)).to all(start_with('0.0.0.0:'))
        expect(ran.flatten).not_to include('serve')
        expect(helper).not_to have_received(:tailscale_https_name)
      end
    end

    it "lets what an app writes into a share stay editable over SMB, installing acl if needed" do
      FileUtils.mkdir_p("#{dir}/downloads")
      share = { name: 'Downloads', path: "#{dir}/downloads", pooled: false, write: true }
      allow(helper).to receive(:app_share_mounts).and_return([])
      allow(File).to receive(:executable?).with('/usr/bin/setfacl').and_return(false)
      helper.do_install_app('transmission', helper.app_manifest('transmission'), [share])
      acl = ran.index { |argv| argv.first == '/usr/bin/find' }
      expect(ran[acl - 1]).to include('/usr/bin/apt-get', 'install', 'acl')
      expect(ran[acl]).to eq(['/usr/bin/find', "#{dir}/downloads", '-xdev', '-type', 'd', '-exec',
                              '/usr/bin/setfacl', '-P', '-d', '-m', 'u::rwx,g::rwx,o::rx', '{}', '+'])
      expect(ran.index { |argv| argv[1] == 'start' }).to be > acl
      expect(ran.flatten).not_to include('/usr/sbin/zfs')
    end

    describe 'a share on a ZFS pool' do
      let(:folder) { "#{dir}/downloads" }
      let(:share) { { name: 'Downloads', path: folder, pooled: false, write: true } }

      def on_zfs(acltype, mountpoint: '/srv/pools/tank')
        allow(helper).to receive(:capture).with(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '-T', folder]).and_return("zfs\n")
        allow(helper).to receive(:capture).with(['/usr/sbin/zfs', 'get', '-H', '-o', 'name,value', 'acltype', folder])
                                          .and_return("tank/shares\t#{acltype}\n")
        allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs get -H -o value mountpoint tank]).and_return("#{mountpoint}\n")
      end

      before do
        FileUtils.mkdir_p(folder)
        allow(helper).to receive(:app_share_mounts).and_return([])
        allow(File).to receive(:executable?).with('/usr/bin/setfacl').and_return(true)
      end

      # ZFS on Linux's default: setfacl failed with "Operation not supported" and the install stopped
      it 'gets POSIX ACLs on its dataset before setfacl when the pool has them off' do
        on_zfs('off')
        helper.do_install_app('transmission', helper.app_manifest('transmission'), [share])
        set = ran.index { |argv| argv.first == '/usr/sbin/zfs' }
        expect(ran[set]).to eq(['/usr/sbin/zfs', 'set', 'acltype=posixacl', 'xattr=sa', 'tank/shares'])
        expect(ran.index { |argv| argv.first == '/usr/bin/find' }).to be > set
      end

      it 'leaves a dataset that has them as it is' do
        on_zfs('posix')
        helper.do_install_app('transmission', helper.app_manifest('transmission'), [share])
        expect(ran.flatten).not_to include('/usr/sbin/zfs')
        expect(ran.map(&:first)).to include('/usr/bin/find')
      end

      it "never changes a pool that isn't Amahi-kai's" do
        on_zfs('off', mountpoint: '/tank')
        helper.do_install_app('transmission', helper.app_manifest('transmission'), [share])
        expect(ran.flatten).not_to include('/usr/sbin/zfs')
      end
    end

    # The old container went first: a create that failed left the app none, and Install again then
    # upgraded it with no copy.
    it 'makes the new container beside the old one, and gives the app its old one back, started, when that fails' do
      allow(helper).to receive(:docker_output).with('inspect', '--format', '{{json .State}}', 'amahi-gitea').and_return('{"Running":true}')
      allow(helper).to receive(:run_command) do |argv|
        ran << argv
        accounts[argv.last] = account(argv.last, 996) if argv.first == '/usr/sbin/useradd'
        raise AmahiHelper::Failed, 'docker exited 125: invalid mount config' if argv[1] == 'create'
        nil
      end
      expect { helper.do_install_app('gitea', helper.app_manifest('gitea')) }.to raise_error(AmahiHelper::Failed, /invalid mount config/)
      docker = ran.select { |argv| argv.first == '/usr/bin/docker' }.map { |argv| argv[1..2].reject { |arg| arg.is_a?(Hash) } }
      expect(docker.drop(1)).to eq([%w[rm --force], %w[stop --time], %w[create --name], %w[rm --force], %w[start amahi-gitea]])
      expect(ran.select { |argv| argv[1] == 'rm' }.map { |argv| argv[3] }).to eq(%w[amahi-gitea-next amahi-gitea-next]) # never the old one
      expect(File.exist?("#{dir}/app-definitions/gitea.json")).to be false
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
        helper.do_uninstall_app('vaultwarden', true)
        expect(ran).to include(['/usr/bin/docker', 'image', 'rm', manifest[:image], { allow_failure: true }])
        expect(File.exist?("#{backups}/vaultwarden.json")).to be false
      end

      # Rollback and Undo ran the old image with the new definition's settings.
      it 'keeps the definition the app ran in its copy, and goes back to it' do
        kept = JSON.parse(File.read("#{dir}/app-definitions/vaultwarden.json"))
        File.write("#{dir}/app-definitions/vaultwarden.json", kept.merge('memory' => '256m').to_json)
        allow(helper).to receive(:app_health_problem).and_return('it stopped (exit code 1)')
        helper.do_update_app('vaultwarden', manifest, [])
        creates = ran.select { |argv| argv[1] == 'create' }
        expect(creates.map { |argv| argv[argv.index('--memory') + 1] }).to eq(%w[512m 256m]) # the new version, then the old one as it was

        allow(helper).to receive(:app_health_problem).and_return(nil)
        helper.do_update_app('vaultwarden', manifest, [])
        expect(backup_info['definition']).to include('image' => old_image, 'memory' => '256m')
        expect(helper.validate('apps.undo_update', { 'app' => 'vaultwarden' })[:manifest]).to include(image: old_image, memory: '256m')
      end

      it "starts it again on the version it ran when its data can't be copied" do
        allow(helper).to receive(:run_command) do |argv|
          raise AmahiHelper::Failed, 'cp exited 1: No space left on device' if argv.first == '/usr/bin/cp'
          fake_docker.call(argv)
        end
        expect { helper.do_update_app('vaultwarden', manifest, []) }.to raise_error(
          AmahiHelper::Failed, "vaultwarden's data couldn't be copied before the update (cp exited 1: No space left on device); it runs 1.37.2 as before"
        )
        expect(ran.last).to eq(['/usr/bin/docker', 'start', 'amahi-vaultwarden', { allow_failure: true }])
        expect(ran.map { |argv| argv[1] }).not_to include('create')
      end

      it "doesn't take an older version from the catalog for an update" do
        older = manifest.merge(image: "vaultwarden/server:1.36.0@sha256:#{'d' * 64}")
        expect { helper.do_update_app('vaultwarden', older, []) }.to raise_error(
          AmahiHelper::Failed, "the catalog's vaultwarden (1.36.0) is older than the one it runs (1.37.2), so there's nothing to update to"
        )
        expect(ran).to be_empty
        expect(helper.version_below?('4.0.16-ls253', '4.0.17-ls254')).to be true
        expect(helper.version_below?('latest', '1.0')).to be false
      end

      # Undo changed the data before it found the old image gone (an update removes it).
      it 'downloads the old version again before Undo changes anything, and stops if it cannot' do
        helper.do_update_app('vaultwarden', manifest, [])
        ran.clear
        allow(helper).to receive(:run_command) do |argv|
          raise AmahiHelper::Failed, 'docker exited 1: no such image' if argv[1] == 'pull'
          fake_docker.call(argv)
        end
        expect { helper.do_undo_app_update('vaultwarden', manifest, []) }.to raise_error(AmahiHelper::Failed, /no such image/)
        expect(File.read("#{data}/db.sqlite3")).to eq('upgraded') # untouched
        expect(ran).to eq([])
      end
    end

    # Two apps' jobs at once read the shared records, each wrote back its own: one lost the other's
    # entry, and both could take the same free port.
    it "holds the records' lock from choosing the ports to recording them, once, inside or out" do
      locks = []
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with("#{dir}/app-records.lock", anything, anything) { |*args, &block| locks << args.first && File.open(*args.first(1), File::RDWR | File::CREAT, &block) }
      helper.do_install_app('gitea', helper.app_manifest('gitea'))
      expect(locks).to eq(["#{dir}/app-records.lock"]) # the record inside the choice takes no second lock
      expect(helper.with_records_lock { helper.with_records_lock { :inner } }).to eq(:inner)
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

    # The web app's account owned the share root, so a link there in place of a share's folder would
    # have given the app whatever it pointed to (Docker follows links in a mount's source).
    it "refuses a share whose folder is a link, or under one, when the request comes in and again before the container is made" do
      FileUtils.mkdir_p("#{dir}/elsewhere")
      FileUtils.rm_rf("#{files}/downloads")
      File.symlink("#{dir}/elsewhere", "#{files}/downloads")
      expect(refused(transmission, [{ 'name' => 'Downloads' }])).to eq("share Downloads's folder #{files}/downloads isn't a real folder (a link, or missing)")
      FileUtils.rm_f("#{files}/downloads")
      FileUtils.mkdir_p("#{files}/downloads")
      chosen = choose(transmission, [{ 'name' => 'Downloads' }])
      expect { helper.app_share_sources!(chosen) }.not_to raise_error
      FileUtils.rm_rf("#{files}/downloads")
      File.symlink("#{dir}/elsewhere", "#{files}/downloads") # swapped in since the request
      expect { helper.app_share_sources!(chosen) }.to raise_error(AmahiHelper::Failed, /isn't a real folder/)
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

    # Mount as Share, and the setup wizard's FAT, exFAT and NTFS drives, share a drive as it is.
    it "takes a share at a mounted drive's own mount point, and not one at an unmounted drive's" do
      File.write("#{dir}/smb.conf", "#{smb_conf}[USB]\n\tpath = #{drives}/storage-2\n")
      allow(helper).to receive(:real_root?).and_call_original
      allow(helper).to receive(:real_root?).with("#{drives}/storage-2").and_return(true) # the drive mounted there
      expect(choose(transmission, [{ 'name' => 'USB' }])).to eq([{ name: 'USB', path: "#{drives}/storage-2", pooled: false, write: false }])
      allow(helper).to receive(:real_root?).with("#{drives}/storage-2").and_return(false) # an empty folder on the system disk
      expect(refused(transmission, [{ 'name' => 'USB' }])).to include("isn't in the share root or on a mounted data drive")
    end

    it "mounts shares at /shares/<name>, a pooled share with its copy folders, and lets a writer join the users group" do
      allow(helper).to receive(:mount_point?) { |path| path == "#{drives}/storage-1" } # storage-2 isn't mounted
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

    it "makes a pooled share's folder on a mounted pool drive that has none yet, so the app sees the copies made there" do
      allow(helper).to receive(:mount_point?).and_return(true)
      allow(helper).to receive(:real_root?).and_return(true) # the drives are mounted
      allow(helper).to receive(:do_own_dir)
      mounts = helper.app_share_mounts(choose(transmission, [{ 'name' => 'Movies' }]))
      expect(mounts).to include("type=bind,source=#{drives}/storage-2/Movies,target=#{drives}/storage-2/Movies,readonly")
      expect(File.directory?("#{drives}/storage-2/Movies")).to be true
      expect(helper).to have_received(:do_own_dir).with("#{drives}/storage-2/Movies", 'amahi', 'users', '2775').once
      expect(helper).not_to have_received(:do_own_dir).with("#{drives}/storage-1/Movies", anything, anything, anything)

      # A link where the folder would be is left alone, and not mounted
      FileUtils.rm_rf("#{drives}/storage-2/Movies")
      File.symlink('/etc', "#{drives}/storage-2/Movies")
      expect(helper.app_share_mounts(choose(transmission, [{ 'name' => 'Movies' }])).join(' ')).not_to include('storage-2')
      expect { helper.greyhole_copies('..') }.to raise_error(AmahiHelper::Failed, /can't be a folder/)
    end

    # Some folders of a share rather than all of it: each at /shares/<name>/<folder>, from the
    # helper's own mount of it (APP_SHARE_BIND_ROOT), never the folder's path, which an app that
    # writes there could swap for a link.
    describe 'folders of shares' do
      let(:bind_root) { "#{dir}/run/app-shares" }

      before do
        FileUtils.mkdir_p(%W[#{files}/downloads/tv/new #{files}/downloads/music #{files}/movies/Kids])
        stub_const('AmahiHelper::APP_SHARE_BIND_ROOT', bind_root)
        stub_const('AmahiHelper::APP_SHARE_BINDS', "#{dir}/app-share-binds.json")
        allow(helper).to receive(:say)
      end

      it 'takes folders of a share, each read only or read and write' do
        expect(choose(transmission, [{ 'name' => 'Downloads', 'folder' => 'tv/new', 'write' => true }, { 'name' => 'Downloads', 'folder' => 'music' }])).to eq(
          [{ name: 'Downloads', path: "#{files}/downloads", pooled: false, folder: 'tv/new', write: true },
           { name: 'Downloads', path: "#{files}/downloads", pooled: false, folder: 'music', write: false }]
        )
      end

      it 'refuses a folder that is missing, outside the share, odd, or reached through a link, and folders that overlap' do
        FileUtils.mkdir_p("#{dir}/elsewhere")
        File.symlink("#{dir}/elsewhere", "#{files}/downloads/linked")
        expect(refused(transmission, [{ 'name' => 'Downloads', 'folder' => 'films' }])).to eq("Downloads/films isn't a real folder (a link, or missing)")
        expect(refused(transmission, [{ 'name' => 'Downloads', 'folder' => 'linked' }])).to eq("Downloads/linked isn't a real folder (a link, or missing)")
        ['../movies', 'tv/../..', '/etc', 'tv/', 'a,b', 'say "hi"', "tv\nnew", ''].each do |folder|
          expect(refused(transmission, [{ 'name' => 'Downloads', 'folder' => folder }])).to match(/must be a folder inside the share|folder is missing/), folder
        end
        expect(refused(transmission, [{ 'name' => 'Downloads' }, { 'name' => 'Downloads', 'folder' => 'music' }]))
          .to eq('Downloads is given whole, so its folders are in it already')
        expect(refused(transmission, [{ 'name' => 'Downloads', 'folder' => 'music' }, { 'name' => 'downloads', 'folder' => 'music' }]))
          .to eq('Downloads/music is listed twice')
        expect(refused(transmission, [{ 'name' => 'Downloads', 'folder' => 'tv' }, { 'name' => 'Downloads', 'folder' => 'tv/new' }]))
          .to eq('Downloads/tv/new is inside Downloads/tv, given too')
        expect(refused(transmission, [{ 'name' => 'Movies', 'folder' => 'Kids', 'write' => true }])).to eq('share Movies is pooled by Greyhole, so apps can only read it')
      end

      it "mounts each folder from the helper's own mount of it, and a pooled share's folder with that folder of its copies" do
        allow(helper).to receive(:mount_point?) { |path| path == "#{drives}/storage-1" }
        allow(helper).to receive(:real_root?).and_return(true)
        allow(helper).to receive(:do_own_dir)
        allow(helper).to receive(:group_id).and_call_original
        allow(helper).to receive(:group_id).with('users').and_return(100)
        chosen = choose(transmission, [{ 'name' => 'Downloads', 'folder' => 'tv/new', 'write' => true }, { 'name' => 'Movies', 'folder' => 'Kids' }])
        binds = { %w[Downloads tv/new] => "#{bind_root}/transmission/1/0", %w[Movies Kids] => "#{bind_root}/transmission/1/1" }
        expect(helper.app_share_mounts(chosen, binds)).to eq(
          ['--group-add', '100',
           '--mount', "type=bind,source=#{bind_root}/transmission/1/0,target=/shares/Downloads/tv/new",
           '--mount', "type=bind,source=#{bind_root}/transmission/1/1,target=/shares/Movies/Kids,readonly",
           '--mount', "type=bind,source=#{drives}/storage-1/Movies/Kids,target=#{drives}/storage-1/Movies/Kids,readonly"]
        )
        expect(File.directory?("#{drives}/storage-1/Movies/Kids")).to be true # made on the drive, as Greyhole would
        expect { helper.app_share_mounts(chosen, {}) }.to raise_error(AmahiHelper::Failed, "Downloads/tv/new isn't mounted for the app")
      end

      it 'mounts the folders in a set of their own for the next container, and takes the set down if one fails' do
        mounted = []
        allow(helper).to receive(:bind_share_folder) { |root, folder, target| mounted << [root, folder, target] }
        chosen = choose(transmission, [{ 'name' => 'Downloads', 'folder' => 'tv/new' }, { 'name' => 'Downloads', 'folder' => 'music' }])
        binds, set = helper.app_share_binds_make('transmission', chosen)
        expect(set).to match(%r{\A#{bind_root}/transmission/\d{14}-\h{6}\z})
        expect(binds).to eq(%w[Downloads tv/new] => "#{set}/0", %w[Downloads music] => "#{set}/1")
        expect(mounted).to eq([["#{files}/downloads", 'tv/new', "#{set}/0"], ["#{files}/downloads", 'music', "#{set}/1"]])
        expect(helper.app_share_binds_make('transmission', choose(transmission, [{ 'name' => 'Downloads' }]))).to eq([{}, nil])

        allow(helper).to receive(:bind_share_folder).and_raise(AmahiHelper::Failed, 'mount exited 32')
        allow(helper).to receive(:app_share_binds_remove)
        expect { helper.app_share_binds_make('transmission', chosen) }.to raise_error(AmahiHelper::Failed, 'mount exited 32')
        expect(helper).to have_received(:app_share_binds_remove).with(start_with("#{bind_root}/transmission/"))
      end

      it 'records the set the container mounts for the restart, and takes down the sets before it' do
        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
        allow(helper).to receive(:app_share_binds_remove)
        FileUtils.mkdir_p(%W[#{bind_root}/transmission/20261026000000-aaaaaa #{bind_root}/transmission/20261027000000-bbbbbb])
        chosen = choose(transmission, [{ 'name' => 'Downloads', 'folder' => 'tv/new' }])
        helper.app_share_binds_keep('transmission', "#{bind_root}/transmission/20261027000000-bbbbbb", chosen)
        expect(JSON.parse(File.read("#{dir}/app-share-binds.json"))).to eq(
          'transmission' => [{ 'path' => "#{bind_root}/transmission/20261027000000-bbbbbb/0", 'share' => 'Downloads', 'folder' => 'tv/new' }]
        )
        expect(helper).to have_received(:app_share_binds_remove).with("#{bind_root}/transmission/20261026000000-aaaaaa").once

        helper.app_share_binds_keep('transmission', nil, []) # given whole shares again, or uninstalled
        expect(JSON.parse(File.read("#{dir}/app-share-binds.json"))).to eq({})
        expect(helper).to have_received(:app_share_binds_remove).with("#{bind_root}/transmission/20261027000000-bbbbbb")
      end

      # apps.share_binds, from amahi-kai-app-shares.service before Docker starts: /run is empty after a restart.
      it "mounts the recorded folders again after a restart, from the share's folder now, and leaves out what can't be" do
        set = "#{bind_root}/transmission/20261027000000-bbbbbb"
        File.write("#{dir}/app-share-binds.json", {
          'transmission' => [{ 'path' => "#{set}/0", 'share' => 'Downloads', 'folder' => 'tv/new' },
                             { 'path' => "#{set}/1", 'share' => 'Downloads', 'folder' => 'gone' },
                             { 'path' => '/etc/passwd', 'share' => 'Downloads', 'folder' => 'tv/new' },
                             { 'path' => "#{set}/3", 'share' => 'Photos', 'folder' => 'x' }]
        }.to_json)
        mounted = []
        allow(helper).to receive(:bind_share_folder).and_call_original
        allow(helper).to receive(:with_dir).and_call_original
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(hash_including('PATH'), ['/usr/bin/mount', '/usr/bin/mount'], '--no-canonicalize', '--bind', anything, anything, anything) do |*args|
          mounted << args[5]
          ['', '', instance_double(Process::Status, success?: true)]
        end
        expect(helper.do_share_binds).to eq('transmission' => {
          "#{set}/0" => 'mounted',
          "#{set}/1" => "#{files}/downloads/gone doesn't exist",
          '/etc/passwd' => "/etc/passwd isn't one of the helper's",
          "#{set}/3" => '"Photos" isn\'t one of the NAS\'s shares'
        })
        expect(mounted).to eq(["#{set}/0"])
        expect(File.directory?("#{set}/1")).to be false # no empty folder for Docker to mount in its place
      end

      it "binds the folder through a handle on it, refusing one reached through a link" do
        allow(Open3).to receive(:capture3).and_call_original
        FileUtils.mkdir_p("#{dir}/elsewhere")
        FileUtils.rm_rf("#{files}/downloads/tv")
        File.symlink("#{dir}/elsewhere", "#{files}/downloads/tv") # a writer swapped the folder above it for a link
        FileUtils.mkdir_p("#{dir}/elsewhere/new")
        expect { helper.bind_share_folder("#{files}/downloads", 'tv/new', "#{bind_root}/t/1/0") }
          .to raise_error(AmahiHelper::Failed, /moved while it was being changed/)
        File.unlink("#{files}/downloads/tv")
        File.symlink("#{dir}/elsewhere/new", "#{files}/downloads/tv") # the folder itself
        expect { helper.bind_share_folder("#{files}/downloads", 'tv', "#{bind_root}/t/1/0") }.to raise_error(AmahiHelper::Failed, /is not a folder/)
        expect(Open3).not_to have_received(:capture3).with(anything, ['/usr/bin/mount', '/usr/bin/mount'], any_args)
        expect(File.exist?("#{bind_root}/t/1/0")).to be false
      end

      it "mounts the folder itself, as root" do
        skip 'needs root' unless Process.euid.zero?

        target = "#{bind_root}/t/1/0"
        File.write("#{files}/downloads/tv/new/episode.mkv", 'x')
        helper.bind_share_folder("#{files}/downloads", 'tv/new', target)
        expect(Dir.children(target)).to eq(['episode.mkv'])
        helper.app_share_binds_remove("#{bind_root}/t/1")
        expect(File.exist?(target)).to be false
      end

      it "mounts the folders for a container, and mounts them again from the record after a restart, as root" do
        skip 'needs root' unless Process.euid.zero?

        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
        File.write("#{files}/downloads/music/song.flac", 'x')
        chosen = choose(transmission, [{ 'name' => 'Downloads', 'folder' => 'music' }])
        binds, set = helper.app_share_binds_make('transmission', chosen)
        helper.app_share_binds_keep('transmission', set, chosen)
        expect(Dir.children(binds[%w[Downloads music]])).to eq(['song.flac'])

        helper.app_share_binds_remove(set) # /run, emptied by a restart
        expect(File.exist?(set)).to be false
        expect(helper.do_share_binds).to eq('transmission' => { "#{set}/0" => 'mounted' })
        expect(Dir.children("#{set}/0")).to eq(['song.flac'])
        expect(helper.do_share_binds).to eq('transmission' => { "#{set}/0" => 'mounted' }) # once
        expect(File.foreach('/proc/self/mountinfo').count { |line| line.split(' ')[4] == "#{set}/0" }).to eq(1)
        helper.app_share_binds_keep('transmission', nil, [])
        expect(File.exist?(set)).to be false
      end

      it "follows the pool with the folders a container has, written to only where the app writes shares" do
        allow(helper).to receive(:do_install_app)
        allow(helper).to receive(:do_app_firewall)
        allow(helper).to receive(:greyhole_copies).with('Movies', 'Kids').and_return(["#{drives}/storage-1/Movies/Kids"])
        mounts = [{ 'Destination' => '/shares/Movies/Kids', 'Source' => "#{bind_root}/transmission/1/0", 'RW' => false },
                  { 'Destination' => '/shares/Downloads/tv/new', 'Source' => "#{bind_root}/transmission/1/1", 'RW' => true },
                  { 'Destination' => "#{drives}/storage-1/Movies/Kids", 'RW' => false },
                  { 'Destination' => "#{drives}/storage-2/Movies/Kids", 'RW' => false }]
        allow(helper).to receive(:docker_output) do |*args|
          args.first == 'ps' ? 'transmission' : [{ 'Mounts' => mounts, 'State' => { 'Running' => true, 'Error' => '' } }].to_json
        end
        expect(helper.do_follow_pool_apps).to eq(
          'apps' => { 'transmission' => 'remade' },
          'shares' => { 'transmission' => [{ 'name' => 'Movies', 'folder' => 'Kids', 'write' => false },
                                           { 'name' => 'Downloads', 'folder' => 'tv/new', 'write' => true }] }
        )
        expect(helper).to have_received(:do_install_app).with(
          'transmission', anything,
          [{ name: 'Movies', path: "#{files}/movies", pooled: true, folder: 'Kids', write: false },
           { name: 'Downloads', path: "#{files}/downloads", pooled: false, folder: 'tv/new', write: true }], true
        )
      end
    end

    # The NAS's DNS for apps: the bridge's address while Unbound's config listens there (DnsService
    # writes it while Docker runs), with the local domain to search.
    describe "the NAS's DNS for an app" do
      before do
        allow(helper).to receive(:app_dns_options).and_call_original
        stub_const('AmahiHelper::UNBOUND_CONF', "#{dir}/amahi-kai.conf")
        allow(helper).to receive(:docker_bridge_address).and_return('172.17.0.1')
      end

      it "is the bridge's address and the local domain while Unbound answers there, else Docker's own" do
        expect(helper.app_dns_options).to eq([]) # DNS off: no config
        File.write(AmahiHelper::UNBOUND_CONF, %(server:\n  interface: 127.0.0.1\n  interface: 192.168.1.1\n  local-zone: "home.arpa." static\n))
        expect(helper.app_dns_options).to eq([]) # not on the bridge (Docker started after the last save)
        File.write(AmahiHelper::UNBOUND_CONF, %(server:\n  interface: 192.168.1.1\n  interface: 172.17.0.1\n  local-zone: "home.arpa." static\n))
        expect(helper.app_dns_options).to eq(['--dns', '172.17.0.1', '--dns-search', 'home.arpa'])
        allow(helper).to receive(:docker_bridge_address).and_return(nil) # Docker down
        expect(helper.app_dns_options).to eq([])
      end
    end

    # apps.follow_dns: each app container made with other DNS than the NAS's now is made again,
    # keeping its shares, version and data.
    describe 'following the DNS' do
      def containers(states)
        allow(helper).to receive(:docker_output) do |*args|
          if args.first == 'ps' then states.keys.join("\n")
          else
            id = args.last.delete_prefix('amahi-')
            [{ 'Mounts' => [{ 'Destination' => '/shares/Movies', 'Source' => "#{files}/movies", 'RW' => false }],
               'State' => states[id][:state], 'HostConfig' => states[id][:dns] }].to_json
          end
        end
      end

      let(:nas_dns) { { 'Dns' => ['172.17.0.1'], 'DnsSearch' => ['home.arpa'] } }

      before do
        allow(helper).to receive(:do_install_app)
        allow(helper).to receive(:run_command)
        allow(helper).to receive(:do_app_firewall)
        allow(helper).to receive(:app_manifest).and_return({})
        allow(helper).to receive(:app_dns_options).and_return(['--dns', '172.17.0.1', '--dns-search', 'home.arpa'])
      end

      it "makes again the apps made with other DNS, keeping their shares, and a stopped one stopped" do
        containers('jellyfin' => { state: { 'Running' => true }, dns: { 'Dns' => [], 'DnsSearch' => [] } },
                   'gitea' => { state: { 'Running' => true }, dns: nas_dns },
                   'emby' => { state: { 'Running' => false }, dns: {} })
        expect(helper.do_follow_dns_apps).to eq('apps' => { 'jellyfin' => 'remade', 'emby' => 'remade, stopped' })
        expect(helper).to have_received(:do_install_app).with('jellyfin', {}, [{ name: 'Movies', path: "#{files}/movies", pooled: true, write: false }], true)
        expect(helper).to have_received(:run_command).with(['/usr/bin/docker', 'stop', '--time', '30', 'amahi-emby']).once
        expect(helper).to have_received(:do_app_firewall)
      end

      it "gives back Docker's own DNS once the NAS's stops answering on the bridge, and leaves an app whose job runs to it" do
        allow(helper).to receive(:app_dns_options).and_return([])
        containers('gitea' => { state: { 'Running' => true }, dns: nas_dns }, 'jellyfin' => { state: { 'Running' => true }, dns: nas_dns })
        allow(helper).to receive(:app_job_running?).with('jellyfin').and_return(true)
        expect(helper.do_follow_dns_apps).to eq('apps' => { 'gitea' => 'remade' })
      end

      it 'leaves alone the apps that already have it, and does nothing without Docker' do
        containers('gitea' => { state: { 'Running' => true }, dns: nas_dns })
        expect(helper.do_follow_dns_apps).to eq('apps' => {})
        expect(helper).not_to have_received(:do_app_firewall)
        allow(helper).to receive(:docker_output).and_return(nil)
        expect(helper.do_follow_dns_apps).to eq('apps' => {})
      end
    end

    # apps.follow_pool: each app container whose pool drive mounts don't match the pool now is
    # made again, keeping its shares (read from its mounts), version and data.
    describe 'following the pool' do
      let(:jellyfin_mounts) do
        [{ 'Destination' => '/shares/Movies', 'Source' => "#{files}/movies", 'RW' => false },
         { 'Destination' => '/shares/Downloads', 'Source' => "#{files}/downloads", 'RW' => true },
         { 'Destination' => "#{drives}/storage-1/Movies", 'RW' => false },
         { 'Destination' => "#{drives}/storage-2/Movies", 'RW' => false },
         { 'Destination' => '/config', 'RW' => true }]
      end

      def containers(states)
        allow(helper).to receive(:docker_output) do |*args|
          if args.first == 'ps' then states.keys.join("\n")
          else
            id = args.last.delete_prefix('amahi-')
            [{ 'Mounts' => states[id][:mounts], 'State' => states[id][:state] }].to_json
          end
        end
      end

      before do
        allow(helper).to receive(:do_install_app)
        allow(helper).to receive(:run_command)
        allow(helper).to receive(:do_app_firewall)
        allow(helper).to receive(:greyhole_copies).with('Movies').and_return(["#{drives}/storage-1/Movies"]) # storage-2 is missing
      end

      it "makes again, with the drives there are, an app whose mounts don't match the pool, keeping its shares" do
        containers('transmission' => { mounts: jellyfin_mounts, state: { 'Running' => true, 'Error' => '' } })
        expect(helper.do_follow_pool_apps).to eq(
          'apps' => { 'transmission' => 'remade' },
          'shares' => { 'transmission' => [{ 'name' => 'Movies', 'write' => false }, { 'name' => 'Downloads', 'write' => true }] }
        )
        expect(helper).to have_received(:do_install_app).with(
          'transmission', anything,
          [{ name: 'Movies', path: "#{files}/movies", pooled: true, write: false },
           { name: 'Downloads', path: "#{files}/downloads", pooled: false, write: true }], true
        )
        expect(helper).not_to have_received(:run_command)
        expect(helper).to have_received(:do_app_firewall)
      end

      # follow_pool remade containers with no check at all: its shares are checked as apps.install
      # checks them, and an app that only reads shares gets them read only, whatever its mounts say.
      it "checks the shares as an install does, and writes only where the app writes shares" do
        containers('jellyfin' => { mounts: jellyfin_mounts, state: { 'Running' => true, 'Error' => '' } })
        expect(helper.do_follow_pool_apps['shares']).to eq('jellyfin' => [{ 'name' => 'Movies', 'write' => false },
                                                                           { 'name' => 'Downloads', 'write' => false }])
        FileUtils.rm_rf("#{files}/downloads")
        File.symlink('/etc', "#{files}/downloads")
        expect(helper.do_follow_pool_apps['apps']).to eq('jellyfin' => "share Downloads's folder #{files}/downloads isn't a real folder (a link, or missing)")
      end

      it 'leaves an app whose job is running to that job' do
        containers('jellyfin' => { mounts: jellyfin_mounts, state: { 'Running' => true, 'Error' => '' } })
        allow(helper).to receive(:app_job_running?).with('jellyfin').and_return(true)
        expect(helper.do_follow_pool_apps).to eq('apps' => {}, 'shares' => {})
        expect(helper).not_to have_received(:do_install_app)
      end

      it "leaves an app whose mounts match alone, remakes one that couldn't start over a mount, and keeps a stopped one stopped" do
        matching = jellyfin_mounts.reject { |mount| mount['Destination'].include?('storage-2') }
        containers('jellyfin' => { mounts: matching, state: { 'Running' => true, 'Error' => '' } },
                   'plex' => { mounts: matching, state: { 'Running' => false, 'Error' => 'failed to fulfil mount request: open /mnt/storage-2/Movies' } },
                   'emby' => { mounts: jellyfin_mounts, state: { 'Running' => false, 'Error' => '' } })
        allow(helper).to receive(:app_manifest).and_return({})
        expect(helper.do_follow_pool_apps['apps']).to eq('plex' => 'remade', 'emby' => 'remade, stopped')
        expect(helper).to have_received(:run_command).with(['/usr/bin/docker', 'stop', '--time', '30', 'amahi-emby']).once
      end

      it "goes on past an app it can't make again, giving the reason" do
        containers('jellyfin' => { mounts: jellyfin_mounts, state: { 'Running' => true, 'Error' => '' } })
        allow(helper).to receive(:do_install_app).and_raise(AmahiHelper::Failed, 'docker exited 125: no space')
        expect(helper.do_follow_pool_apps).to eq('apps' => { 'jellyfin' => 'docker exited 125: no space' }, 'shares' => {})
      end

      it 'does nothing without Docker' do
        allow(helper).to receive(:docker_output).and_return(nil)
        expect(helper.do_follow_pool_apps).to eq('apps' => {}, 'shares' => {})
      end
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

  # tailscaled holds a served app's port on the Tailscale addresses (another address stands in for
  # them here): checked on 0.0.0.0 that reads as taken, on 127.0.0.1, where the app is published, not
  it 'sees a port as free on the address an app is published on, while something listens on another' do
    server = TCPServer.new('127.0.0.2', 0)
    port = server.addr[1]
    expect(helper.port_bindable?(port, 'tcp')).to be false
    expect(helper.port_bindable?(port, 'tcp', '127.0.0.1')).to be true
  ensure
    server&.close
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

    # Router mode and This NAS change the LAN's subnets: devices on a new one couldn't reach the
    # apps, and an old one stayed let in.
    it "is rebuilt after the network changes, where Docker runs, and says so when that fails" do
      allow(helper).to receive(:docker_output).with('info', '--format', '{{.ServerVersion}}').and_return(nil)
      allow(helper).to receive(:do_app_firewall)
      expect(helper.refresh_app_firewall).to be_nil
      expect(helper).not_to have_received(:do_app_firewall)
      allow(helper).to receive(:docker_output).with('info', '--format', '{{.ServerVersion}}').and_return("27.3.1\n")
      expect(helper.refresh_app_firewall).to be_nil
      expect(helper).to have_received(:do_app_firewall).once
      allow(helper).to receive(:do_app_firewall).and_raise(AmahiHelper::Failed, 'iptables exited 4')
      expect(helper.refresh_app_firewall).to eq("the app firewall wasn't rebuilt for the network's change: iptables exited 4")
      source = HelperSource.text
      %w[do_router_on do_router_off do_apply_address do_revert_address].each do |step|
        body = source[/    def #{step}\b.*?\n    end\n/m]
        expect(body).to include('refresh_app_firewall'), step
      end
    end

    it "is run each time Docker starts" do
      expect(steps('apps.firewall', {})).to eq([[:app_firewall]])
      unit = File.read(Rails.root.join('config/systemd/amahi-kai-app-firewall.service'))
      expect(unit).to include('ExecStart=/usr/local/sbin/amahi-helper apps.firewall', 'After=docker.service',
                              'PartOf=docker.service', 'WantedBy=docker.service')
    end

    # Rebuilt rule by rule, the chain was empty for a moment, which let everything through: its
    # rules go in in one iptables-restore.
    it "lets in only the NAS's private subnets and Tailscale, and drops the rest, the rules swapped in whole" do
      expect(helper.do_app_firewall).to eq('lan' => ['192.168.1.0/24', '10.20.0.0/16'])
      rules = ran.map { |argv| argv.reject { |arg| arg.is_a?(Hash) } }
      expect(rules).to eq([
                            %w[/usr/sbin/iptables -w -N DOCKER-USER], %w[/usr/sbin/iptables -w -N AMAHI-APPS],
                            %w[/usr/sbin/iptables-restore -w --noflush],
                            %w[/usr/sbin/iptables -w -C DOCKER-USER -j AMAHI-APPS],
                            %w[/usr/sbin/iptables -w -I DOCKER-USER 1 -j AMAHI-APPS]
                          ])
      expect(ran[2].last[:stdin]).to eq(<<~RULES)
        *filter
        :AMAHI-APPS - [0:0]
        -A AMAHI-APPS -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
        -A AMAHI-APPS ! -o docker0 -j RETURN
        -A AMAHI-APPS -i docker0 -j RETURN
        -A AMAHI-APPS -i tailscale0 -j RETURN
        -A AMAHI-APPS -s 192.168.1.0/24 -j RETURN
        -A AMAHI-APPS -s 10.20.0.0/16 -j RETURN
        -A AMAHI-APPS -j DROP
        COMMIT
      RULES
    end

    # Docker starts the apps' containers, ports and all, before amahi-kai-app-firewall.service runs.
    it "is in place before Docker starts too" do
      unit = File.read(Rails.root.join('config/systemd/amahi-kai-app-firewall-early.service'))
      expect(unit).to include('ExecStart=/usr/local/sbin/amahi-helper apps.firewall', 'Before=docker.service',
                              'After=network-online.target', 'WantedBy=docker.service')
      expect(File.read(Rails.root.join('bin/amahi-install-helper'))).to include('amahi-kai-app-firewall-early.service', 'systemctl enable amahi-kai-app-firewall-early.service')
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

  # An install, update, undo or uninstall runs as a unit of its own: a restart of the web app,
  # whose unit the helper ran in, took the job down partway (an install left on Installing).
  describe 'jobs' do
    let(:runs) { [] }

    before do
      stub_const('AmahiHelper::RUN_DIR', dir)
      allow(helper).to receive(:replace_process) { |env, argv, **opts| runs << [env, argv, opts[:in].read, File.exist?(opts[:in].path)] }
    end

    def call(op, args, env = {})
      out = StringIO.new
      saved = env.keys.to_h { |key| [key, ENV[key]] }
      env.each { |key, value| ENV[key] = value }
      code = helper.main([op], input: StringIO.new(args), output: out)
      [code, out.string.empty? ? nil : JSON.parse(out.string)]
    ensure
      saved&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "runs each in a unit of its own, named for the app, with the same arguments and who asked" do
      call('apps.install', '{"app":"gitea","shares":[]}', 'SUDO_USER' => 'amahi')
      env, argv, input, left = runs.sole
      expect(env).to eq(AmahiHelper::ENV_MIN)
      expect(argv).to eq(['/usr/bin/systemd-run', '--unit=amahi-kai-appjob-gitea', '--wait', '--pipe', '--collect', '--quiet',
                          '--setenv=AMAHI_APP_JOB=gitea', '--setenv=AMAHI_APP_CALLER=amahi', '/usr/local/sbin/amahi-helper', 'apps.install'])
      expect(input).to eq('{"app":"gitea","shares":[]}')
      expect(left).to be false # the arguments' file is gone once it's open
      %w[apps.update apps.undo_update apps.uninstall].each { |op| call(op, '{"app":"gitea"}') }
      expect(runs.map { |run| run[1].last }).to eq(%w[apps.install apps.update apps.undo_update apps.uninstall])
    end

    it "refuses a second job for an app while one runs, and names no unit for arguments that don't name an app" do
      allow(helper).to receive(:app_job_running?).with('gitea').and_return(true)
      expect(call('apps.update', '{"app":"gitea"}')).to eq([1, { 'ok' => false, 'error' => "gitea is being changed (an install, update or uninstall runs): try again when it's done" }])
      code, reply = call('apps.install', '{"app":"../etc"}') # refused where it is (here, by the helper's own checks first)
      expect([code, reply['ok']]).to eq([1, false])
      expect(runs).to be_empty
    end

    it 'runs the job itself inside its unit, and logs who asked for it' do
      allow(helper).to receive(:execute).and_return('ok' => true)
      expect(call('apps.install', '{"app":"gitea"}', 'AMAHI_APP_JOB' => 'gitea')).to eq([0, { 'ok' => true }])
      expect(runs).to be_empty
      ENV['AMAHI_APP_CALLER'] = 'amahi'
      expect(helper.app_job_caller).to eq('amahi')
    ensure
      ENV.delete('AMAHI_APP_CALLER')
    end

    it "asks systemd whether an app's job runs, and never counts the job itself" do
      allow(helper).to receive(:app_job_running?).and_call_original
      allow(Open3).to receive(:capture3).and_return(['', '', instance_double(Process::Status, success?: true)])
      expect(helper.app_job_running?('gitea')).to be true
      expect(Open3).to have_received(:capture3).with(AmahiHelper::ENV_MIN, '/usr/bin/systemctl', 'is-active', '--quiet',
                                                     'amahi-kai-appjob-gitea.service', unsetenv_others: true, chdir: '/')
      ENV['AMAHI_APP_JOB'] = 'gitea'
      expect(helper.app_job_running?('gitea')).to be false
    ensure
      ENV.delete('AMAHI_APP_JOB')
    end

    it 'lists the apps whose jobs run, for the Apps page' do
      allow(helper).to receive(:app_jobs_running).and_call_original
      allow(Open3).to receive(:capture3).and_return(["amahi-kai-appjob-gitea.service loaded active running x\namahi-kai-appjob-Bad.service x\n", '',
                                                     instance_double(Process::Status, success?: true)])
      expect(helper.app_jobs_running).to eq(['gitea'])
    end
  end

  # An app whose page is HTTPS only (web_tls) doesn't answer plain HTTP: its update was rolled
  # back for not coming up.
  describe 'the health check' do
    let(:key) { OpenSSL::PKey::RSA.new(2048) }
    let(:cert) do
      OpenSSL::X509::Certificate.new.tap do |c|
        c.version = 2
        c.serial = 1
        c.subject = c.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
        c.public_key = key.public_key
        c.not_before = Time.now - 60
        c.not_after = Time.now + 3600
        c.sign(key, OpenSSL::Digest.new('SHA256'))
      end
    end

    def serve(tls:)
      server = TCPServer.new('127.0.0.1', 0)
      Thread.new do
        socket = server.accept
        if tls
          context = OpenSSL::SSL::SSLContext.new
          context.cert = cert
          context.key = key
          ssl = OpenSSL::SSL::SSLSocket.new(socket, context)
          ssl.accept
          ssl.close
        else
          socket.write("HTTP/1.0 200 OK\r\n\r\n")
          socket.close
        end
      rescue StandardError
        nil
      end
      server.addr[1]
    end

    before { stub_const('AmahiHelper::APP_PORTS', "#{dir}/app-ports.json") }

    it 'takes a TLS handshake from an HTTPS app, and an HTTP reply from the others' do
      port = serve(tls: true)
      expect(helper.app_answers?('vaultwarden', { web_port: port, web_tls: true })).to be true
      port = serve(tls: false)
      expect(helper.app_answers?('gitea', { web_port: port, web_tls: false })).to be true
      port = serve(tls: false) # plain HTTP where HTTPS is wanted: no handshake
      expect(helper.app_answers?('vaultwarden', { web_port: port, web_tls: true })).to be false
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
      allow(helper).to receive(:app_jobs_running).and_return(['gitea'])
      expect(helper.do_apps_status).to eq(
        'docker' => true,
        'apps' => { 'gitea' => { 'state' => 'running', 'status' => 'Up 2 hours', 'image' => 'gitea/gitea:1.27.3-rootless' },
                    'jellyfin' => { 'state' => 'exited', 'status' => 'Exited (1) 3 minutes ago', 'image' => 'jellyfin/jellyfin:12.1' } },
        'jobs' => ['gitea']
      )
    end

    it "says when Docker isn't running" do
      docker_says('', success: false)
      expect(helper.do_apps_status).to eq('docker' => false, 'apps' => {}, 'jobs' => [])
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
