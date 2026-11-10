require 'rails_helper'

# Apps in a real browser: without Docker (as outside production), the Install Docker window
# streams the simulated install and finishes; the installed apps page loads clean.
RSpec.describe 'Apps', type: :system do
  it 'offers to install Docker, and its window streams to the end' do
    sign_in_as_admin
    visit '/apps'
    expect(page).to have_text('Docker is not installed')
    click_button 'Install Docker'
    within('#docker-install-modal') do
      expect(page).to have_css('#docker-output', text: 'Installing Docker Engine')
      expect(page).to have_css('#docker-status', text: '✓ Done', wait: 30) # the simulated install takes a few seconds
      expect(page).to have_button('Close & Refresh')
    end
  end

  # P4.6: an app that keeps data on a ZFS pool asks for the pool before it installs.
  describe 'storage on a ZFS pool' do
    let(:fetched) { Rails.root.join('tmp', 'catalog', 'apps').to_s }
    let(:tank) { StoragePools::Pool.new(name: 'tank', managed: true, vdevs: [{ 'name' => 'mirror-0', 'children' => [] }]) }

    before do
      FileUtils.rm_rf(File.dirname(fetched))
      FileUtils.mkdir_p(fetched)
      File.write("#{fetched}/store.yml", File.read(File.join(AppCatalog::CATALOG_DIR, 'uptimekuma.yml'))
                                            .sub(/^name: .*$/, 'name: Store')
                                            .sub('  - { name: data, path: /app/data }', '  - { name: data, path: /app/data, kind: dataset }'))
      AppCatalog.reload!
      allow(DockerService).to receive(:installed?).and_return(true)
      allow(DockerService).to receive(:running?).and_return(true)
      allow(StoragePools).to receive(:zfs_installed?).and_return(true)
    end

    after do
      FileUtils.rm_rf(File.dirname(fetched))
      AppCatalog.reload!
    end

    it 'installs on the pool chosen' do
      allow(StoragePools).to receive(:status).and_return(installed: true, offline: [], error: nil, pools: [tank])
      sign_in_as_admin
      visit '/apps'
      within('#docker_app_store') { click_button 'Install' }
      within('#app-shares-dialog') do
        # Store doesn't work with shares: the dialog is for its pool only
        expect(page).to have_css('#app-shares-title', text: 'Storage for Store')
        expect(page).to have_css('[data-role="shares-part"]', visible: :hidden)
        expect(page).to have_text('Store keeps its data on a ZFS pool')
        expect(page).to have_select('app-storage-pool', selected: 'ZFS pool tank (Mirror)')
        expect(page).to have_no_text("there isn't one yet")
        click_button 'Install'
      end
      within('#app-install-modal') { expect(page).to have_text('Store is installed and running', wait: 15) }
      expect(Privileged.calls).to include(['apps.install', { app: 'store', shares: [], pool: 'tank' }])
    end

    it "can't install before there's a pool" do
      allow(StoragePools).to receive(:status).and_return(installed: true, offline: [], error: nil, pools: [])
      sign_in_as_admin
      visit '/apps'
      within('#docker_app_store') { click_button 'Install' }
      within('#app-shares-dialog') do
        expect(page).to have_text("Store keeps its data on a ZFS pool, and there isn't one yet")
        expect(page).to have_button('Install', disabled: true)
      end
    end
  end

  # Change ticks the shares an installed app was given. A name recorded in other capitals (the share
  # deleted and made again as "vault") still counts, as it does for the helper and for the share's
  # delete check, which both ignore case.
  describe "an installed app's shares" do
    before do
      allow(DockerService).to receive_messages(installed?: true, running?: true)
      create(:share, name: 'Vault')
      create(:share, name: 'Movies')
    end

    def open_change(app)
      sign_in_as_admin
      visit "/apps/#{app.identifier}"
      find("[data-app-shares='#{app.identifier}'][data-verb='Save and restart']").click
    end

    it 'ticks the shares it was given' do
      app = create(:docker_app, identifier: 'uptimekuma', name: 'Uptime Kuma', status: 'running')
      app.update!(shares: [{ name: 'Vault', write: false }])
      open_change(app)
      within('#app-shares-dialog') do
        expect(find('tr[data-share="Vault"] [data-role="give"]')).to be_checked
        expect(find('tr[data-share="Movies"] [data-role="give"]')).not_to be_checked
      end
    end

    it 'ticks a share recorded in other capitals' do
      app = create(:docker_app, identifier: 'uptimekuma', name: 'Uptime Kuma', status: 'running')
      app.update!(shares: [{ name: 'vault', write: false }])
      open_change(app)
      within('#app-shares-dialog') { expect(find('tr[data-share="Vault"] [data-role="give"]')).to be_checked }
    end
  end

  # Only some folders of a share, picked in the dialog's folder browser one level at a time.
  describe 'folders of a share' do
    let(:root) { Dir.mktmpdir }

    before do
      allow(DockerService).to receive_messages(installed?: true, running?: true)
      FileUtils.mkdir_p(%W[#{root}/vault/media/Pictures #{root}/vault/media/Movies])
      create(:share, name: 'Vault', path: "#{root}/vault")
    end

    after { FileUtils.rm_rf(root) }

    def open_change(app)
      sign_in_as_admin
      visit "/apps/#{app.identifier}"
      find("[data-app-shares='#{app.identifier}'][data-verb='Save and restart']").click
    end

    it 'gives an app a folder chosen in the browser, read only or read and write' do
      app = create(:docker_app, identifier: 'transmission', name: 'Transmission', status: 'running')
      app.update!(shares: [{ name: 'Vault', write: false }])
      open_change(app)
      within('#app-shares-dialog tr[data-share-folders="Vault"]') do
        choose 'Only some folders'
        click_button '📁 media'
        expect(page).to have_button('📁 Movies')
        click_button '📁 Pictures'
        expect(page).to have_text('No folders in here.')
        click_button 'Choose media/Pictures'
        find('[data-folder="media/Pictures"] select').select('Read and write')
        click_button '+ Add a folder'
        click_button '📁 media'
        click_button 'Choose media'
        expect(page).to have_text('media/Pictures, chosen already, is inside media: remove it first')
        click_button 'Cancel'
      end
      within('#app-shares-dialog') { click_button 'Save and restart' }
      within('#app-install-modal') { expect(page).to have_text('Transmission is installed and running', wait: 15) }
      expect(Privileged.calls).to include(['apps.install', { app: 'transmission', shares: [{ name: 'Vault', folder: 'media/Pictures', write: true }] }])
    end

    it 'shows the folders an app was given, and asks for one before giving only some' do
      app = create(:docker_app, identifier: 'jellyfin', name: 'Jellyfin', status: 'running')
      app.update!(shares: [{ name: 'Vault', folder: 'media/Movies', write: false }])
      open_change(app)
      within('#app-shares-dialog') do
        within('tr[data-share-folders="Vault"]') do
          expect(page).to have_checked_field('Only some folders')
          expect(page).to have_css('[data-folder="media/Movies"]')
          expect(page).to have_no_css('[data-folder] select') # Jellyfin only reads shares
          find('[data-folder="media/Movies"] [data-role="remove-folder"]').click
        end
        click_button 'Save and restart'
        expect(page).to have_text('Choose a folder, or All of Vault')
        choose 'All of Vault'
        click_button 'Save and restart'
      end
      within('#app-install-modal') { expect(page).to have_text('Jellyfin is installed and running', wait: 15) }
      expect(Privileged.calls).to include(['apps.install', { app: 'jellyfin', shares: [{ name: 'Vault', write: false }] }])
    end
  end

  # Install asks which shares to give an app only when it works with files in shares (the
  # catalog's shares, or writes_shares): Vaultwarden and Uptime Kuma install without asking
  describe 'apps that work with shares, and the others' do
    before do
      allow(DockerService).to receive(:installed?).and_return(true)
      allow(DockerService).to receive(:running?).and_return(true)
    end

    it 'installs an app that does not work with shares without asking' do
      sign_in_as_admin
      visit '/apps'
      within('#docker_app_uptimekuma') { click_button 'Install' }
      within('#app-install-modal') { expect(page).to have_text('Uptime Kuma is installed and running', wait: 15) }
      expect(page).to have_no_css('#app-shares-dialog.show')
      expect(Privileged.calls).to include(['apps.install', { app: 'uptimekuma', shares: [] }])
    end

    it 'asks which shares to give an app that works with them' do
      sign_in_as_admin
      visit '/apps'
      within('#docker_app_jellyfin') { click_button 'Install' }
      within('#app-shares-dialog') do
        expect(page).to have_css('#app-shares-title', text: 'Shares for Jellyfin')
        expect(page).to have_css('[data-role="shares-part"]', visible: :visible)
      end
    end
  end

  # Manage opens an app's own page, where a password Amahi-kai made stays hidden until Show
  it "opens an installed app's page from Manage, and shows its password only on Show" do
    allow(DockerService).to receive_messages(installed?: true, running?: true)
    create(:docker_app, identifier: 'transmission', name: 'Transmission', status: 'running')
    allow(AppCatalog).to receive(:secrets).and_call_original
    allow(AppCatalog).to receive(:secrets).with('transmission').and_return([{ label: 'Sign in as admin with this password', value: 'Gener4ted' }])
    sign_in_as_admin
    visit '/apps/installed_apps' # the old Installed tab's page: the Apps page now
    expect(page).to have_css('.kai-mainnav .kai-navlink[aria-current="page"]', text: 'Apps')
    within('#docker_app_transmission') do
      expect(page).to have_css('.kai-pill', text: 'Running')
      click_link 'Manage'
    end
    expect(page).to have_current_path('/apps/transmission')
    within('.kai-secret') do
      expect(page).to have_no_text('Gener4ted')
      click_button 'Show'
      expect(page).to have_css('code', text: 'Gener4ted')
      click_button 'Hide'
      expect(page).to have_no_text('Gener4ted')
    end
    click_link 'All apps'
    expect(page).to have_current_path('/apps')
  end

  # P4.9: a newer version the update check found, offered on the app's page and on the dashboard,
  # with its logo from the NAS (P4.10)
  it "offers a newer version the update check found, with a word on a new major version" do
    allow(DockerService).to receive_messages(installed?: true, running?: true)
    create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'running', image: AppCatalog.find('gitea')[:image],
                        show_in_dashboard: true, newer_tag: '28.3.0-rootless', newer_image: "gitea/gitea:28.3.0-rootless@sha256:#{'9' * 64}",
                        newer_kind: 'newer', newer_major: true, newer_notes: 'https://github.com/go-gitea/gitea/releases/tag/v28.3.0',
                        versions_checked_at: 1.hour.ago)
    sign_in_as_admin
    expect(page).to have_css('.update-notice', text: 'Gitea 1.27.3-rootless → 28.3.0-rootless (a new major version)')
    visit '/apps'
    within('#docker_app_gitea') do
      expect(page).to have_css('.kai-pill', text: 'Update ready')
      expect(page).to have_css("img.kai-app-logo[src^='/apps/logos/gitea?v=']")
      click_link 'Manage'
    end
    within('#app-version-gitea') do
      expect(page).to have_button('Update to 28.3.0-rootless')
      expect(page).to have_link("What's new", href: 'https://github.com/go-gitea/gitea/releases/tag/v28.3.0')
      expect(page).to have_text("A new major version: read what's new before you update.")
    end
    expect(page).to have_css('#app-checked-gitea', text: 'About 1 hour ago')
    expect(page.evaluate_script("document.querySelector('#docker_app_gitea img.kai-app-logo').naturalWidth")).to be > 0 # the NAS served it
  end

  # The app's card: Update beside Manage runs the update in the install window, after asking;
  # a new major version is Review update, to the app's page
  it "updates from the app's card, and sends a new major version to the app's page" do
    allow(DockerService).to receive_messages(installed?: true, running?: true)
    current = AppCatalog.find('gitea')[:image]
    newer = "gitea/gitea:1.27.9-rootless@sha256:#{'9' * 64}"
    create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'running', image: current, newer_tag: '1.27.9-rootless', newer_image: newer,
                        newer_kind: 'newer', newer_major: false, versions_checked_at: 1.hour.ago)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with('apps.update', hash_including(app: 'gitea', tag: '1.27.9-rootless'))
                                       .and_return('ok' => true, 'updated' => true, 'image' => newer, 'from' => current)
    sign_in_as_admin
    visit '/apps'
    within('#docker_app_gitea') do
      accept_confirm(/Update Gitea to 1\.27\.9-rootless\?/) { click_button 'Update' }
    end
    within('#app-install-modal') do
      expect(page).to have_text('Updating Gitea...')
      expect(page).to have_text('✓ Gitea is updated to 1.27.9-rootless and running', wait: 15)
    end

    DockerApp.find_by(identifier: 'gitea').update!(image: current, newer_tag: '28.3.0-rootless', newer_major: true,
                                                   newer_image: "gitea/gitea:28.3.0-rootless@sha256:#{'8' * 64}")
    visit '/apps'
    within('#docker_app_gitea') { click_link 'Review update' }
    expect(page).to have_current_path('/apps/gitea')
    expect(page).to have_css('#app-major-gitea', text: 'A new major version')
  end
end
