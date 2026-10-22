require 'rails_helper'

# The first-run setup wizard in a real browser, every step in order, as a fresh install shows
# it: Greyhole not installed yet. The drives and the system's commands are stubbed; the
# install windows stream the development stand-ins (SetupService).
RSpec.describe 'Setup wizard', type: :system do
  let(:devices) do
    [
      { name: 'sda', path: '/dev/sda', model: 'OS DISK', size: '40G', os_disk: true, zfs_pool: nil,
        partitions: [{ name: 'sda1', path: '/dev/sda1', size: '40G', fstype: 'ext4', mountpoint: '/', status: :mounted }] },
      { name: 'sdb', path: '/dev/sdb', model: 'Blank SSD', size: '500G', os_disk: false, zfs_pool: nil,
        partitions: [{ name: 'sdb', path: '/dev/sdb', size: '500G', fstype: nil, mountpoint: nil, status: :unformatted }] },
      { name: 'sdd', path: '/dev/sdd', model: 'NTFS USB', size: '2T', os_disk: false, zfs_pool: nil,
        partitions: [{ name: 'sdd1', path: '/dev/sdd1', size: '2T', fstype: 'ntfs', mountpoint: nil, status: :unmounted }] },
      { name: 'sde', path: '/dev/sde', model: 'ZFS member', size: '1T', os_disk: false, zfs_pool: 'tank',
        partitions: [{ name: 'sde1', path: '/dev/sde1', size: '1T', fstype: 'zfs_member', mountpoint: nil, status: :unmounted }] }
    ]
  end

  before do
    mounts = %w[/mnt/storage-1 /mnt/storage-2]
    allow(DiskManager).to receive(:devices).and_return(devices)
    allow(DiskManager).to receive(:format_disk!)
    allow(DiskManager).to receive(:mount!) { mounts.shift }
    allow(SambaService).to receive(:push_config)
    allow(Greyhole).to receive(:installed?).and_return(false)
  end

  # The install and preview windows cover the page, not only the wizard's panel (a blur on the
  # panel itself used to make it their frame).
  def window_width(id)
    page.evaluate_script("document.getElementById('#{id}').getBoundingClientRect().width")
  end

  it 'walks from the first sign-in to the dashboard' do
    Setting.set('setup_completed', 'false')
    visit '/login'
    fill_in 'username', with: User::SEED_ADMIN_LOGIN
    fill_in 'password', with: User::SEED_ADMIN_PASSWORD
    click_button I18n.t('log_in')

    expect(page).to have_current_path('/setup/welcome')
    expect(page).to have_css('.setup-stepcount', text: /step 1 of 7/i)
    click_link "Let's get started"

    # A refused password shows here, and not again on the next page
    fill_in 'password', with: 'abcdefgh1'
    fill_in 'password_confirmation', with: 'abcdefgh2'
    click_button 'Save & continue →'
    expect(page).to have_css('.amahi-toast', text: 'Passwords do not match')
    fill_in 'password', with: 'abcdefgh1'
    fill_in 'password_confirmation', with: 'abcdefgh1'
    click_button 'Save & continue →'

    expect(page).to have_current_path('/setup/network')
    expect(page).to have_css('.setup-stepcount', text: /step 3 of 7/i)
    expect(page).to have_no_css('.amahi-toast', text: 'Passwords do not match')
    fill_in 'server_name', with: 'Test NAS'
    click_button 'Save & continue →'

    # Drives: neither the system's disk nor a ZFS pool's is offered
    expect(page).to have_current_path('/setup/storage')
    expect(all('input[name="drives[]"]', visible: :all).map(&:value)).to contain_exactly('/dev/sdb', '/dev/sdd1')
    check 'drive__dev_sdb'
    check 'drive__dev_sdd1'
    click_button 'Prepare drives & continue →'
    within('#prepare-drives-install-modal') { expect(page).to have_link('Continue →', wait: 15) }
    expect(window_width('prepare-drives-install-modal')).to be > 1000
    click_link 'Continue →'

    # Greyhole: installed from here, and its copies kept once it is
    expect(page).to have_current_path('/setup/greyhole')
    expect(page).to have_button('Install Greyhole →')
    click_button 'Install Greyhole →'
    within('#greyhole-install-install-modal') { expect(page).to have_link('Continue →', wait: 15) }
    expect(window_width('greyhole-install-install-modal')).to be > 1000
    expect(Setting.get('default_pool_copies')).to eq('1') # one pool drive: one copy
    allow(Greyhole).to receive(:installed?).and_return(true)
    click_link 'Continue →'

    expect(page).to have_current_path('/setup/share')
    fill_in 'share_name', with: 'Media'
    click_button 'Create & continue →'

    expect(page).to have_current_path('/setup/complete')
    expect(page).to have_css('.summary-item', text: 'First share: Media')
    expect(page).to have_css('.summary-item', text: 'Greyhole pool: 1 drive')
    expect(page).to have_css('.summary-item', text: 'Drive shared as it is: storage-2 (/mnt/storage-2)')
    expect(Share.find_by(name: 'Media')).to have_attributes(disk_pool_copies: 1, path: Share.default_full_path('Media'))
    expect(DiskPoolPartition.pluck(:path)).to eq(['/mnt/storage-1'])

    click_button 'Go to the dashboard →'
    expect(page).to have_css('.kai-mainnav')
    expect(Setting.get('setup_completed')).to eq('true')
  end
end
