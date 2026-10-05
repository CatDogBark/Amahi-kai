require 'rails_helper'

# Disks → ZFS Pools (docs/plans/storage.md), and the share-storage pages leaving pool drives alone.
RSpec.describe 'ZFS pools', type: :request do
  let(:pool) do
    StoragePools::Pool.new(
      name: 'tank', health: 'DEGRADED', used: 500_000_000_000, available: 2_000_000_000_000,
      mountpoint: '/srv/pools/tank', state: 'DEGRADED', status: 'One or more devices could not be used.',
      action: "Replace the device using 'zpool replace'.", scan: 'none requested', errors: 'No known data errors',
      vdevs: [{ 'name' => 'raidz1-0', 'state' => 'DEGRADED', 'children' => [
        { 'name' => '/dev/disk/by-id/ata-Samsung_SSD_870_S1-part1', 'device' => '/dev/sdc1', 'state' => 'ONLINE',
          'read' => '0', 'write' => '0', 'cksum' => '0', 'children' => [] },
        { 'name' => '1234', 'state' => 'UNAVAIL', 'note' => 'was /dev/disk/by-id/ata-Samsung_SSD_870_S2-part1',
          'read' => '0', 'write' => '0', 'cksum' => '0', 'children' => [] }
      ] }]
    )
  end

  def drive(path, role, **extra)
    { path: path, model: 'Samsung SSD 870 EVO 1TB', serial: "S#{path[-1]}", size: 1_000_204_886_016, ssd: true, role: role,
      pool: nil, mounts: [], free: %i[free old_zfs].include?(role) }.merge(extra)
  end

  let(:drives) do
    [drive('/dev/sda', :os, mounts: ['/']), drive('/dev/sdb', :share, mounts: ['/mnt/storage-1']),
     drive('/dev/sdc', :pool, pool: 'tank'), drive('/dev/sdd', :free), drive('/dev/sde', :free), drive('/dev/sdf', :old_zfs, pool: 'old')]
  end

  def stub_pools(installed:, pools: [], drives: self.drives, error: nil)
    allow(StoragePools).to receive(:status).and_return(installed: installed, pools: pools, error: error)
    allow(StoragePools).to receive(:drives).and_return(drives)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  it 'is for admins only' do
    login_as(create(:user))
    get '/disks/pools'
    expect(response).to redirect_to(new_user_session_url)
    post '/disks/create_pool', params: { name: 'tank', layout: 'mirror', devices: %w[/dev/sdd /dev/sde] }, as: :json
    expect(Privileged.calls).to be_empty
  end

  context 'as an admin' do
    before { login_as_admin }

    it 'offers to install ZFS, and lists the drives without a form until it is' do
      stub_pools(installed: false)
      get '/disks/pools'
      expect(response).to have_http_status(:ok)
      expect(page.at_css('#install-zfs-btn')['data-zfs-install']).to eq('/disks/install_zfs_stream')
      expect(page.at_css('#pool-form')).to be_nil
      expect(page.css('#pool-drives tbody tr').size).to eq(6)
      expect(page.css('#pool-drives input')).to be_empty
      expect(page.at_css('#zfs-install-install-modal')).not_to be_nil
      expect(page.at_css('.setup-subtab .active-subtab-link').text.strip).to eq('ZFS Pools')
    end

    it "shows each pool's health, space, notes and drives" do
      stub_pools(installed: true, pools: [pool])
      get '/disks/pools'
      card = page.at_css('#pool-tank')
      expect(card.at_css('.card-header').text).to include('tank', 'RAIDZ1 · 2 drives', 'DEGRADED')
      expect(card.text).to include('466 GB used', '1.82 TB free of 2.27 TB', 'One or more devices could not be used.',
                                   "What to do: Replace the device using 'zpool replace'.", '/srv/pools/tank', 'No scrub has run yet.')
      rows = card.css('tbody tr').map { |tr| tr.css('td').map { |td| td.text.strip } }
      expect(rows).to eq([['/dev/sdc', 'Samsung_SSD_870_S1', 'ONLINE', '0 / 0 / 0'],
                          ['—', 'was /dev/disk/by-id/ata-Samsung_SSD_870_S2-part1', 'UNAVAIL', '0 / 0 / 0']])
    end

    it 'offers only free drives to a new pool, with every layout, and a free name' do
      stub_pools(installed: true, pools: [pool])
      get '/disks/pools'
      form = page.at_css('#pool-form')
      expect(form['action']).to eq('/disks/create_pool')
      expect(form.css('input[name="devices[]"]').map { |i| i['value'] }).to eq(%w[/dev/sdd /dev/sde /dev/sdf])
      expect(form.at_css('input[value="/dev/sdd"]')['data-size']).to eq('1000204886016')
      expect(JSON.parse(form['data-layouts']).map { |l| l['key'] }).to eq(%w[mirror striped_mirrors raidz1 raidz2 raidz3])
      expect(form.css('input[name="layout"]').size).to eq(5)
      expect(form.at_css('#pool-name')['value']).to eq('pool1')
      roles = page.css('#pool-drives tbody tr').to_h { |tr| [tr.css('td')[1].text.strip, tr.css('td')[4].text.strip] }
      expect(roles).to include('/dev/sda' => 'System disk', '/dev/sdb' => 'Share storage (/mnt/storage-1)',
                               '/dev/sdc' => 'ZFS pool tank', '/dev/sdd' => 'Free')
      expect(roles['/dev/sdf']).to include('old ZFS label (pool old')
    end

    it 'says when there are too few free drives' do
      stub_pools(installed: true, drives: [drive('/dev/sda', :os), drive('/dev/sdd', :free)])
      get '/disks/pools'
      expect(page.at_css('#pool-form')).to be_nil
      expect(response.body).to include('A pool needs at least 2 free drives')
    end

    it "shows why the pools couldn't be read" do
      stub_pools(installed: true, error: 'The ZFS modules are not loaded.')
      get '/disks/pools'
      expect(page.at_css('.alert-warning').text.strip).to eq("Couldn't read the pools: The ZFS modules are not loaded.")
    end

    it 'creates a pool through the helper' do
      post '/disks/create_pool', params: { name: 'tank', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde] }, as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls).to eq([['pools.create', { name: 'tank', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde] }]])
    end

    it "passes on the helper's refusal" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('pools.create', '/dev/sdb is mounted at /mnt/storage-1; unmount it first', refused: true))
      post '/disks/create_pool', params: { name: 'tank', layout: 'mirror', devices: %w[/dev/sdb /dev/sdd] }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('status' => 'error', 'error' => '/dev/sdb is mounted at /mnt/storage-1; unmount it first')
    end

    it 'installs ZFS and sets it up, streaming the progress' do
      get '/disks/install_zfs_stream', headers: same_origin
      expect(response.body).to include('data: Installing ZFS (zfsutils-linux)...', 'data: ✓ ZFS installed', "event: done\ndata: success")
      expect(Privileged.calls).to eq([['packages.install', { packages: ['zfsutils-linux'] }], ['zfs.setup', {}]])
    end

    it 'ends the install stream with an error when the install fails' do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.install', 'apt-get exited 100'))
      get '/disks/install_zfs_stream', headers: same_origin
      expect(response.body).to include('data: ✗ apt-get exited 100', "event: done\ndata: error")
    end

    it 'marks pool drives on the Devices page, without the format and mount buttons' do
      allow(DiskManager).to receive(:devices).and_return([
        { name: 'sdc', path: '/dev/sdc', model: 'SSD', size: '931.5G', os_disk: false, zfs_pool: 'tank',
          partitions: [{ name: 'sdc1', path: '/dev/sdc1', size: '931.5G', fstype: 'zfs_member', status: :unmounted }] },
        { name: 'sdd', path: '/dev/sdd', model: 'SSD', size: '931.5G', os_disk: false, zfs_pool: nil,
          partitions: [{ name: 'sdd', path: '/dev/sdd', size: '931.5G', fstype: nil, status: :unformatted }] }
      ])
      get '/disks/devices'
      cards = page.css('#disks-table .card')
      expect(cards[0].text).to include('ZFS pool tank')
      expect(cards[0].css('form')).to be_empty
      expect(cards[1].css('form').size).to eq(1) # Initialize
    end
  end
end
