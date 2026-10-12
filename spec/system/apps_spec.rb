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
    let(:tank) { StoragePools::Pool.new(name: 'tank', vdevs: [{ 'name' => 'mirror-0', 'children' => [] }]) }

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

  it 'shows the installed apps page' do
    sign_in_as_admin
    visit '/apps/installed_apps'
    expect(page).to have_css('.kai-mainnav .kai-navlink[aria-current="page"]', text: 'Apps')
  end
end
