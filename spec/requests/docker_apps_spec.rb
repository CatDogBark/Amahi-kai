require 'spec_helper'

# The Apps pages (docs/plans/apps.md, P4.1): the catalog's apps, installed through the root
# helper. Outside production Privileged.call records each call instead of running it.
describe "Docker Apps", type: :request do
  before do
    login_as_admin
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
  end

  def gitea(attrs = {})
    DockerApp.create!({ identifier: 'gitea', name: 'Gitea', image: AppCatalog.find('gitea')[:image], status: 'running',
                        host_port: 3300 }.merge(attrs))
  end

  def helper_fails(operation, message)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with(operation, any_args).and_raise(Privileged::Error.new(operation, message))
  end

  # The catalog fetched from its own repo (with the helper's update check); outside
  # production it lives in tmp/.
  describe "the catalog's own repo" do
    let(:fetched) { Rails.root.join('tmp', 'catalog', 'apps').to_s }
    let(:status_path) { Rails.root.join('tmp', 'catalog-status.json').to_s }

    before do
      FileUtils.rm_rf([File.dirname(fetched), status_path])
      AppCatalog.reload!
    end

    after do
      FileUtils.rm_rf([File.dirname(fetched), status_path])
      AppCatalog.reload!
    end

    it "says where the catalog came from, with Check now" do
      get "/apps/docker_apps"
      expect(response.body).to include('App catalog: the copy that came with Amahi-kai', 'action="/apps/refresh_catalog"')

      File.write(status_path, { checked_at: 1.hour.ago.utc.iso8601, commit: 'abc1234', apps: %w[gitea], error: 'GitHub is offline',
                                problems: [{ app: 'broken', problem: 'image must be name:tag@sha256:digest' }] }.to_json)
      get "/apps/installed_apps"
      expect(response.body).to include('App catalog checked', 'the last check failed: GitHub is offline',
                                       'skipped broken (image must be name:tag@sha256:digest)')
    end

    it "fetches it on Check now, and says what happened" do
      post "/apps/refresh_catalog"
      expect(Privileged.calls).to include(['system.check_update', {}]) # Amahi-kai and the catalog
      expect(response).to redirect_to('/apps')
      expect(flash[:notice]).to eq('Checked Amahi-kai and the apps for updates.')

      File.write(status_path, { checked_at: Time.now.utc.iso8601, error: 'GitHub is offline' }.to_json)
      post "/apps/refresh_catalog", headers: { 'Referer' => 'http://www.example.com/apps/installed_apps' }
      expect(response).to redirect_to('http://www.example.com/apps/installed_apps')
      expect(flash[:alert]).to eq("Couldn't refresh the app catalog: GitHub is offline")
    end

    it "lists an app that needs a newer Amahi-kai, without Install" do
      FileUtils.mkdir_p(fetched)
      FileUtils.cp(Dir[Rails.root.join('config/apps/*.yml')], fetched)
      File.write("#{fetched}/future.yml", "name: Future\ndescription: Later.\ncategory: media\nrequires: #{AppCatalog::FORMAT + 1}\n")
      AppCatalog.reload!
      get "/apps/docker_apps"
      expect(response.body).to include('Future', 'Needs a newer Amahi-kai: run System Update first', 'data-app-shares="gitea"')
      expect(response.body).not_to include('data-app-shares="future"')
    end

    it "holds back an update that needs a newer Amahi-kai" do
      FileUtils.mkdir_p(fetched)
      newer = File.read(Rails.root.join('config/apps/gitea.yml'))
                  .sub(/^image: .*$/, "image: gitea/gitea:9.9.9-rootless@sha256:#{'c' * 64}") + "requires: #{AppCatalog::FORMAT + 1}\n"
      File.write("#{fetched}/gitea.yml", newer)
      AppCatalog.reload!
      gitea(image: YAML.safe_load(File.read(Rails.root.join('config/apps/gitea.yml')))['image']) # what came with Amahi-kai
      get "/apps/installed_apps"
      expect(response.body).to include('9.9.9-rootless needs a newer Amahi-kai: run System Update first')
      expect(response.body).not_to include('Update to 9.9.9-rootless')
    end
  end

  describe "the catalog page" do
    it "lists the catalog's apps, with Install for the ones not installed" do
      get "/apps/docker_apps"
      expect(response).to have_http_status(:ok)
      %w[Jellyfin Vaultwarden Gitea Transmission].each { |name| expect(response.body).to include(name) }
      expect(response.body).to include('data-app-shares="uptimekuma"', 'data-url="/apps/docker/install_stream/uptimekuma"')
      expect(response.body).to include('id="app-shares-dialog"')
    end

    it "asks Docker for the apps' states, and links a running app to its own port" do
      gitea
      get "/apps/docker_apps", headers: { 'Host' => '192.168.1.111' }
      expect(Privileged.calls).to include(['apps.status', {}])
      expect(response.body).to include('href="http://192.168.1.111:3300/"')
      expect(response.body).not_to include('/app/gitea')
      expect(response.body).to include("Its data stays in #{AppCatalog.apps_root}/gitea")
    end

    # How to sign in the first time, open, above the passwords Amahi-kai made (kept folded away)
    it "says how to sign in on an installed app's row, above the passwords Amahi-kai made for it" do
      secrets = File.join(AppCatalog.secrets_dir, 'transmission.json')
      FileUtils.mkdir_p(File.dirname(secrets))
      File.write(secrets, { 'PASS' => 'Gener4ted' }.to_json)
      DockerApp.create!(identifier: 'transmission', name: 'Transmission', image: AppCatalog.find('transmission')[:image],
                        status: 'running', host_port: 9091)
      gitea
      get "/apps/installed_apps"
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#app-sign-in-transmission').text.squish)
        .to eq('First sign-in: Sign in as admin with the password Amahi-kai made for it.')
      expect(page.at_css('#docker_app_transmission details.app-secrets code').text).to eq('Gener4ted')
      expect(page.at_css('#app-sign-in-gitea').text.squish).to start_with('First sign-in: Its first page sets it up')
      expect(page.at_css('#docker_app_gitea details.app-secrets')).to be_nil # nothing made for it
    ensure
      FileUtils.rm_f(secrets)
    end

    it "shows each installed app's ports" do
      gitea(port_mappings: [{ host: 3300, protocol: 'tcp', label: 'web' }, { host: 2222, protocol: 'tcp', label: 'Git over SSH' }].to_json)
      get "/apps/installed_apps"
      expect(CGI.unescapeHTML(response.body)).to include('Ports 3300 (web) · 2222 (Git over SSH)')
    end

    it "says to open apps on the LAN or Tailscale when the page came through the Cloudflare Tunnel" do
      gitea
      get "/apps/docker_apps", headers: { 'Host' => 'nas.example.com', 'CF-Connecting-IP' => '203.0.113.9' }
      expect(response.body).not_to include('href="http://nas.example.com:3300/"')
      expect(response.body).to include('Open it on your LAN or Tailscale')
    end

    it "filters by category" do
      get "/apps/docker_apps", params: { category: "media" }
      expect(response.body).to include("Jellyfin")
      expect(response.body).not_to include("Vaultwarden")
    end

    it "offers to delete the data an earlier install kept" do
      allow(AppCatalog).to receive(:data_kept?).and_return(false)
      allow(AppCatalog).to receive(:data_kept?).with('gitea').and_return(true)
      get "/apps/docker_apps"
      expect(response.body).to include("/apps/docker/uninstall/gitea?delete_data=1")
      expect(response.body.scan("delete_data=1").size).to eq(1)
    end

    it "shows an installed app's generated passwords to admins, with a copy button" do
      gitea(identifier: 'transmission', name: 'Transmission', host_port: 9091)
      allow(AppCatalog).to receive(:secrets).and_return([])
      allow(AppCatalog).to receive(:secrets).with('transmission')
                                            .and_return([{ label: 'Web interface password (user admin)', value: 'pa55word' }])
      get "/apps/installed_apps"
      expect(response.body).to include('Web interface password (user admin)')
      expect(response.body).to include('data-copy="pa55word"')
    end

    it "shows Docker as not installed when checking it fails" do
      allow(DockerService).to receive(:installed?).and_raise(RuntimeError, "docker not found")
      get "/apps/docker_apps"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Install Docker')
    end
  end

  # P4.6: an app whose catalog entry keeps folders on a ZFS pool (kind: dataset).
  describe "storage on a ZFS pool" do
    let(:fetched) { Rails.root.join('tmp', 'catalog', 'apps').to_s }
    let(:storage) { AppCatalog.storage_path }

    before do
      FileUtils.rm_rf(File.dirname(fetched))
      FileUtils.mkdir_p(fetched)
      File.write("#{fetched}/store.yml", File.read(File.join(AppCatalog::CATALOG_DIR, 'uptimekuma.yml'))
                                            .sub(/^name: .*$/, 'name: Store')
                                            .sub('  - { name: data, path: /app/data }', '  - { name: data, path: /app/data, kind: dataset }'))
      FileUtils.cp(File.join(AppCatalog::CATALOG_DIR, 'gitea.yml'), fetched)
      AppCatalog.reload!
      allow(StoragePools).to receive(:zfs_installed?).and_return(true)
      allow(StoragePools).to receive(:status).and_return(
        installed: true, offline: [], error: nil,
        pools: [StoragePools::Pool.new(name: 'tank', managed: true, vdevs: [{ 'name' => 'mirror-0', 'children' => [] }]),
                StoragePools::Pool.new(name: 'rpool', managed: false, vdevs: [])] # a system's own: not offered
      )
    end

    after do
      FileUtils.rm_rf([File.dirname(fetched), storage])
      AppCatalog.reload!
    end

    it "offers the online pools in the install dialog, and says when there's none" do
      get "/apps"
      page = Nokogiri::HTML(response.body)
      install = page.at_css('#docker_app_store button[data-app-shares]')
      expect(install['data-storage']).to eq('required')
      expect(install['data-storage-pool']).to eq('')
      expect(page.css('#app-storage-pool option').map { |o| [o['value'], o.text.strip] })
        .to eq([['', 'None: without what it keeps on a pool'], ['tank', 'ZFS pool tank (Mirror)']])
      expect(page.at_css('#docker_app_gitea button[data-app-shares]')['data-storage']).to eq('')

      allow(StoragePools).to receive(:status).and_return(installed: true, offline: [], error: nil, pools: [])
      get "/apps"
      page = Nokogiri::HTML(response.body)
      expect(page.css('#app-storage-pool option').size).to eq(1)
      expect(page.at_css('[data-role="storage-missing"]').text.squish).to include("there isn't one yet", 'Disks → ZFS Pools')
    end

    it "passes the pool chosen to the helper, only for an app that keeps data on one" do
      get "/apps/docker/install_stream/store", params: { pool: 'tank' }, headers: same_origin
      expect(Privileged.calls).to include(['apps.install', { app: 'store', shares: [], pool: 'tank' }])
      get "/apps/docker/install_stream/gitea", params: { pool: 'tank' }, headers: same_origin
      expect(Privileged.calls).to include(['apps.install', { app: 'gitea', shares: [] }])
    end

    it "says on an installed app's row which pool its data is on" do
      DockerApp.create!(identifier: 'store', name: 'Store', image: AppCatalog.find('store')[:image], status: 'running', host_port: 3001)
      get "/apps/installed_apps"
      expect(Nokogiri::HTML(response.body).at_css('#app-storage-store').text.squish).to include('Its data needs a ZFS pool now, and it has none')

      File.write(storage, { 'store' => 'tank' }.to_json)
      get "/apps/installed_apps"
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#app-storage-store').text.squish).to eq('Its data is on the ZFS pool tank')
      expect(page.at_css('#docker_app_store button[data-app-shares]')['data-storage-pool']).to eq('tank')
      get "/apps/docker_apps"
      expect(response.body).to include("Its data stays on the ZFS pool tank, and its settings in #{AppCatalog.apps_root}/store: both are used again")
    end
  end

  describe "installing" do
    it "installs through the helper, streaming its progress, and says where to open the app" do
      get "/apps/docker/install_stream/uptimekuma", headers: same_origin.merge('Host' => '192.168.1.111')
      expect(Privileged.calls).to include(['apps.install', { app: 'uptimekuma', shares: [] }])
      expect(response.body).to include('✓ Uptime Kuma is installed and running')
      expect(response.body).to include('Open it at http://192.168.1.111:3001/ (on your LAN or Tailscale)')
      expect(response.body).to include('First sign-in: Its first page asks you to make the admin account.')
      expect(response.body).not_to include('Passwords and keys') # Amahi-kai made none for it
      expect(DockerApp.find_by(identifier: 'uptimekuma')).to have_attributes(status: 'running', host_port: 3001,
                                                                             container_name: 'amahi-uptimekuma')
    end

    it "says where the password it made is, after how to sign in" do
      get "/apps/docker/install_stream/transmission", headers: same_origin
      expect(response.body).to include('First sign-in: Sign in as admin with the password Amahi-kai made for it.')
      expect(response.body).to include('Passwords and keys Amahi-kai made for it are on the Apps page, under Transmission')
    end

    it "keeps the ports the helper gave when the catalog's were taken" do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.install', app: 'gitea', shares: []).and_return(
        'ok' => true, 'ports' => [{ 'preferred' => 3300, 'host' => 3302, 'container' => 3000, 'protocol' => 'tcp' },
                                  { 'preferred' => 2222, 'host' => 2222, 'container' => 2222, 'protocol' => 'tcp' }]
      )
      get "/apps/docker/install_stream/gitea", headers: same_origin.merge('Host' => '192.168.1.111')
      expect(response.body).to include('Open it at http://192.168.1.111:3302/')
      app = DockerApp.find_by(identifier: 'gitea')
      expect(app.host_port).to eq(3302)
      expect(app.port_summary).to eq('3302 (web) · 2222 (Git over SSH)')
    end

    it "records and shows the helper's reason when it fails" do
      helper_fails('apps.install', 'docker exited 1: pull access denied')
      get "/apps/docker/install_stream/uptimekuma", headers: same_origin
      expect(response.body).to include('✗ docker exited 1: pull access denied')
      expect(DockerApp.find_by(identifier: 'uptimekuma')).to have_attributes(status: 'error', error_message: 'docker exited 1: pull access denied')
    end

    describe "with shares" do
      before do
        create(:share, name: 'Movies', disk_pool_copies: 2)
        create(:share, name: 'Downloads')
      end

      it "gives the app the shares chosen, read only unless it writes shares and the share isn't pooled" do
        get "/apps/docker/install_stream/transmission",
            params: { share: %w[Movies Downloads Nope], write: %w[Movies Downloads] }, headers: same_origin
        shares = [{ name: 'Downloads', write: true }, { name: 'Movies', write: false }]
        expect(Privileged.calls).to include(['apps.install', { app: 'transmission', shares: shares }])
        expect(DockerApp.find_by(identifier: 'transmission').shares).to eq(shares)
      end

      # The new shares were saved before the helper ran: a failed reinstall left the record saying
      # shares the container didn't have.
      it "saves the shares chosen only once the helper has given them" do
        app = DockerApp.create!(identifier: 'transmission', name: 'Transmission', image: AppCatalog.find('transmission')[:image], status: 'running')
        app.update!(shares: [{ name: 'Movies', write: false }])
        helper_fails('apps.install', 'docker exited 125: invalid mount')
        get "/apps/docker/install_stream/transmission", params: { share: %w[Downloads] }, headers: same_origin
        expect(app.reload).to have_attributes(status: 'error', shares: [{ name: 'Movies', write: false }])
      end

      it "keeps every share read only for an app that only reads them" do
        get "/apps/docker/install_stream/jellyfin", params: { share: %w[Downloads], write: %w[Downloads] }, headers: same_origin
        expect(Privileged.calls).to include(['apps.install', { app: 'jellyfin', shares: [{ name: 'Downloads', write: false }] }])
      end

      it "gives the app folders of a share, each read only unless it writes shares there" do
        get "/apps/docker/install_stream/transmission",
            params: { share: %w[Movies/Kids Downloads/tv/new Downloads/music/], write: %w[Downloads/tv/new Movies/Kids] }, headers: same_origin
        shares = [{ name: 'Downloads', folder: 'music', write: false }, { name: 'Downloads', folder: 'tv/new', write: true },
                  { name: 'Movies', folder: 'Kids', write: false }]
        expect(Privileged.calls).to include(['apps.install', { app: 'transmission', shares: shares }])
        expect(DockerApp.find_by(identifier: 'transmission').shares).to eq(shares)
      end

      it "names an app's folders on its row, and says which aren't there any more" do
        root = Dir.mktmpdir
        FileUtils.mkdir_p("#{root}/tv/new")
        Share.find_by(name: 'Downloads').update_column(:path, root)
        gitea(identifier: 'transmission', name: 'Transmission', status: 'stopped',
              volume_mappings: [{ name: 'Downloads', folder: 'tv/new', write: true }, { name: 'Downloads', folder: 'music' }].to_json)
        get "/apps/installed_apps"
        expect(response.body).to include('Shares Downloads/music (read only) · Downloads/tv/new (read and write)')
        expect(Nokogiri::HTML(response.body).at_css('#app-missing-folders-transmission').text.squish).to eq(
          "Downloads/music isn't there any more (renamed, moved or deleted): Transmission can't start until Change gives it its folders again."
        )
        expect(CGI.unescapeHTML(response.body)).to include(%(data-current="[{"name":"Downloads","folder":"tv/new","write":true},{"name":"Downloads","folder":"music","write":false}]"))
      ensure
        FileUtils.rm_rf(root) if root
      end

      it "lists the shares in the dialog, pooled ones marked, and shows an installed app's shares with Change" do
        gitea(identifier: 'transmission', name: 'Transmission', status: 'stopped',
              volume_mappings: [{ name: 'Downloads', write: true }, { name: 'Movies', write: false }].to_json)
        get "/apps/installed_apps"
        expect(response.body).to include('data-share="Movies" data-pooled="true"', 'data-share="Downloads" data-pooled="false"')
        expect(response.body).to include('Shares Movies (read only) · Downloads (read and write)')
        expect(CGI.unescapeHTML(response.body)).to include(%(data-current="[{"name":"Downloads","write":true},{"name":"Movies","write":false}]"))
        expect(response.body).to include('data-verb="Save and restart"', 'id="app-install-modal"')
      end
    end

    # The share dialog's folder browser (apps.js): a share's folders, one level at a time.
    describe "a share's folders" do
      let(:root) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(%W[#{root}/vault/media/Pictures #{root}/vault/media/Movies #{root}/vault/.recycle #{root}/elsewhere])
        File.write("#{root}/vault/notes.txt", 'x')
        File.symlink("#{root}/elsewhere", "#{root}/vault/linked")
        create(:share, name: 'Vault', path: "#{root}/vault")
      end

      after { FileUtils.rm_rf(root) }

      it "lists a share's folders, not its files, links or hidden folders" do
        get '/apps/share_folders', params: { share: 'vault' }
        expect(response.parsed_body).to eq('share' => 'Vault', 'path' => '', 'folders' => ['media'])
        get '/apps/share_folders', params: { share: 'Vault', path: 'media/' }
        expect(response.parsed_body).to eq('share' => 'Vault', 'path' => 'media', 'folders' => %w[Movies Pictures])
      end

      it "refuses a folder outside the share, one reached through a link or not there, and a share that isn't" do
        ['../elsewhere', 'media/../..', 'linked', 'nope', 'notes.txt'].each do |path|
          get '/apps/share_folders', params: { share: 'Vault', path: path }
          expect(response).to have_http_status(:unprocessable_content), path
          expect(response.parsed_body.keys).to eq(['error'])
        end
        get '/apps/share_folders', params: { share: 'Photos' }
        expect(response).to have_http_status(:not_found)
      end

      it 'is for admins only' do
        login_as(create(:user))
        get '/apps/share_folders', params: { share: 'Vault' }
        expect(response.body).not_to include('media')
      end
    end

    it "refuses an app that isn't in the catalog" do
      get "/apps/docker/install_stream/portainer", headers: same_origin
      expect(response.body).to include("That app isn't in the catalog")
      expect(Privileged.calls.map(&:first)).not_to include('apps.install')
    end
  end

  describe "start, stop and restart" do
    it "answers with the helper's reason, or that the app isn't installed" do
      gitea
      helper_fails('apps.stop', 'docker exited 1: is the docker daemon running?')
      post "/apps/docker/stop/gitea"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['message']).to eq('docker exited 1: is the docker daemon running?')
      post "/apps/docker/start/jellyfin"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['message']).to eq("That app isn't installed")
    end
  end

  # P4.5: Update when the catalog has another version, Undo update while the copy is kept.
  describe "updates" do
    let(:old) { "gitea/gitea:1.27.2-rootless@sha256:#{'b' * 64}" }
    let(:catalog) { AppCatalog.find('gitea')[:image] }

    def helper_replies(operation, reply)
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with(operation, app: 'gitea', shares: []).and_return({ 'ok' => true }.merge(reply))
    end

    it "offers Update to the catalog's version, with its release notes, only when the app runs another" do
      gitea(image: old)
      get "/apps/installed_apps"
      expect(response.body).to include('Version 1.27.2-rootless', 'Update to 1.27.3-rootless',
                                       'data-url="/apps/docker/update_stream/gitea"',
                                       'href="https://github.com/go-gitea/gitea/releases/tag/v1.27.3"')
      DockerApp.find_by(identifier: 'gitea').update!(image: catalog)
      get "/apps/installed_apps"
      expect(response.body).to include('Version 1.27.3-rootless')
      expect(response.body).not_to include('Update to')
    end

    it "counts the updates on the dashboard" do
      gitea(image: old, show_in_dashboard: true)
      get "/"
      expect(response.body).to include('1 update')
    end

    it "updates through the helper, with the app's shares, and records the new version" do
      gitea(image: old, volume_mappings: [].to_json)
      helper_replies('apps.update', 'updated' => true, 'image' => catalog, 'from' => old)
      get "/apps/docker/update_stream/gitea", headers: same_origin
      expect(response.body).to include('✓ Gitea is updated to 1.27.3-rootless and running', 'goes back to 1.27.2-rootless for 30 days')
      expect(DockerApp.find_by(identifier: 'gitea').image).to eq(catalog)
    end

    it "says when the new version didn't come up and the app went back" do
      gitea(image: old)
      helper_replies('apps.update', 'updated' => false, 'image' => old, 'problem' => 'it stopped (exit code 1)')
      get "/apps/docker/update_stream/gitea", headers: same_origin
      expect(response.body).to include("✗ 1.27.3-rootless didn't come up healthy: it stopped (exit code 1)",
                                       'Gitea is back on 1.27.2-rootless', 'data: error')
      expect(DockerApp.find_by(identifier: 'gitea')).to have_attributes(image: old, status: 'running')
    end

    it "shows the helper's reason when it couldn't start the update" do
      gitea(image: old)
      helper_fails('apps.update', "there isn't room to copy gitea's data before updating")
      get "/apps/docker/update_stream/gitea", headers: same_origin
      expect(response.body).to include("✗ there isn't room to copy gitea's data before updating")
    end

    it "offers Undo update while the copy is kept, and undoes through the helper" do
      gitea
      allow(AppCatalog).to receive(:backup).and_return(nil)
      allow(AppCatalog).to receive(:backup).with('gitea').and_return(from: old, taken_at: Time.utc(2026, 10, 5, 12), until: Time.utc(2026, 11, 4, 12))
      get "/apps/installed_apps"
      # The date in the viewer's time zone (time_ago.js), the copy's age in the confirm (no time zone there)
      expect(response.body).to include('Undo update', 'data-url="/apps/docker/undo_update_stream/gitea"',
                                       '(until <time datetime="2026-11-04T12:00:00Z" data-local="month-day">November 4</time>)',
                                       "with its data from #{ApplicationController.helpers.time_ago_in_words(Time.utc(2026, 10, 5, 12))} ago.")
      expect(response.body).not_to include("ZFS pool's own snapshots")
      # Its data on a ZFS pool: the roll-back takes the pool's later snapshots of it with it
      allow(AppCatalog).to receive(:backup).with('gitea').and_return(from: old, taken_at: Time.utc(2026, 10, 5, 12), until: Time.utc(2026, 11, 4, 12), snapshot: true)
      get "/apps/installed_apps"
      expect(response.body).to include("and so are the ZFS pool&#39;s own snapshots of its data taken since")
      helper_replies('apps.undo_update', 'image' => old)
      get "/apps/docker/undo_update_stream/gitea", headers: same_origin
      expect(response.body).to include('✓ Gitea is back on 1.27.2-rootless, with its data from before the update')
      expect(DockerApp.find_by(identifier: 'gitea').image).to eq(old)
    end

    it "keeps the version an app runs when its shares change" do
      gitea(image: old)
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.install', app: 'gitea', shares: []).and_return('ok' => true, 'image' => old)
      get "/apps/docker/install_stream/gitea", headers: same_origin
      expect(DockerApp.find_by(identifier: 'gitea').image).to eq(old)
    end

    it "won't update an app that isn't installed" do
      get "/apps/docker/update_stream/gitea", headers: same_origin
      expect(response.body).to include("That app isn't installed")
      expect(Privileged.calls.map(&:first)).not_to include('apps.update')
    end
  end

  describe "uninstalling" do
    it "keeps the data unless asked to delete it" do
      gitea
      post "/apps/docker/uninstall/gitea"
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(DockerApp.find_by(identifier: 'gitea')).to be_nil
      post "/apps/docker/uninstall/gitea", params: { delete_data: '1' }
      expect(Privileged.calls).to eq([['apps.uninstall', { app: 'gitea', delete_data: false }],
                                      ['apps.uninstall', { app: 'gitea', delete_data: true }]])
    end

    it "refuses an app that isn't installed or in the catalog" do
      post "/apps/docker/uninstall/portainer"
      expect(response).to have_http_status(:not_found)
      expect(Privileged.calls).to be_empty
    end

    # An app the catalog dropped couldn't be uninstalled until System Update.
    it "uninstalls an installed app the catalog dropped" do
      DockerApp.create!(identifier: 'portainer', name: 'Portainer', image: "portainer/portainer-ce:2.0@sha256:#{'a' * 64}", status: 'running')
      post "/apps/docker/uninstall/portainer"
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls).to eq([['apps.uninstall', { app: 'portainer', delete_data: false }]])
    end
  end

  it "no longer proxies apps at /app/<id>" do
    gitea
    get "/app/gitea"
    expect(response).to have_http_status(:not_found)
  end

  describe "the dashboard" do
    it "links each running app to its own port" do
      gitea(show_in_dashboard: true)
      get "/", headers: { 'Host' => '192.168.1.111' }
      expect(response.body).to include('href="http://192.168.1.111:3300/"')
    end

    it "links to the Apps page instead through the Cloudflare Tunnel" do
      gitea(show_in_dashboard: true)
      get "/", headers: { 'Host' => 'nas.example.com', 'CF-Connecting-IP' => '203.0.113.9' }
      expect(response.body).not_to include(':3300/')
      expect(response.body).to include('href="/apps/installed_apps"', 'LAN or Tailscale')
    end
  end

end
