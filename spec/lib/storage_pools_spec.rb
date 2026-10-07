require 'rails_helper'
require 'storage_pools'

RSpec.describe StoragePools do
  let(:raidz) do
    { 'name' => 'tank', 'health' => 'DEGRADED', 'size' => 4_000, 'allocated' => 10, 'used' => 5, 'available' => 2_900,
      'mountpoint' => '/srv/pools/tank', 'state' => 'DEGRADED', 'scan' => 'none requested', 'errors' => 'No known data errors',
      'vdevs' => [{ 'name' => 'raidz1-0', 'state' => 'DEGRADED', 'children' => [
        { 'name' => '/dev/disk/by-id/ata-SSD_1-part1', 'device' => '/dev/sdc1', 'state' => 'ONLINE', 'children' => [] },
        { 'name' => '1234', 'state' => 'UNAVAIL', 'note' => 'was /dev/disk/by-id/ata-SSD_2-part1', 'children' => [] }
      ] }] }
  end

  def reply(data)
    allow(Privileged).to receive(:call).with('pools.status').and_return({ 'ok' => true }.merge(data))
  end

  describe '.status' do
    it 'turns the helper reply into pools' do
      reply('zfs' => true, 'pools' => [raidz])
      status = described_class.status
      expect(status[:installed]).to be(true)
      pool = status[:pools].sole
      expect(pool).to have_attributes(name: 'tank', health: 'DEGRADED', used: 5, available: 2_900, layout: 'RAIDZ1')
      expect(pool).not_to be_healthy
      expect(pool.drives.map { |d| d['state'] }).to eq(%w[ONLINE UNAVAIL])
      expect(pool.data_errors).to be_nil
    end

    it 'names each layout from its vdevs' do
      layout = ->(*names) { StoragePools::Pool.new(vdevs: names.map { |n| { 'name' => n, 'children' => [] } }).layout }
      expect(layout.call('mirror-0')).to eq('Mirror')
      expect(layout.call('mirror-0', 'mirror-1')).to eq('Striped mirrors')
      expect(layout.call('raidz2-0', 'raidz2-1')).to eq('RAIDZ2')
      expect(layout.call('/dev/disk/by-id/ata-x')).to eq('Stripe')
    end

    it "reports ZFS as not installed, and the helper's error" do
      reply('zfs' => false, 'pools' => [])
      expect(described_class.status).to eq(installed: false, pools: [], offline: [], error: nil)
      allow(Privileged).to receive(:call).with('pools.status').and_raise(Privileged::Error.new('pools.status', 'boom'))
      expect(described_class.status).to eq(installed: false, pools: [], offline: [], error: 'boom')
    end

    it 'lists the pools taken offline, and says what keeps ZFS from being uninstalled' do
      reply('zfs' => true, 'pools' => [], 'offline' => [{ 'name' => 'away', 'state' => 'ONLINE', 'devices' => ['/dev/sdd1'] },
                                                        { 'name' => 'gone', 'state' => 'MISSING', 'devices' => [] }])
      status = described_class.status
      expect(status[:offline].map { |p| [p.name, p.found?] }).to eq([['away', true], ['gone', false]])
      expect(described_class.removal_blocker(status)).to eq('The pool away is offline: bring it online and delete it first.')
      reply('zfs' => true, 'pools' => [raidz])
      expect(described_class.removal_blocker(described_class.status)).to eq('Delete the pool tank first.')
      reply('zfs' => true, 'pools' => [])
      expect(described_class.removal_blocker(described_class.status)).to be_nil
    end
  end

  describe '.drives' do
    let(:lsblk) do
      { 'blockdevices' => [
        { 'path' => '/dev/sda', 'type' => 'disk', 'size' => 64_000, 'model' => 'QEMU HARDDISK', 'rota' => true, 'mountpoints' => [nil],
          'children' => [{ 'path' => '/dev/sda1', 'type' => 'part', 'mountpoints' => ['/'] }] },
        { 'path' => '/dev/sdb', 'type' => 'disk', 'size' => 1_000, 'mountpoints' => [nil],
          'children' => [{ 'path' => '/dev/sdb1', 'type' => 'part', 'fstype' => 'ext4', 'mountpoints' => ['/mnt/storage-1'] }] },
        { 'path' => '/dev/sdc', 'type' => 'disk', 'size' => 1_000, 'mountpoints' => [nil],
          'children' => [{ 'path' => '/dev/sdc1', 'type' => 'part', 'fstype' => 'zfs_member', 'label' => 'tank', 'mountpoints' => [nil] }] },
        { 'path' => '/dev/sdd', 'type' => 'disk', 'size' => 1_000, 'mountpoints' => [nil],
          'children' => [{ 'path' => '/dev/sdd1', 'type' => 'part', 'fstype' => 'zfs_member', 'label' => 'oldpool', 'mountpoints' => [nil] }] },
        { 'path' => '/dev/sde', 'type' => 'disk', 'size' => 1_000_000, 'model' => 'Samsung SSD 870 EVO 1TB ', 'serial' => 'S6P',
          'rota' => false, 'mountpoints' => [nil] },
        { 'path' => '/dev/sdf', 'type' => 'disk', 'size' => 1_000, 'mountpoints' => [nil],
          'children' => [{ 'path' => '/dev/md0', 'type' => 'raid1', 'mountpoints' => [nil] }] },
        { 'path' => '/dev/sr0', 'type' => 'rom', 'size' => 1, 'mountpoints' => [nil] }
      ] }.to_json
    end

    before do
      allow(Open3).to receive(:capture3)
        .with('lsblk', '-J', '-b', '-o', 'NAME,PATH,TYPE,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS,ROTA')
        .and_return([lsblk, '', instance_double(Process::Status, success?: true)])
    end

    it 'says what each whole disk is used for, and which a new pool may take' do
      reply('zfs' => true, 'pools' => [raidz])
      drives = described_class.drives(described_class.status[:pools])
      expect(drives.to_h { |d| [d[:path], [d[:role], d[:free]]] }).to eq(
        '/dev/sda' => [:os, false], '/dev/sdb' => [:share, false], '/dev/sdc' => [:pool, false],
        '/dev/sdd' => [:old_zfs, true], '/dev/sde' => [:free, true], '/dev/sdf' => [:in_use, false]
      )
      expect(drives.find { |d| d[:path] == '/dev/sde' }).to include(model: 'Samsung SSD 870 EVO 1TB', serial: 'S6P', size: 1_000_000, ssd: true)
      expect(drives.find { |d| d[:path] == '/dev/sdc' }[:pool]).to eq('tank')
      expect(drives.find { |d| d[:path] == '/dev/sdb' }[:mounts]).to eq(['/mnt/storage-1'])
    end

    it "keeps an offline pool's drives for it, by the drives found or by their label" do
      offline = [StoragePools::OfflinePool.new(name: 'oldpool', state: 'ONLINE', devices: [])]
      drives = described_class.drives([], offline)
      expect(drives.find { |d| d[:path] == '/dev/sdd' }).to include(role: :offline, pool: 'oldpool', free: false)
      offline = [StoragePools::OfflinePool.new(name: 'away', state: 'ONLINE', devices: ['/dev/sde'])]
      expect(described_class.drives([], offline).find { |d| d[:path] == '/dev/sde' }).to include(role: :offline, pool: 'away', free: false)
    end

    # lsblk lists every device flat unless NAME is the first column, and then a disk seems
    # to have nothing on it: the system disk showed as free.
    it 'lists nothing rather than read a flat list' do
      flat = { 'blockdevices' => [{ 'path' => '/dev/sda', 'type' => 'disk', 'mountpoints' => [nil] },
                                  { 'path' => '/dev/sda1', 'type' => 'part', 'mountpoints' => ['/'] }] }.to_json
      allow(Open3).to receive(:capture3).and_return([flat, '', instance_double(Process::Status, success?: true)])
      expect(described_class.drives).to eq([])
    end

    it "never offers the disk this machine runs from (its real lsblk)" do
      allow(Open3).to receive(:capture3).and_call_original
      out, _err, status = Open3.capture3('lsblk', '-J', '-o', 'NAME,PATH,MOUNTPOINTS')
      skip 'no lsblk here' unless status.success?
      mounted = ->(node) { [*Array(node['mountpoints']), *Array(node['children']).flat_map { |c| mounted.call(c) }] }
      root = JSON.parse(out)['blockdevices'].find { |disk| mounted.call(disk).include?('/') }
      skip "/ isn't on a disk lsblk lists here" unless root
      expect(described_class.drives.find { |d| d[:path] == root['path'] }).to include(role: :os, free: false)
    end

    it 'lists nothing when lsblk fails' do
      allow(Open3).to receive(:capture3).and_return(['', 'boom', instance_double(Process::Status, success?: false)])
      expect(described_class.drives).to eq([])
    end
  end

  describe '.install!' do
    before do
      allow(File).to receive(:executable?).and_call_original
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('packages.install', packages: ['zfsutils-linux']).and_yield('Setting up zfsutils-linux')
      allow(Privileged).to receive(:call).with('zfs.setup').and_return('ok' => true, 'arc_max' => 2_147_483_648)
    end

    def installed(zfs:, smart:)
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(zfs)
      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(smart)
    end

    it 'installs ZFS and the drive health tools (without their recommends), sets ZFS up and checks the drives' do
      installed(zfs: false, smart: false)
      lines = []
      described_class.install! { |line| lines << line }
      expect(lines).to eq(['Installing ZFS (zfsutils-linux)...', '  Setting up zfsutils-linux',
                           'Loading ZFS and limiting its memory cache...', "  ✓ ZFS's cache is limited to 2 GB",
                           'Installing the drive health tools (smartmontools)...', 'Checking the drives...'])
      expect(Privileged).to have_received(:call).with('packages.install', packages: ['smartmontools'], recommends: false)
      expect(Privileged.calls).to include(['storage.check_health', {}])
    end

    it 'installs only what is missing' do
      installed(zfs: true, smart: false)
      described_class.install!
      expect(Privileged).not_to have_received(:call).with('packages.install', packages: ['zfsutils-linux'])
      expect(Privileged).not_to have_received(:call).with('zfs.setup')
      expect(Privileged).to have_received(:call).with('packages.install', packages: ['smartmontools'], recommends: false)
    end

    it 'raises the helper error' do
      installed(zfs: false, smart: false)
      allow(Privileged).to receive(:call).with('packages.install', packages: ['zfsutils-linux'])
                                         .and_raise(Privileged::Error.new('packages.install', 'apt failed'))
      expect { described_class.install! }.to raise_error(StoragePools::Error, 'apt failed')
    end
  end

  describe '.next_scrub' do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/etc/cron.d/zfsutils-linux').and_return(true)
    end

    it "is the second Sunday of the month at 00:24, Ubuntu's schedule" do
      expect(described_class.next_scrub(Time.local(2026, 10, 4, 12))).to eq(Time.local(2026, 10, 11, 0, 24))
      expect(described_class.next_scrub(Time.local(2026, 10, 11, 1))).to eq(Time.local(2026, 11, 8, 0, 24))
      expect(described_class.next_scrub(Time.local(2026, 12, 20))).to eq(Time.local(2027, 1, 10, 0, 24))
    end

    it "is nil without the package's schedule" do
      allow(File).to receive(:exist?).with('/etc/cron.d/zfsutils-linux').and_return(false)
      expect(described_class.next_scrub).to be_nil
    end
  end

  describe 'changing a pool' do
    it 'replaces a drive, adds a group and destroys a pool through the helper, then checks the health' do
      described_class.replace!(name: 'tank', old: '1234567890', new: '/dev/sdg')
      described_class.add_group!(name: 'tank', devices: %w[/dev/sdg /dev/sdh /dev/sdi])
      described_class.destroy!(name: 'tank', confirm: 'tank')
      expect(Privileged.calls).to eq([
        ['pools.replace', { name: 'tank', old: '1234567890', new: '/dev/sdg' }], ['storage.check_health', {}],
        ['pools.add_group', { name: 'tank', devices: %w[/dev/sdg /dev/sdh /dev/sdi] }], ['storage.check_health', {}],
        ['pools.destroy', { name: 'tank', confirm: 'tank' }], ['storage.check_health', {}]
      ])
    end

    it "needs the drives, and doesn't fail a change when the health check after it does" do
      expect { described_class.replace!(name: 'tank', old: 'x', new: '') }.to raise_error(StoragePools::Error, 'Choose the new drive')
      expect { described_class.add_group!(name: 'tank', devices: []) }.to raise_error(StoragePools::Error, 'Choose the drives to add')
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('storage.check_health').and_raise(Privileged::Error.new('storage.check_health', 'busy'))
      expect { described_class.destroy!(name: 'tank', confirm: 'tank') }.not_to raise_error
    end

    it "knows the shape of a pool's groups, and when a scrub or resilver runs" do
      pool = lambda do |*groups, scan: nil|
        StoragePools::Pool.new(scan: scan, vdevs: groups.map { |name, width| { 'name' => name, 'children' => Array.new(width) { {} } } })
      end
      expect(pool.call(['raidz1-0', 4], ['raidz1-1', 4]).group_shape).to eq(['raidz1', 4])
      expect(pool.call(['mirror-0', 2]).group_shape).to eq(['mirror', 2])
      expect(pool.call(['raidz1-0', 4], ['raidz1-1', 3]).group_shape).to be_nil
      expect(pool.call(['mirror-0', 2], ['raidz2-1', 4]).group_shape).to be_nil
      expect(pool.call(['/dev/sdc1', 0]).group_shape).to be_nil
      expect(pool.call(scan: 'resilver in progress since Sun Oct  4 10:00:00 2026')).to be_scanning
      expect(pool.call(scan: 'scrub in progress since Sun Oct  4 10:00:00 2026')).to be_scanning
      expect(pool.call(scan: 'scrub repaired 0B in 00:01:02 with 0 errors on Sun Oct  4 02:41:08 2026')).not_to be_scanning
    end
  end

  describe 'snapshots' do
    it 'takes one now, sets what a pool keeps, deletes one and rolls back, through the helper' do
      described_class.snapshot!('tank')
      described_class.set_snapshot_policy!(name: 'tank', hourly: '12', daily: 7)
      described_class.destroy_snapshot!(name: 'tank', snapshot: 'amahi-hourly-2026-10-05-1300')
      described_class.rollback!(name: 'tank', snapshot: 'amahi-daily-2026-10-04-0010', confirm: 'tank')
      expect(Privileged.calls - [['storage.check_health', {}]]).to eq([
        ['pools.snapshot', { name: 'tank' }],
        ['pools.snapshot_policy', { name: 'tank', hourly: 12, daily: 7 }],
        ['pools.destroy_snapshot', { name: 'tank', snapshot: 'amahi-hourly-2026-10-05-1300' }],
        ['pools.rollback', { name: 'tank', snapshot: 'amahi-daily-2026-10-04-0010', confirm: 'tank' }]
      ])
    end

    it 'needs whole numbers to keep' do
      expect { described_class.set_snapshot_policy!(name: 'tank', hourly: 'many', daily: 7) }.to raise_error(StoragePools::Error, 'Keep a whole number of snapshots')
      expect { described_class.set_snapshot_policy!(name: 'tank', hourly: '2.5', daily: 7) }.to raise_error(StoragePools::Error)
      expect(Privileged.calls).to be_empty
    end

    it "gives a pool's snapshots with their times, and what it keeps (the defaults when unset)" do
      pool = StoragePools::Pool.new(snapshots: [{ 'name' => 'amahi-daily-2026-10-04-0010', 'kind' => 'daily', 'created' => 1_791_000_000, 'used' => 5 }])
      expect(pool.snapshot_list.sole).to include('kind' => 'daily', 'created' => Time.at(1_791_000_000))
      expect(pool.keeps).to eq('hourly' => 24, 'daily' => 30)
      expect(StoragePools::Pool.new(snapshot_policy: { 'hourly' => 0, 'daily' => 7 }).keeps).to eq('hourly' => 0, 'daily' => 7)
    end
  end

  it 'scrubs a pool and checks the health through the helper' do
    described_class.scrub!('tank')
    described_class.check_health!
    expect(Privileged.calls).to eq([['pools.scrub', { name: 'tank' }], ['storage.check_health', {}]])
  end

  describe '.create!' do
    it 'passes the request to the helper' do
      described_class.create!(name: ' tank ', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde])
      expect(Privileged.calls).to eq([['pools.create', { name: 'tank', layout: 'raidz1', devices: %w[/dev/sdc /dev/sdd /dev/sde] }],
                                      ['storage.check_health', {}]])
    end

    it 'needs a known layout and some drives' do
      expect { described_class.create!(name: 'tank', layout: 'raid5', devices: ['/dev/sdc']) }.to raise_error(StoragePools::Error, 'Choose a layout')
      expect { described_class.create!(name: 'tank', layout: 'mirror', devices: []) }.to raise_error(StoragePools::Error, /Choose the drives/)
      expect(Privileged.calls).to be_empty
    end
  end
end
