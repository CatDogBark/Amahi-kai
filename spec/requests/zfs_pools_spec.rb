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

  it "keeps the dashboard's alerts from users who aren't admins" do
    allow(StorageHealth).to receive(:load).and_return(StorageHealth.new('pools' => [{ 'name' => 'tank', 'health' => 'FAULTED', 'vdevs' => [] }]))
    ensure_setup_completed!
    login_as(create(:user))
    get '/'
    expect(response).to have_http_status(:ok)
    expect(page.css('.storage-alerts')).to be_empty
  end

  context 'as an admin' do
    before { login_as_admin }

    it 'offers to install ZFS, and lists the drives without a form until it is' do
      stub_pools(installed: false)
      get '/disks/pools'
      expect(response).to have_http_status(:ok)
      expect(page.at_css('#install-zfs-btn')['data-storage-install']).to eq('/disks/install_storage_tools_stream')
      expect(page.at_css('#pool-form')).to be_nil
      expect(page.css('#pool-drives tbody tr').size).to eq(6)
      expect(page.css('#pool-drives input')).to be_empty
      expect(page.at_css('#storage-install-install-modal')).not_to be_nil
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
      expect(rows).to eq([['/dev/sdc', 'Samsung_SSD_870_S1', 'ONLINE', 'Not checked yet', '0 / 0 / 0', 'Replace'],
                          ['—', 'was /dev/disk/by-id/ata-Samsung_SSD_870_S2-part1', 'UNAVAIL', '—', '0 / 0 / 0', 'Replace']])
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

    it 'creates a pool through the helper, then checks the health' do
      post '/disks/create_pool', params: { name: 'tank', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde] }, as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls).to eq([['pools.create', { name: 'tank', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde] }],
                                      ['storage.check_health', {}]])
    end

    it 'replaces a drive, adds drives and deletes a pool through the helper' do
      post '/disks/replace_pool_drive', params: { name: 'tank', old: '1234', new: '/dev/sdd' }, as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      post '/disks/add_pool_group', params: { name: 'tank', devices: %w[/dev/sdd /dev/sde] }, as: :json
      post '/disks/destroy_pool', params: { name: 'tank', confirm: 'tank' }, as: :json
      expect(Privileged.calls.map(&:first) - ['storage.check_health']).to eq(%w[pools.replace pools.add_group pools.destroy])
      expect(Privileged.calls).to include(['pools.destroy', { name: 'tank', confirm: 'tank' }])
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('pools.destroy', "type the pool's name (tank) to destroy it", refused: true))
      post '/disks/destroy_pool', params: { name: 'tank', confirm: 'no' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq("type the pool's name (tank) to destroy it")
    end

    it "offers Replace on every drive (highlighted when it isn't ONLINE), Add drives in the pool's shape, and Delete" do
      stub_pools(installed: true, pools: [pool])
      get '/disks/pools'
      card = page.at_css('#pool-tank')
      replace = card.css('[data-pool-dialog="replace"]')
      expect(replace.map { |b| b['data-old'] }).to eq(['/dev/disk/by-id/ata-Samsung_SSD_870_S1-part1', '1234'])
      expect(replace.map { |b| b['data-old-label'] }).to eq(['/dev/sdc (Samsung_SSD_870_S1)', 'the missing drive (was /dev/disk/by-id/ata-Samsung_SSD_870_S2-part1)'])
      expect(replace.map { |b| b['class'][/btn-(warning|outline-secondary)/] }).to eq(%w[btn-outline-secondary btn-warning])
      add = card.at_css('[data-pool-dialog="add"]')
      expect(add.to_h.slice('data-layout', 'data-width', 'data-parity', 'data-layout-name')).to eq(
        'data-layout' => 'raidz1', 'data-width' => '2', 'data-parity' => '1', 'data-layout-name' => 'RAIDZ1'
      )
      expect(card.at_css('[data-pool-dialog="destroy"]')['data-name']).to eq('tank')
      dialogs = %w[replace-dialog add-dialog destroy-dialog].map { |id| page.at_css("##{id}") }
      expect(dialogs.map { |d| d['data-url'] }).to eq(%w[/disks/replace_pool_drive /disks/add_pool_group /disks/destroy_pool])
      expect(page.css('#replace-dialog input[name="new"]').map { |i| i['value'] }).to eq(%w[/dev/sdd /dev/sde /dev/sdf])
      expect(page.css('#add-dialog input[name="devices[]"]').map { |i| i['value'] }).to eq(%w[/dev/sdd /dev/sde /dev/sdf])
      expect(card.at_css('[data-pool-scanning]')).to be_nil
    end

    it "shows a pool's snapshots, what it keeps, and Roll back and Delete for Amahi-kai's own" do
      created = 2.hours.ago.to_i
      snappy = StoragePools::Pool.new(**pool.to_h, snapshot_space: 3_000_000, snapshot_policy: { 'hourly' => 12, 'daily' => 30 },
                                                   snapshots: [{ 'name' => 'my-own', 'kind' => nil, 'created' => created - 60, 'used' => 1 },
                                                               { 'name' => 'amahi-daily-2026-10-04-0010', 'kind' => 'daily', 'created' => created - 30, 'used' => 2 },
                                                               { 'name' => 'amahi-hourly-2026-10-05-1300', 'kind' => 'hourly', 'created' => created, 'used' => 3 }])
      stub_pools(installed: true, pools: [snappy])
      get '/disks/pools'
      section = page.at_css('#snapshots-tank')
      expect(section.text.squish).to include('3 snapshots, using 2.86 MB')
      form = section.at_css('[data-snapshot-policy]')
      expect([form['data-url'], form.at_css('[name=hourly]')['value'], form.at_css('[name=daily]')['value']])
        .to eq(['/disks/pool_snapshot_policy', '12', '30'])
      expect(section.at_css('[data-storage-post="/disks/snapshot_pool"]')['data-name']).to eq('tank')
      rows = section.css('[data-snapshot-table] tbody tr')
      expect(rows.map { |tr| tr.css('td').first.text.squish }).to eq(['Hourly amahi-hourly-2026-10-05-1300', 'Daily amahi-daily-2026-10-04-0010',
                                                                      "Not Amahi-kai's my-own"])
      rollbacks = section.css('[data-pool-dialog="rollback"]')
      expect(rollbacks.map { |b| [b['data-snapshot'], b['data-later']] }).to eq(
        [['amahi-hourly-2026-10-05-1300', ''], ['amahi-daily-2026-10-04-0010', ', and so are the 1 snapshot taken after it']]
      )
      expect(rows.last.css('button')).to be_empty
      delete = section.at_css('[data-storage-post="/disks/destroy_pool_snapshot"]')
      expect(delete.to_h.slice('data-name', 'data-snapshot')).to eq('data-name' => 'tank', 'data-snapshot' => 'amahi-hourly-2026-10-05-1300')
      expect(page.at_css('#rollback-dialog')['data-url']).to eq('/disks/rollback_pool')
    end

    it 'takes, deletes and rolls back snapshots and sets what a pool keeps, through the helper' do
      post '/disks/snapshot_pool', params: { name: 'tank' }, as: :json
      post '/disks/pool_snapshot_policy', params: { name: 'tank', hourly: 6, daily: 14 }, as: :json
      post '/disks/destroy_pool_snapshot', params: { name: 'tank', snapshot: 'amahi-hourly-2026-10-05-1300' }, as: :json
      post '/disks/rollback_pool', params: { name: 'tank', snapshot: 'amahi-daily-2026-10-04-0010', confirm: 'tank' }, as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls.map(&:first) - ['storage.check_health']).to eq(%w[pools.snapshot pools.snapshot_policy pools.destroy_snapshot pools.rollback])
      post '/disks/pool_snapshot_policy', params: { name: 'tank', hourly: 'lots', daily: 14 }, as: :json
      expect(response.parsed_body).to eq('status' => 'error', 'error' => 'Keep a whole number of snapshots')
    end

    it 'says the page updates while a resilver runs, and offers no Add drives for a pool of mixed groups' do
      resilvering = StoragePools::Pool.new(**pool.to_h, scan: 'resilver in progress since Sun Oct  4 10:00:00 2026',
                                                        vdevs: pool.vdevs + [{ 'name' => 'mirror-1', 'children' => [{}, {}] }])
      stub_pools(installed: true, pools: [resilvering])
      get '/disks/pools'
      card = page.at_css('#pool-tank')
      expect(card.at_css('[data-pool-scanning]').text).to include('updates every 30 seconds')
      expect(card.at_css('[data-pool-dialog="add"]')).to be_nil
      expect(card.at_css('[data-storage-post="/disks/scrub_pool"]')['disabled']).not_to be_nil
    end

    it "passes on the helper's refusal" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('pools.create', '/dev/sdb is mounted at /mnt/storage-1; unmount it first', refused: true))
      post '/disks/create_pool', params: { name: 'tank', layout: 'mirror', devices: %w[/dev/sdb /dev/sdd] }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('status' => 'error', 'error' => '/dev/sdb is mounted at /mnt/storage-1; unmount it first')
    end

    it 'installs ZFS and the drive health tools, streaming the progress' do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(false)
      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(false)
      get '/disks/install_storage_tools_stream', headers: same_origin
      expect(response.body).to include('data: Installing ZFS (zfsutils-linux)...', 'data: ✓ Installed', "event: done\ndata: success")
      expect(Privileged.calls).to eq([['packages.install', { packages: ['zfsutils-linux'] }], ['zfs.setup', {}],
                                      ['packages.install', { packages: ['smartmontools'], recommends: false }],
                                      ['storage.check_health', {}]])
    end

    it 'ends the install stream with an error when the install fails' do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.install', 'apt-get exited 100'))
      get '/disks/install_storage_tools_stream', headers: same_origin
      expect(response.body).to include('data: ✗ apt-get exited 100', "event: done\ndata: error")
    end

    context 'with a health check on file' do
      let(:health) do
        StorageHealth.new('checked_at' => 10.minutes.ago.utc.iso8601, 'smartctl' => true,
                          'pools' => [{ 'name' => 'tank', 'health' => 'DEGRADED', 'vdevs' => [] }],
                          'drives' => { '/dev/sdd' => { 'model' => 'Samsung SSD 870 EVO 1TB', 'passed' => true, 'power_on_hours' => 4210,
                                                        'firmware' => 'SVT02B6Q', 'attributes' => { '5' => { 'raw' => 3 }, '177' => { 'value' => 98 } } },
                                        '/dev/sde' => { 'model' => 'Samsung SSD 870 EVO 1TB', 'passed' => true, 'attributes' => {} } })
      end

      before { allow(StorageHealth).to receive(:load).and_return(health) }

      it 'shows the alerts, each drive\'s health and when it was checked' do
        stub_pools(installed: true, pools: [pool])
        get '/disks/pools'
        alerts = page.css('.storage-alerts .alert').map { |a| a.text.squish }
        expect(alerts).to eq(['Pool tank is DEGRADED', '/dev/sdd (Samsung SSD 870 EVO 1TB) has 3 reallocated sectors See the drive →'])
        health_cells = page.css('#pool-drives tbody tr').to_h { |tr| [tr.css('td')[1].text.strip, tr.css('td')[5].text.squish] }
        expect(health_cells['/dev/sdd']).to eq('Check Has 3 reallocated sectors · 2% worn · 4,210 hours · firmware SVT02B6Q')
        expect(health_cells['/dev/sde']).to eq('OK')
        expect(health_cells['/dev/sda']).to eq('Not checked yet')
        expect(page.at_css('#health-checked').text).to include('Health checked 10 minutes ago')
        expect(page.at_css('#health-checked button')['data-storage-post']).to eq('/disks/check_health')
      end

      it 'shows the alerts on every Disks page and on the dashboard' do
        stub_pools(installed: true)
        allow(DiskManager).to receive(:devices).and_return([])
        ['/disks', '/disks/devices', '/disks/mounts', '/disks/storage_pool', '/'].each do |path|
          get path
          expect(page.css('.storage-alerts .alert').size).to eq(2), path
        end
      end

      it 'says why a drive has no SMART data: a virtual disk, a drive that gives none, or no smartmontools' do
        checked = ->(smartctl) { StorageHealth.new('checked_at' => 1.minute.ago.utc.iso8601, 'smartctl' => smartctl,
                                                   'drives' => { '/dev/sda' => nil, '/dev/sdd' => nil }) }
        drives = [drive('/dev/sda', :os, model: 'QEMU HARDDISK'), drive('/dev/sdd', :free, model: 'Samsung SSD 870 EVO 1TB')]
        stub_pools(installed: true, drives: drives)
        cells = lambda do
          get '/disks/pools'
          page.css('#pool-drives tbody tr').to_h { |tr| [tr.css('td')[1].text.strip, tr.css('td')[5].text.squish] }
        end
        allow(StorageHealth).to receive(:load).and_return(checked.call(true))
        expect(cells.call).to eq('/dev/sda' => 'Virtual disk: no SMART data', '/dev/sdd' => 'No SMART data from this drive')
        allow(StorageHealth).to receive(:load).and_return(checked.call(false))
        expect(cells.call.values.uniq).to eq(['Needs smartmontools'])

        allow(StorageHealth).to receive(:load).and_return(checked.call(true))
        allow(DiskManager).to receive(:devices).and_return([
          { name: 'sda', path: '/dev/sda', model: 'QEMU HARDDISK', size: '35G', os_disk: true, zfs_pool: nil, partitions: [] }
        ])
        get '/disks/devices'
        expect(page.css('#disks-table .card-header .badge').map(&:text).map(&:squish)).to eq(['Virtual disk', 'OS Disk'])
      end

      it 'puts a SMART badge on Devices' do
        allow(DiskManager).to receive(:devices).and_return([
          { name: 'sdd', path: '/dev/sdd', model: 'SSD', size: '931.5G', os_disk: false, zfs_pool: nil, partitions: [] }
        ])
        get '/disks/devices'
        expect(page.at_css('#disks-table .card-header .badge').text).to eq('SMART Check')
      end
    end

    it 'offers Scrub now (not while scrubbing) and says when the next automatic scrub is' do
      allow(StoragePools).to receive(:next_scrub).and_return(Time.local(2026, 10, 11, 0, 24))
      scrubbing = pool.dup.tap { |p| p.scan = 'scrub in progress since Sun Oct  4 10:00:00 2026' }
      stub_pools(installed: true, pools: [pool, StoragePools::Pool.new(**scrubbing.to_h, name: 'busy')])
      get '/disks/pools'
      scrub = page.at_css('#pool-tank [data-storage-post="/disks/scrub_pool"]')
      expect(scrub['data-name']).to eq('tank')
      expect(scrub.text.strip).to eq('Scrub now')
      expect(page.at_css('#pool-busy [data-storage-post="/disks/scrub_pool"]')['disabled']).not_to be_nil
      expect(page.at_css('#pool-tank').text).to include('Next automatic scrub: Sunday, October 11 at 00:24.')
    end

    it 'scrubs a pool and runs the health check through the helper' do
      post '/disks/scrub_pool', params: { name: 'tank' }, as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      post '/disks/check_health', as: :json
      expect(Privileged.calls).to eq([['pools.scrub', { name: 'tank' }], ['storage.check_health', {}]])
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('pools.scrub', 'there\'s no pool named "x"', refused: true))
      post '/disks/scrub_pool', params: { name: 'x' }, as: :json
      expect(response.parsed_body).to eq('status' => 'error', 'error' => 'there\'s no pool named "x"')
    end

    it 'offers smartmontools when ZFS is installed but it is not' do
      stub_pools(installed: true)
      allow(StoragePools).to receive(:smart_installed?).and_return(false)
      get '/disks/pools'
      expect(page.at_css('#install-smart-btn')['data-storage-install']).to eq('/disks/install_storage_tools_stream')
      allow(StoragePools).to receive(:smart_installed?).and_return(true)
      get '/disks/pools'
      expect(page.at_css('#smart-not-installed')).to be_nil
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
