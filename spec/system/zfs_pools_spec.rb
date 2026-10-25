require 'rails_helper'

# Disks → ZFS Pools in a real browser: the buttons and dialogs storage_pools.js runs. The pools
# and drives are stubbed (StoragePools), and change as the stubbed helper is asked, so each
# action's page reload shows it done.
RSpec.describe 'ZFS pools', type: :system do
  # Each drive goes by its ref, its /dev/disk/by-id link (DiskManager.by_id_refs)
  def drive(path, role, **extra)
    { path: path, ref: "/dev/disk/by-id/ata-SSD_#{path[-1]}", model: 'SSD', serial: "S#{path[-1]}", size: 1_000_204_886_016,
      ssd: true, role: role, pool: nil, mounts: [], contents: [], free: role == :free }.merge(extra)
  end

  let(:found) { [StoragePools::FoundPool.new(name: 'old', id: '5678', state: 'ONLINE', devices: ['/dev/sdg1'], foreign: true)] }
  let(:drives) { [drive('/dev/sdd', :free), drive('/dev/sde', :free), drive('/dev/sdg', :found, pool: 'old')] }

  before do
    allow(StoragePools).to receive(:zfs_installed?).and_return(true)
    allow(StoragePools).to receive(:smart_installed?).and_return(true)
    allow(StoragePools).to receive(:status) { { installed: true, pools: [], offline: [], found: found, error: nil } }
    allow(StoragePools).to receive(:drives) { drives }
    allow(DiskManager).to receive(:resolve) { |ref| ref.sub(%r{\A/dev/disk/by-id/ata-SSD_}, '/dev/sd') }
    allow(StoragePools).to receive(:import_found!).and_wrap_original { |original, id| original.call(id).tap { found.clear } }
    allow(StoragePools).to receive(:erase_drive!).and_wrap_original do |original, device, **options|
      original.call(device, **options).tap { drives.reject! { |d| d[:path] == '/dev/sdg' } }
    end
    allow(StoragePools).to receive(:create!).and_wrap_original do |original, **options|
      original.call(**options).tap { drives.each { |d| d.merge!(role: :pool, pool: 'pool1', free: false) if d[:free] } }
    end
    sign_in_as_admin
  end

  it 'imports a pool found on the drives by its id' do
    visit '/disks/pools'
    within('#found-5678') do
      expect(page).to have_text('On the drives, not imported')
      expect(page).to have_text('last used by another system')
      message = accept_confirm { click_button 'Import' }
      expect(message).to include('Import the pool old from /dev/sdg?')
    end
    expect(page).to have_no_css('#found-5678')
    expect(Privileged.calls).to include(['pools.import_found', { id: '5678' }])
  end

  it "erases a found pool's drive only once the pool's name is typed" do
    visit '/disks/pools'
    find('#erase-sdg').click
    within('#erase-dialog') do
      expect(page).to have_text('Erase /dev/sdg')
      expect(page).to have_button('Erase', disabled: true)
      fill_in 'erase-confirm', with: 'ol'
      expect(page).to have_button('Erase', disabled: true)
      fill_in 'erase-confirm', with: 'old'
      click_button 'Erase'
    end
    expect(page).to have_no_css('#erase-sdg')
    expect(Privileged.calls).to include(['pools.erase_drive', { device: '/dev/sdg', confirm: 'old' }])
  end

  it 'creates a pool on the drives ticked, naming them by their kernel names, and sends their refs' do
    visit '/disks/pools'
    check 'pool-drive-sdd'
    check 'pool-drive-sde'
    choose 'layout-mirror'
    check 'pool-erase'
    message = accept_confirm { click_button 'Create pool' }
    expect(message).to include('pool "pool1" on /dev/sdd, /dev/sde?')
    expect(page).to have_no_css('#pool-form')
    expect(Privileged.calls).to include(['pools.create', { name: 'pool1', layout: 'mirror', devices: %w[/dev/sdd /dev/sde] }])
  end
end
