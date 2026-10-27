require 'rails_helper'

# The root helper's ZFS operations (docs/plans/storage.md): installing ZFS's settings, reading
# pools, creating one on whole disks, and keeping pool drives away from share storage.
RSpec.describe 'AmahiHelper ZFS pools' do
  let(:helper) { AmahiHelper }

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

  def status(success)
    instance_double(Process::Status, success?: success, exitstatus: success ? 0 : 1)
  end

  # sda: the OS disk. sdb: a share drive mounted under /mnt. sdc: an unmounted disk with an
  # old ext4 partition. sdd, sde, sdf: empty disks. sdg: an LVM volume on it. sdh: a disk in
  # a pool already. nvme0n1: an empty NVMe drive.
  let(:dir) { Dir.mktmpdir }
  let(:mnt) { "#{dir}/mnt" }
  let(:fstab) { "#{dir}/fstab" }
  let(:tree) do
    [{ 'path' => '/dev/sda', 'type' => 'disk', 'mountpoints' => [nil],
       'children' => [{ 'path' => '/dev/sda1', 'type' => 'part', 'mountpoints' => ['/boot/efi'] },
                      { 'path' => '/dev/sda2', 'type' => 'part', 'mountpoints' => ['/'] }] },
     { 'path' => '/dev/sdb', 'type' => 'disk', 'mountpoints' => [nil],
       'children' => [{ 'path' => '/dev/sdb1', 'type' => 'part', 'fstype' => 'ext4', 'mountpoints' => ["#{mnt}/storage-1"] }] },
     { 'path' => '/dev/sdc', 'type' => 'disk', 'mountpoints' => [nil],
       'children' => [{ 'path' => '/dev/sdc1', 'type' => 'part', 'fstype' => 'ext4', 'mountpoints' => [nil] }] },
     { 'path' => '/dev/sdd', 'type' => 'disk', 'mountpoints' => [nil] },
     { 'path' => '/dev/sde', 'type' => 'disk', 'mountpoints' => [nil] },
     { 'path' => '/dev/sdf', 'type' => 'disk', 'mountpoints' => [nil] },
     { 'path' => '/dev/sdg', 'type' => 'disk', 'mountpoints' => [nil],
       'children' => [{ 'path' => '/dev/sdg1', 'type' => 'part', 'mountpoints' => [nil],
                        'children' => [{ 'path' => '/dev/mapper/vg-data', 'type' => 'lvm', 'mountpoints' => [nil] }] }] },
     { 'path' => '/dev/sdh', 'type' => 'disk', 'mountpoints' => [nil],
       'children' => [{ 'path' => '/dev/sdh1', 'type' => 'part', 'fstype' => 'zfs_member', 'mountpoints' => [nil] },
                      { 'path' => '/dev/sdh9', 'type' => 'part', 'mountpoints' => [nil] }] },
     { 'path' => '/dev/nvme0n1', 'type' => 'disk', 'mountpoints' => [nil] }]
  end

  before do
    Dir.mkdir(mnt)
    File.write(fstab, "UUID=os / ext4 defaults 0 1\n")
    stub_const('AmahiHelper::MNT', mnt)
    stub_const('AmahiHelper::FSTAB', fstab)
    stub_const('AmahiHelper::POOL_ROOT', "#{dir}/pools")
    stub_const('AmahiHelper::APP_STORAGE', "#{dir}/app-storage.json")
    allow(helper).to receive(:block_tree).and_return(tree)
    allow(File).to receive(:blockdev?).and_call_original
    allow(File).to receive(:blockdev?).with(a_string_starting_with('/dev/')).and_return(true)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(true)
    allow(helper).to receive(:probe).and_return({})
    allow(helper).to receive(:pool_names).and_return(['old'])
    allow(helper).to receive(:pooled_devices).and_return('/dev/sdh1' => 'old')
    allow(helper).to receive(:stable_path) { |disk| "/dev/disk/by-id/ata-SSD_#{File.basename(disk)}" }
    allow(helper).to receive(:ssd?).and_return(true)
    allow(helper).to receive(:other_mount_views).and_return([])
    stub_const('AmahiHelper::APP_RECORDS_LOCK', "#{dir}/app-records.lock")
    # No pool on the drives that isn't imported; every pool here mounts at POOL_ROOT/<name> (Amahi-kai's)
    allow(helper).to receive(:importable_pools).and_return([])
    allow(helper).to receive(:pool_mountpoint) { |name| "#{dir}/pools/#{name}" }
  end

  after { FileUtils.rm_rf(dir) }

  describe 'pools.create' do
    def create(layout, devices, name: 'tank')
      { 'name' => name, 'layout' => layout, 'devices' => devices }
    end

    it 'wipes the disks (partitions first) and creates the pool by their by-id names' do
      expect(steps('pools.create', create('raidz1', %w[/dev/sdc /dev/sdd /dev/sde]))).to eq(
        [%w[/usr/sbin/wipefs -a /dev/sdc1], %w[/usr/sbin/wipefs -a /dev/sdc], %w[/usr/sbin/wipefs -a /dev/sdd],
         %w[/usr/sbin/wipefs -a /dev/sde], ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [:make_dir, "#{dir}/pools", '0755'],
         ['/usr/sbin/zpool', 'create', '-f', '-o', 'ashift=12', '-o', 'autoexpand=on', '-o', 'autotrim=on', '-O', 'compression=lz4',
          '-O', 'setuid=off', '-O', 'devices=off', '-O', "mountpoint=#{dir}/pools/tank", '-O', 'amahi:snapshot-hourly=24', '-O', 'amahi:snapshot-daily=30', 'tank', 'raidz1',
          '/dev/disk/by-id/ata-SSD_sdc', '/dev/disk/by-id/ata-SSD_sdd', '/dev/disk/by-id/ata-SSD_sde'],
         [:pool_status]]
      )
    end

    it 'builds each layout, and leaves autotrim off unless every drive is an SSD' do
      vdevs = lambda do |layout, devices|
        command = steps('pools.create', create(layout, devices))[-2]
        command.drop(command.index('tank') + 1)
      end
      ids = %w[sdc sdd sde sdf].map { |d| "/dev/disk/by-id/ata-SSD_#{d}" }
      expect(vdevs.call('mirror', %w[/dev/sdc /dev/sdd])).to eq(['mirror', *ids.first(2)])
      expect(vdevs.call('striped_mirrors', %w[/dev/sdc /dev/sdd /dev/sde /dev/sdf]))
        .to eq(['mirror', ids[0], ids[1], 'mirror', ids[2], ids[3]])
      expect(vdevs.call('raidz2', %w[/dev/sdc /dev/sdd /dev/sde /dev/sdf])).to eq(['raidz2', *ids])

      allow(helper).to receive(:ssd?).with('/dev/sdd').and_return(false)
      expect(steps('pools.create', create('mirror', %w[/dev/sdc /dev/sdd]))[-2]).not_to include('autotrim=on')
    end

    it 'needs enough drives for the layout, in pairs for striped mirrors' do
      expect(refusal('pools.create', create('mirror', %w[/dev/sdc]))).to eq('mirror needs at least 2 drives')
      expect(refusal('pools.create', create('raidz1', %w[/dev/sdc /dev/sdd]))).to eq('raidz1 needs at least 3 drives')
      expect(refusal('pools.create', create('raidz3', %w[/dev/sdc /dev/sdd /dev/sde /dev/sdf]))).to eq('raidz3 needs at least 5 drives')
      expect(refusal('pools.create', create('striped_mirrors', %w[/dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/nvme0n1])))
        .to eq('striped_mirrors needs an even number of drives')
      expect(refusal('pools.create', create('raid5', %w[/dev/sdc /dev/sdd /dev/sde]))).to include("isn't one Amahi-kai uses")
      expect(refusal('pools.create', create('mirror', '/dev/sdc'))).to eq('devices must be a list of disks')
    end

    it 'refuses the OS disk, partitions, mounted drives, drives in use, in fstab, in a pool or listed twice' do
      expect(refusal('pools.create', create('mirror', %w[/dev/sda /dev/sdd]))).to include('is a disk the system uses')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdc1 /dev/sdd]))).to eq('"/dev/sdc1" is not a whole disk')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdb /dev/sdd]))).to eq("/dev/sdb is mounted at #{mnt}/storage-1; unmount it first")
      expect(refusal('pools.create', create('mirror', %w[/dev/sdg /dev/sdd]))).to eq('/dev/sdg holds /dev/mapper/vg-data (lvm), which is in use')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdh /dev/sdd]))).to eq('/dev/sdh is in the pool old')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sdd]))).to eq('/dev/sdd is listed twice')
      expect(refusal('pools.create', create('mirror', ['/dev/sdd; reboot', '/dev/sde']))).to include('is not a whole disk')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdq /dev/sdd]))).to eq("lsblk doesn't list /dev/sdq")

      allow(helper).to receive(:probe).with('/dev/sdc1').and_return('UUID' => 'u-1', 'PART_ENTRY_UUID' => 'p-1')
      File.write(fstab, "UUID=u-1 #{mnt}/old ext4 defaults,nofail 0 2\n")
      expect(refusal('pools.create', create('mirror', %w[/dev/sdc /dev/sdd]))).to include('/dev/sdc1 is in /etc/fstab (UUID=u-1)')
      File.write(fstab, "PARTUUID=p-1 #{mnt}/old ext4 defaults 0 2\n")
      expect(refusal('pools.create', create('mirror', %w[/dev/sdc /dev/sdd]))).to include('(PARTUUID=p-1)')
    end

    it 'checks the pool name, and that its mount point is free' do
      ['Tank', '1tank', 'my pool', 'a' * 33, '', 'tank/x', '../x'].each do |name|
        expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde], name: name))).not_to be_nil, name.inspect
      end
      %w[mirror raidz raidz2 spare log c0t0d0].each do |name|
        expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde], name: name))).to include('a word ZFS keeps'), name
      end
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde], name: 'old'))).to eq('a pool named old already exists')
      FileUtils.mkdir_p("#{dir}/pools/tank/stuff")
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde]))).to include('is in the way')
    end

    # A pool given an offline pool's name took its place: the offline one vanished from the page,
    # and its drives were offered for Erase. A pool found on the drives (this server's before it
    # was installed again) the same.
    it "refuses the name of a pool offline here or found on the drives, and a found pool's drives" do
      stub_const('AmahiHelper::OFFLINE_POOLS', "#{dir}/offline-pools.json")
      File.write("#{dir}/offline-pools.json", { 'away' => '1234' }.to_json)
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde], name: 'away')))
        .to eq('a pool named away is offline here; bring it online, or delete it, first')
      found = [{ 'name' => 'tank', 'id' => '5678', 'state' => 'ONLINE', 'force' => true, 'status' => nil, 'devices' => ['/dev/sdc1'] }]
      allow(helper).to receive(:importable_pools).and_return(found)
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde], name: 'tank')))
        .to eq('a pool named tank is on drives connected here, not imported; import it, or erase its drives, first')
      expect(refusal('pools.create', create('mirror', %w[/dev/sdc /dev/sdd], name: 'new')))
        .to eq("/dev/sdc holds the pool tank, which isn't imported; import it on Disks → ZFS Pools, or erase the drive there")
    end

    it "refuses when ZFS isn't installed" do
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(false)
      expect(refusal('pools.create', create('mirror', %w[/dev/sdd /dev/sde]))).to eq("zpool isn't installed")
    end
  end

  describe 'share storage' do
    it "won't format, mount or preview a drive with ZFS on it" do
      %w[disks.format disks.preview].each do |op|
        expect(refusal(op, { 'device' => '/dev/sdh1' })).to include('holds a ZFS pool'), op
        expect(refusal(op, { 'device' => '/dev/sdh' })).to include('holds a ZFS pool'), op
      end
      expect(refusal('disks.mount', { 'device' => '/dev/sdh9', 'mount_point' => "#{mnt}/x" })).to include('holds a ZFS pool')
      expect(refusal('disks.format', { 'device' => '/dev/sdd' })).to be_nil
    end
  end

  describe 'smart.setup' do
    it "clears the unit's virtual machine condition, and runs smartd only while a drive has SMART to watch" do
      expect(steps('smart.setup', {})).to eq(
        [[:make_dir, '/etc/systemd/system/smartmontools.service.d', '0755'],
         [:install, '/etc/systemd/system/smartmontools.service.d/amahi-kai.conf', AmahiHelper::SMARTD_DROPIN_CONTENT, nil],
         %w[/usr/bin/systemctl daemon-reload],
         [:smartd_follow_need]]
      )
      expect(AmahiHelper::SMARTD_DROPIN_CONTENT.lines.map(&:strip).reject { |l| l.start_with?('#') })
        .to eq(['[Unit]', 'ConditionVirtualization='])
    end
  end

  # smartd while a drive has SMART to watch, Greyhole while its pool has a drive and it isn't
  # switched off: each is switched on when it gets work and off when it has none, else left alone.
  describe 'services that run while they have work' do
    let(:states) { { 'is-enabled' => 'enabled', 'is-active' => 'active' } }
    let(:ran) { [] }

    before do
      allow(helper).to receive(:unit_state) { |question, _unit| states[question] }
      allow(helper).to receive(:run_command) { |argv| ran << argv && nil }
    end

    it 'switches a service on when it gets work, off when it has none, and leaves it alone otherwise' do
      states['is-enabled'] = 'disabled'
      expect(helper.follow_need('smartmontools.service', true)).to eq('on')
      # Two commands, not enable --now, which leaves an init script's service (Greyhole's) as it was
      expect(ran).to eq([['/usr/bin/systemctl', 'enable', 'smartmontools.service', { allow_failure: true }],
                         ['/usr/bin/systemctl', 'start', 'smartmontools.service', { allow_failure: true }]])

      ran.clear
      states['is-enabled'] = 'enabled' # left on: a stop on Settings → Servers lasts until the next restart
      expect(helper.follow_need('smartmontools.service', true)).to be_nil
      expect(ran).to eq([])

      expect(helper.follow_need('smartmontools.service', false)).to eq('off')
      expect(ran).to eq([['/usr/bin/systemctl', 'disable', 'smartmontools.service', { allow_failure: true }],
                         ['/usr/bin/systemctl', 'stop', 'smartmontools.service', { allow_failure: true }],
                         ['/usr/bin/systemctl', 'reset-failed', 'smartmontools.service', { allow_failure: true }]])

      ran.clear
      states.merge!('is-enabled' => 'disabled', 'is-active' => 'failed') # off at boot, but it failed once
      expect(helper.follow_need('smartmontools.service', false)).to eq('off')
      states['is-active'] = 'inactive'
      expect(helper.follow_need('smartmontools.service', false)).to be_nil
    end

    it 'reads the systemctl answer for an init script too, from what it prints last' do
      allow(helper).to receive(:unit_state).and_call_original
      allow(Open3).to receive(:capture3).with(AmahiHelper::ENV_MIN, %w[/usr/bin/systemctl /usr/bin/systemctl], 'is-enabled', 'greyhole.service',
                                              unsetenv_others: true, chdir: '/')
                                        .and_return(["enabled\n", "greyhole.service is not a native service, redirecting to systemd-sysv-install.\n", nil])
      expect(helper.unit_state('is-enabled', 'greyhole.service')).to eq('enabled')
    end

    it 'runs smartd while a drive has SMART data, and not on virtual disks' do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(true)
      allow(helper).to receive(:follow_need).and_return('off')
      expect(helper.do_smartd_follow_need('/dev/sda' => nil, '/dev/sdb' => nil)).to eq('smartd' => 'off')
      expect(helper).to have_received(:follow_need).with('smartmontools.service', false)
      helper.do_smartd_follow_need('/dev/sda' => nil, '/dev/sdb' => { 'model' => 'Samsung SSD 870 EVO 1TB', 'asleep' => true })
      expect(helper).to have_received(:follow_need).with('smartmontools.service', true)

      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(false) # no smartmontools
      expect(helper.do_smartd_follow_need).to be_nil
    end

    describe 'Greyhole' do
      let(:off) { "#{dir}/greyhole-off" }

      before do
        stub_const('AmahiHelper::GREYHOLE_OFF', off)
        allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
      end

      it "runs while its pool has a drive and it isn't switched off" do
        allow(helper).to receive(:follow_need) { |_unit, work| work ? 'on' : 'off' }
        allow(helper).to receive(:greyhole_drives).and_return([])
        expect(helper.do_greyhole_follow_need).to eq('greyhole' => 'off')
        allow(helper).to receive(:greyhole_drives).and_return(['/mnt/storage-1'])
        expect(helper.do_greyhole_follow_need).to eq('greyhole' => 'on')
        File.write(off, 'off')
        expect(helper.do_greyhole_follow_need).to eq('greyhole' => 'off')
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with('/usr/bin/greyhole').and_return(true)
        expect(steps('greyhole.follow_need', {})).to eq([[:greyhole_follow_need]])
      end

      it 'is switched off, staying off after a restart, and on again once its pool has a drive' do
        allow(helper).to receive(:greyhole_drives).and_return(['/mnt/storage-1'])
        # Asked for on the page: a stop or start that fails says why (no allow_failure)
        expect(helper.do_greyhole_switch(false)).to eq('on' => false)
        expect(File).to exist(off)
        expect(ran).to eq([['/usr/bin/systemctl', 'disable', 'greyhole.service'], ['/usr/bin/systemctl', 'stop', 'greyhole.service'],
                           ['/usr/bin/systemctl', 'reset-failed', 'greyhole.service', { allow_failure: true }]])

        ran.clear
        expect(helper.do_greyhole_switch(true)).to eq('on' => true)
        expect(File).not_to exist(off)
        expect(ran).to eq([['/usr/bin/systemctl', 'enable', 'greyhole.service'], ['/usr/bin/systemctl', 'start', 'greyhole.service']])

        allow(helper).to receive(:greyhole_drives).and_return([])
        expect { helper.do_greyhole_switch(true) }.to raise_error(AmahiHelper::Failed, 'Greyhole needs a drive in its pool to run: add one first')
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with('/usr/bin/greyhole').and_return(true)
        expect(steps('greyhole.switch', { 'on' => false })).to eq([[:greyhole_switch, false]])
        expect(refusal('greyhole.switch', { 'on' => 'yes' })).to include('true or false')
      end
    end
  end

  describe 'zfs.setup' do
    it 'caps the cache at 2 GiB, or half the memory on a small machine' do
      meminfo = "#{dir}/meminfo"
      stub_const('AmahiHelper::MEMINFO', meminfo)
      File.write(meminfo, "MemTotal:        8000000 kB\nMemFree: 1 kB\n")
      expect(steps('zfs.setup', {})).to eq(
        [%w[/usr/sbin/modprobe zfs], [:install, '/etc/modprobe.d/zfs-amahi.conf', "options zfs zfs_arc_max=2147483648\n", nil],
         [:set_arc_max, 2_147_483_648]]
      )
      File.write(meminfo, "MemTotal:        3900000 kB\n")
      expect(steps('zfs.setup', {}).last).to eq([:set_arc_max, 3_900_000 * 1024 / 2])
    end

    # ZFS keeps at least a 32nd of the memory cached and ignores a cap that isn't above it: on
    # 128 GiB that's 4 GiB, so a 2 GiB cap did nothing.
    it "caps it just above ZFS's own least on a server with more than 64 GiB" do
      meminfo = "#{dir}/meminfo"
      stub_const('AmahiHelper::MEMINFO', meminfo)
      File.write(meminfo, "MemTotal:       131000000 kB\n")
      expect(steps('zfs.setup', {}).last).to eq([:set_arc_max, (131_000_000 * 1024 / 32) + (64 * 1024**2)])
    end

    it 'sets the running value when the module is loaded, and replies with the cap ZFS uses' do
      stub_const('AmahiHelper::ZFS_ARC_MAX', "#{dir}/zfs_arc_max")
      stub_const('AmahiHelper::ARCSTATS', "#{dir}/arcstats")
      expect(helper.do_set_arc_max(5)).to eq('arc_max' => 5) # no module loaded: no figures of its own
      expect(File.exist?("#{dir}/zfs_arc_max")).to be(false)
      File.write("#{dir}/zfs_arc_max", '0')
      File.write("#{dir}/arcstats", "13 1 0x01 123 33456 1 2\nname type data\nc_min 4 1052590080\nc_max 4 2147483648\nsize 4 1024\n")
      expect(helper.do_set_arc_max(2_147_483_648)).to eq('arc_max' => 2_147_483_648)
      expect(File.read("#{dir}/zfs_arc_max")).to eq('2147483648')
      File.write("#{dir}/arcstats", "c_max 4 16842752000\n") # it kept its own
      expect(helper.do_set_arc_max(2_147_483_648)).to eq('arc_max' => 16_842_752_000)
    end
  end

  describe 'reading pools' do
    let(:healthy) do
      <<~STATUS
          pool: tank
         state: ONLINE
          scan: scrub repaired 0B in 00:00:02 with 0 errors on Sun Oct  4 00:24:01 2026
        config:

        \tNAME                                   STATE     READ WRITE CKSUM
        \ttank                                   ONLINE       0     0     0
        \t  raidz1-0                             ONLINE       0     0     0
        \t    /dev/disk/by-id/ata-SSD_1-part1    ONLINE       0     0     0
        \t    /dev/disk/by-id/ata-SSD_2-part1    ONLINE       0     0     0
        \t    /dev/disk/by-id/ata-SSD_3-part1    ONLINE       0     0     0

        errors: No known data errors
      STATUS
    end
    let(:degraded) do
      <<~STATUS
          pool: tank
         state: DEGRADED
        status: One or more devices could not be used because the label is missing or
        \tinvalid.  Sufficient replicas exist for the pool to continue
        \tfunctioning in a degraded state.
        action: Replace the device using 'zpool replace'.
           see: https://openzfs.github.io/openzfs-docs/msg/ZFS-8000-4J
          scan: resilver in progress since Sun Oct  4 10:00:00 2026
        \t1.20G / 2.40G scanned at 300M/s, 600M / 2.40G issued at 150M/s
        \t598M resilvered, 25.00% done, 00:00:12 to go
        config:

        \tNAME                                   STATE     READ WRITE CKSUM
        \ttank                                   DEGRADED     0     0     0
        \t  raidz1-0                             DEGRADED     0     0     0
        \t    /dev/disk/by-id/ata-SSD_1-part1    ONLINE       0     0     0
        \t    1234567890123456789                UNAVAIL      0     0     0  was /dev/disk/by-id/ata-SSD_2-part1
        \t    /dev/disk/by-id/ata-SSD_3-part1    ONLINE       0     0     3

        errors: No known data errors
      STATUS
    end

    before do
      allow(File).to receive(:realpath).and_call_original
      { 1 => 'sdc1', 2 => 'sdd1', 3 => 'sde1' }.each do |n, device|
        allow(File).to receive(:realpath).with("/dev/disk/by-id/ata-SSD_#{n}-part1").and_return("/dev/#{device}")
      end
    end

    it 'reads the state, last scrub, errors and the drives of a healthy pool' do
      reply = helper.parse_pool_status(healthy)
      expect(reply.slice('state', 'scan', 'errors', 'status')).to eq(
        'state' => 'ONLINE', 'scan' => 'scrub repaired 0B in 00:00:02 with 0 errors on Sun Oct  4 00:24:01 2026',
        'errors' => 'No known data errors', 'status' => nil
      )
      vdev = reply['vdevs'].sole
      expect(vdev.slice('name', 'state')).to eq('name' => 'raidz1-0', 'state' => 'ONLINE')
      expect(vdev['children'].map { |d| d['device'] }).to eq(%w[/dev/sdc1 /dev/sdd1 /dev/sde1])
      expect(vdev['children'].first).to include('name' => '/dev/disk/by-id/ata-SSD_1-part1', 'state' => 'ONLINE',
                                                'read' => '0', 'write' => '0', 'cksum' => '0', 'note' => nil)
    end

    it "reads a degraded pool's notes (joined across lines), the resilver, and the missing drive" do
      reply = helper.parse_pool_status(degraded)
      expect(reply['state']).to eq('DEGRADED')
      expect(reply['status']).to eq('One or more devices could not be used because the label is missing or invalid.  ' \
                                    'Sufficient replicas exist for the pool to continue functioning in a degraded state.')
      expect(reply['action']).to eq("Replace the device using 'zpool replace'.")
      expect(reply['scan']).to start_with('resilver in progress since Sun Oct  4 10:00:00 2026 1.20G / 2.40G scanned')
      expect(reply['scan']).to end_with('25.00% done, 00:00:12 to go')
      missing, third = reply['vdevs'].sole['children'].drop(1)
      expect(missing).to include('name' => '1234567890123456789', 'state' => 'UNAVAIL', 'note' => 'was /dev/disk/by-id/ata-SSD_2-part1')
      expect(missing).not_to have_key('device')
      expect(third).to include('device' => '/dev/sde1', 'cksum' => '3')
    end

    it 'lists the pools with their sizes, mount points and status, and which are Amahi-kai\'s' do
      allow(helper).to receive(:capture) do |argv|
        case argv
        when %w[/usr/sbin/zpool list -H -p -o name,size,allocated,free,health]
          "tank\t2980000000000\t1000\t2979999999000\tONLINE\nrpool\t1000\t10\t990\tONLINE\n"
        when %w[/usr/sbin/zfs list -H -p -o used,available,mountpoint,usedbysnapshots tank] then "1000\t2000000000000\t#{dir}/pools/tank\t300\n"
        when %w[/usr/sbin/zfs list -H -p -o used,available,mountpoint,usedbysnapshots rpool] then "10\t990\t/\t0\n"
        when %w[/usr/sbin/zfs list -H -p -t snapshot -d 1 -s creation -o name,creation,used rpool] then ''
        when %w[/usr/sbin/zfs get -H -p -o property,value amahi:snapshot-hourly,amahi:snapshot-daily rpool] then ''
        when %w[/usr/sbin/zpool status -P rpool] then healthy.gsub('tank', 'rpool')
        when %w[/usr/sbin/zfs list -H -p -t snapshot -d 1 -s creation -o name,creation,used tank]
          "tank@amahi-daily-2026-10-04-0010\t1791000000\t300\n"
        when %w[/usr/sbin/zfs get -H -p -o property,value amahi:snapshot-hourly,amahi:snapshot-daily tank]
          "amahi:snapshot-hourly\t12\namahi:snapshot-daily\t-\n"
        when %w[/usr/sbin/zpool status -P tank] then healthy
        else raise "unexpected #{argv}"
        end
      end
      pool, rpool = helper.do_pool_status['pools']
      expect(pool).to include('name' => 'tank', 'size' => 2_980_000_000_000, 'allocated' => 1000, 'free' => 2_979_999_999_000,
                              'health' => 'ONLINE', 'used' => 1000, 'available' => 2_000_000_000_000,
                              'mountpoint' => "#{dir}/pools/tank", 'managed' => true, 'state' => 'ONLINE', 'snapshot_space' => 300,
                              'snapshot_policy' => { 'hourly' => 12, 'daily' => 30 },
                              'snapshots' => [{ 'name' => 'amahi-daily-2026-10-04-0010', 'kind' => 'daily', 'created' => 1_791_000_000, 'used' => 300 }])
      expect(pool['vdevs'].sole['children'].size).to eq(3)
      expect(rpool).to include('name' => 'rpool', 'mountpoint' => '/', 'managed' => false) # a system's own: shown, never changed
    end

    # The scan of the drives for pools that aren't imported reads every drive, waking any that
    # sleep: the ZFS Pools page asks for it, the health check every 15 minutes doesn't.
    it 'scans the drives for the pools that are not imported only when asked' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool list -H -p -o name,size,allocated,free,health]).and_return('')
      found = [{ 'name' => 'tank', 'id' => '5678', 'state' => 'ONLINE', 'force' => false, 'status' => nil, 'devices' => ['/dev/sdc1'] }]
      allow(helper).to receive(:importable_pools).and_return(found)
      expect(helper.do_pool_status).to eq('zfs' => true, 'pools' => [], 'offline' => [], 'found' => found)
      expect(helper.do_pool_status(false)).to eq('zfs' => true, 'pools' => [])
      expect(helper).to have_received(:importable_pools).once
      expect(steps('pools.status', {})).to eq([[:pool_status, false]])
      expect(steps('pools.status', { 'scan' => true })).to eq([[:pool_status, true]])
    end

    it "says ZFS isn't installed, and passes on a zpool failure" do
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(false)
      expect(helper.do_pool_status).to eq('zfs' => false, 'pools' => [])
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(true)
      allow(helper).to receive(:capture).and_raise(AmahiHelper::Failed, 'zpool exited 1: The ZFS modules are not loaded.')
      expect(helper.do_pool_status).to eq('zfs' => true, 'pools' => [], 'offline' => [], 'found' => [],
                                          'error' => 'zpool exited 1: The ZFS modules are not loaded.')
    end

    it 'maps every device in an imported pool to its pool' do
      allow(helper).to receive(:pooled_devices).and_call_original
      allow(helper).to receive(:pool_names).and_return(['tank'])
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool status -P tank]).and_return(degraded)
      expect(helper.pooled_devices).to eq('/dev/sdc1' => 'tank', '/dev/sde1' => 'tank')
    end
  end

  # A share on a pool lives in the pool's shares dataset, POOL_ROOT/<pool>/shares; the pool isn't
  # taken offline or destroyed under its shares.
  describe 'SMB shares on a pool' do
    let(:root) { "#{dir}/pools/old/shares" }

    before do
      allow(File).to receive(:executable?).with('/usr/sbin/zfs').and_return(true)
      FileUtils.mkdir_p(root)
    end

    it "makes the pool's shares dataset if it has none, and checks it's mounted" do
      expect(steps('pools.shares_root', { 'name' => 'old' })).to eq([[:pool_shares_root, 'old']])
      expect(refusal('pools.shares_root', { 'name' => 'nope' })).to eq(%(there's no pool named "nope"))

      ran = []
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name old/shares]).and_raise(AmahiHelper::Failed, 'no such dataset')
      allow(helper).to receive(:run_command) { |argv| ran << argv && nil }
      allow(helper).to receive(:do_own_dir)
      allow(helper).to receive(:pool_shares_mounted?).with(root).and_return(true)
      expect(helper.do_pool_shares_root('old')).to eq('root' => root)
      expect(ran).to eq([%w[/usr/sbin/zfs create old/shares]])
      expect(helper).to have_received(:do_own_dir).with(root, 'root', 'root', '0755')

      allow(helper).to receive(:pool_shares_mounted?).with(root).and_return(false)
      expect { helper.do_pool_shares_root('old') }.to raise_error(AmahiHelper::Failed, "old/shares isn't mounted at #{root}")
    end

    it "takes a share folder in a pool's shares dataset only while that dataset is mounted there" do
      expect(refusal('shares.create_dir', { 'path' => "#{root}/photos" })).to include("a ZFS pool's shares folder")
      allow(helper).to receive(:pool_shares_mounted?).and_call_original
      allow(helper).to receive(:pool_shares_mounted?).with(root).and_return(true)
      expect(steps('shares.create_dir', { 'path' => "#{root}/photos" }))
        .to eq([[:mkdir_p, "#{root}/photos"], [:own_dir, "#{root}/photos", 'amahi', 'users', '2775']])
      # Not the pool itself, nor beside its shares folder
      expect(refusal('shares.create_dir', { 'path' => "#{dir}/pools/old/photos" })).to include("a ZFS pool's shares folder")
      expect(refusal('shares.create_dir', { 'path' => "#{dir}/pools/old/shares" })).to include("a ZFS pool's shares folder")
    end

    it "reads whether a pool's shares dataset is mounted from the mounts list" do
      mounts = "#{dir}/mounts"
      File.write(mounts, "old /srv/x zfs rw 0 0\nold/shares #{root} zfs rw,nosuid,nodev 0 0\nold/other #{dir}/pools/old/other zfs rw 0 0\n")
      expect(helper.pool_shares_mounted?(root, mounts)).to be true
      File.write(mounts, "/dev/sdb1 #{root} ext4 rw 0 0\n")
      expect(helper.pool_shares_mounted?(root, mounts)).to be false
      expect(helper.pool_shares_mounted?("#{dir}/pools/old/other", mounts)).to be false
    end

    it "lets Samba's config name a share folder on a pool" do
      expect(helper.config_share_path?("#{dir}/pools/old/shares/photos")).to be true
      expect(helper.config_share_path?("#{dir}/pools/old/photos")).to be false
      expect(helper.config_share_path?("#{dir}/pools/old/shares")).to be false
    end

    it "won't take a pool offline or destroy it while shares are on it" do
      allow(helper).to receive(:samba_shares).and_return(
        'photos' => { name: 'Photos', path: "#{root}/photos", pooled: false },
        'docs' => { name: 'Docs', path: "#{root}/docs", pooled: false },
        'music' => { name: 'Music', path: '/var/lib/amahi-kai/files/music', pooled: true }
      )
      expect(refusal('pools.export', { 'name' => 'old' })).to eq('the shares Docs, Photos are on old: delete them on Shares first')
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to eq('the shares Docs, Photos are on old: delete them on Shares first')
    end
  end

  # Taking a pool offline or destroying it unmounts it: the Samba sessions holding it end first,
  # and anything else holding it is named.
  describe 'releasing a pool' do
    let(:root) { "#{dir}/pools/old" }

    it "ends the Samba sessions holding the pool, asked first, and names anything else" do
      allow(helper).to receive(:pause)
      allow(helper).to receive(:signal_process)
      session = { pid: 4242, comm: 'smbd', ppid: 900 }
      allow(helper).to receive(:pool_holders).with(root).and_return([session], [])
      allow(helper).to receive(:process_alive?).with(4242).and_return(true, false)
      expect(helper.do_release_pool('old')).to be_nil
      expect(helper).to have_received(:signal_process).with(4242, 'TERM').once
      expect(helper).not_to have_received(:signal_process).with(4242, 'KILL')

      # Samba's own smbd (its parent is init) and a shell are named, not ended
      allow(helper).to receive(:pool_holders).with(root).and_return([{ pid: 1, comm: 'smbd', ppid: 1 }, { pid: 77, comm: 'bash', ppid: 70 }])
      expect { helper.do_release_pool('old') }.to raise_error(AmahiHelper::Failed, 'old is in use by smbd (process 1), bash (process 77): stop them first')
      expect(helper).not_to have_received(:signal_process).with(1, anything)
    end

    it "finds the processes with a folder or file open on the pool" do
      Dir.mktmpdir do |procs|
        FileUtils.mkdir_p(root)
        { 10 => ["#{root}/shares/vault", nil, 'smbd', 900], 11 => ['/', "#{root}/shares/vault/a.jpg", 'smbd', 900],
          12 => ['/home/casey', '/var/log/x', 'bash', 70], 13 => [root, nil, 'cool) prog', 5] }.each do |pid, (cwd, file, comm, ppid)|
          FileUtils.mkdir_p("#{procs}/#{pid}/fd")
          File.symlink(cwd, "#{procs}/#{pid}/cwd")
          File.symlink(file, "#{procs}/#{pid}/fd/3") if file
          File.write("#{procs}/#{pid}/comm", "#{comm}\n")
          File.write("#{procs}/#{pid}/stat", "#{pid} (#{comm}) S #{ppid} 1 1 0")
        end
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob).with('/proc/[0-9]*').and_return(Dir.glob("#{procs}/*").sort)
        expect(helper.pool_holders(root)).to eq([{ pid: 10, comm: 'smbd', ppid: 900 }, { pid: 11, comm: 'smbd', ppid: 900 },
                                                 { pid: 13, comm: 'cool) prog', ppid: 5 }])
      end
    end

    it "is done before the pool is taken offline" do
      allow(helper).to receive(:do_release_pool).with('old').and_raise(AmahiHelper::Failed, 'old is in use by bash (process 77): stop it first')
      allow(helper).to receive(:capture)
      expect { helper.do_export_pool('old', '1') }.to raise_error(AmahiHelper::Failed, /in use by bash/)
      expect(helper).not_to have_received(:capture).with(%w[/usr/sbin/zpool export old])
    end
  end

  describe 'taking a pool offline, and uninstalling ZFS' do
    let(:offline_file) { "#{dir}/offline-pools.json" }

    before do
      stub_const('AmahiHelper::OFFLINE_POOLS', offline_file)
      allow(helper).to receive(:do_install) { |target, content, *| File.write(target, content) }
    end

    it 'takes an existing pool offline, recording its GUID, and only brings back pools it recorded' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool get -H -o value guid old]).and_return("987654321\n")
      expect(steps('pools.export', { 'name' => 'old' })).to eq([[:export_pool, 'old', '987654321'], [:pool_status]])
      expect(refusal('pools.export', { 'name' => 'nope' })).to eq(%(there's no pool named "nope"))

      expect(refusal('pools.import', { 'name' => 'away' })).to eq(%("away" isn't a pool taken offline here))
      File.write(offline_file, { 'away' => '1234', 'junk' => 'x' }.to_json)
      expect(steps('pools.import', { 'name' => 'away' })).to eq(
        [[:make_dir, "#{dir}/pools", '0755'], [:import_pool, 'away', '1234'], [:pool_status]]
      )
      expect(refusal('pools.import', { 'name' => 'junk' })).to eq(%("junk" isn't a pool taken offline here))
      allow(helper).to receive(:pool_names).and_return(['away'])
      expect(refusal('pools.import', { 'name' => 'away' })).to eq('a pool named away is already online')
    end

    it 'refuses to take a pool offline over the record of another one by its name' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool get -H -o value guid old]).and_return("987654321\n")
      File.write(offline_file, { 'old' => '1111' }.to_json)
      expect(refusal('pools.export', { 'name' => 'old' }))
        .to eq('another pool named old is offline here already; rename one of them from the command line first')
      File.write(offline_file, { 'old' => '987654321' }.to_json) # its own record, left by a run that stopped
      expect(steps('pools.export', { 'name' => 'old' })).to eq([[:export_pool, 'old', '987654321'], [:pool_status]])
    end

    it 'records the pool after exporting it, and forgets it once imported' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool export old]).and_return('')
      helper.do_export_pool('old', '987654321')
      expect(helper.offline_records).to eq('old' => '987654321')
      allow(helper).to receive(:capture).with(['/usr/sbin/zpool', 'import', '-d', '/dev/disk/by-id', '987654321']).and_return('')
      helper.do_import_pool('old', '987654321')
      expect(helper.offline_records).to eq({})
    end

    it "keeps an offline pool's drives out of new pools" do
      allow(helper).to receive(:offline_devices).and_return('/dev/sdd' => 'away')
      expect(refusal('pools.create', { 'name' => 'tank', 'layout' => 'mirror', 'devices' => %w[/dev/sdd /dev/sde] }))
        .to eq('/dev/sdd is in the pool away, which is offline; bring it online on Disks → ZFS Pools, or delete it there')
    end

    it 'finds the offline pools on the drives, by their by-id names' do
      by_id = "#{dir}/by-id"
      Dir.mkdir(by_id)
      File.symlink('/dev/null', "#{by_id}/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2-part1")
      File.symlink('/dev/zero', "#{by_id}/scsi-0QEMU_QEMU_HARDDISK_drive-scsi4-part1")
      stub_const('AmahiHelper::BY_ID', by_id)
      scan = <<~SCAN
           pool: away
             id: 1234
          state: ONLINE
         action: The pool can be imported using its name or numeric identifier.
         config:

        \taway                                            ONLINE
        \t  mirror-0                                      ONLINE
        \t    scsi-0QEMU_QEMU_HARDDISK_drive-scsi2-part1  ONLINE
        \t    scsi-0QEMU_QEMU_HARDDISK_drive-scsi4-part1  ONLINE
        \t    scsi-0QEMU_QEMU_HARDDISK_drive-scsi9-part1  UNAVAIL
      SCAN
      expect(helper.parse_importable(scan)).to eq([{ 'name' => 'away', 'id' => '1234', 'state' => 'ONLINE', 'force' => false, 'status' => nil,
                                                     'devices' => %w[/dev/null /dev/zero] }])
      File.write(offline_file, { 'away' => '1234', 'gone' => '99' }.to_json)
      allow(helper).to receive(:pool_names).and_return([])
      allow(helper).to receive(:importable_pools).and_return(helper.parse_importable(scan))
      expect(helper.offline_pools).to eq([{ 'name' => 'away', 'state' => 'ONLINE', 'devices' => %w[/dev/null /dev/zero] },
                                          { 'name' => 'gone', 'state' => 'MISSING', 'devices' => [] }])
    end

    it 'reads a pool last used by another system, which ZFS imports only with -f' do
      scan = <<~SCAN
           pool: tank
             id: 5678
          state: ONLINE
         status: The pool was last accessed by another system.
         action: The pool can be imported using its name or numeric identifier and
        	the '-f' flag.
            see: https://openzfs.github.io/openzfs-docs/msg/ZFS-8000-EY
         config:

        	tank        ONLINE
        	  mirror-0  ONLINE
      SCAN
      expect(helper.parse_importable(scan).sole).to include('name' => 'tank', 'id' => '5678', 'force' => true,
                                                            'status' => 'The pool was last accessed by another system.')
    end

    describe 'a pool found on the drives' do
      # tank: this server's from before it was installed again (ZFS asks for -f), on sdi; away: taken
      # offline here (its record), so not "found"; part: too few of its drives connected.
      let(:scan) do
        [{ 'name' => 'tank', 'id' => '5678', 'state' => 'ONLINE', 'force' => true, 'status' => 'The pool was last accessed by another system.',
           'devices' => ['/dev/sdi1'] },
         { 'name' => 'away', 'id' => '1234', 'state' => 'ONLINE', 'force' => false, 'status' => nil, 'devices' => ['/dev/sdd'] },
         { 'name' => 'part', 'id' => '42', 'state' => 'UNAVAIL', 'force' => false, 'status' => nil, 'devices' => ['/dev/sde1'] }]
      end
      let(:ran) { [] }

      before do
        File.write(offline_file, { 'away' => '1234' }.to_json)
        allow(helper).to receive(:importable_pools).and_return(scan)
        allow(helper).to receive(:run_command) { |argv| ran << argv }
        sdi = { 'path' => '/dev/sdi', 'type' => 'disk', 'mountpoints' => [nil],
                'children' => [{ 'path' => '/dev/sdi1', 'type' => 'part', 'fstype' => 'zfs_member', 'label' => 'tank', 'mountpoints' => [nil] },
                               { 'path' => '/dev/sdi9', 'type' => 'part', 'mountpoints' => [nil] }] }
        allow(helper).to receive(:block_tree).and_return(tree + [sdi])
      end

      it 'is listed apart from the ones taken offline here' do
        expect(helper.found_pools.map { |pool| pool['name'] }).to eq(%w[tank part])
        expect(helper.found_devices).to eq('/dev/sdi1' => 'tank', '/dev/sde1' => 'part')
        expect(helper.offline_devices).to eq('/dev/sdd' => 'away')
      end

      it 'is imported by its id, under its own name, only while ZFS finds enough of its drives' do
        expect(steps('pools.import_found', { 'id' => '5678' })).to eq(
          [[:make_dir, "#{dir}/pools", '0755'], [:import_found_pool, 'tank', '5678', true], [:pool_status]]
        )
        found = ->(id) { refusal('pools.import_found', { 'id' => id }) }
        expect(found.call('42')).to eq('ZFS finds part UNAVAIL: connect its missing drives first')
        expect(found.call('1234')).to eq('no pool with the id 1234 is on the drives, not imported') # offline: Bring online
        expect(found.call('99')).to eq('no pool with the id 99 is on the drives, not imported')
        expect(found.call('5678; reboot')).to include("isn't a pool's id")
        allow(helper).to receive(:pool_names).and_return(%w[old tank])
        expect(found.call('5678')).to eq('a pool named tank is already imported here')
        allow(helper).to receive(:pool_names).and_return(['old'])
        FileUtils.mkdir_p("#{dir}/pools/tank/stuff")
        expect(found.call('5678')).to include('is in the way')
        scan.first['name'] = 'Tank'
        expect(found.call('5678')).to include("isn't one Amahi-kai gives pools")
      end

      def datasets(lines)
        allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name,mountpoint,canmount,setuid,devices -r -t filesystem tank])
                                          .and_return(lines.map { |fields| "#{fields.join("\t")}\n" }.join)
      end

      it "imports it with nothing mounted, then mounts it if everything of it mounts in its own folder" do
        allow(helper).to receive(:capture).with(['/usr/sbin/zpool', 'import', '-N', '-f', '-d', '/dev/disk/by-id', '5678']).and_return('')
        datasets([['tank', "#{dir}/pools/tank", 'on', 'off', 'off'], ['tank/shares', "#{dir}/pools/tank/shares", 'on', 'on', 'off'],
                  ['tank/apps', 'none', 'on', 'off', 'off']])
        helper.do_import_found_pool('tank', '5678', true)
        expect(ran).to eq([%w[/usr/sbin/zfs set setuid=off devices=off tank/shares], %w[/usr/sbin/zfs mount -a]])
      end

      it "exports it again, as it was, when it isn't Amahi-kai's" do
        allow(helper).to receive(:capture).with(['/usr/sbin/zpool', 'import', '-N', '-d', '/dev/disk/by-id', '5678']).and_return('')
        datasets([['tank', "#{dir}/pools/tank", 'on', 'off', 'off'], ['tank/root', '/', 'on', 'off', 'off']])
        expect { helper.do_import_found_pool('tank', '5678', false) }.to raise_error(
          AmahiHelper::Failed, "tank isn't one of Amahi-kai's pools (tank/root mounts at /), so it's left on its drives, not imported: import it from the command line"
        )
        expect(ran).to eq([['/usr/sbin/zpool', 'export', 'tank', { allow_failure: true }]])
        ran.clear
        datasets([['tank', '/data', 'on', 'off', 'off']])
        expect { helper.do_import_found_pool('tank', '5678', false) }.to raise_error(AmahiHelper::Failed, /tank mounts at \/data/)
        ran.clear
        datasets([['tank', "#{dir}/pools/tank", 'off', 'off', 'off'], ['tank/x', '/x', 'noauto', 'off', 'off']]) # noauto can still be mounted
        expect { helper.do_import_found_pool('tank', '5678', false) }.to raise_error(AmahiHelper::Failed, %r{tank/x mounts at /x})
        ran.clear
        datasets([['tank', '/', 'off', 'off', 'off']]) # not mounted itself, but not in its own folder: not Amahi-kai's
        expect { helper.do_import_found_pool('tank', '5678', false) }.to raise_error(AmahiHelper::Failed, %r{tank mounts at /\)})
        datasets([['tank', "#{dir}/pools/tank", 'on', 'off', 'off'], ['tank/old', 'legacy', 'on', 'off', 'off'],
                  ['tank/off', '/elsewhere', 'off', 'off', 'off']]) # neither is mounted by ZFS
        expect { helper.do_import_found_pool('tank', '5678', false) }.not_to raise_error
      end

      it "keeps its drives for it: Erase needs the pool's name typed" do
        expect(refusal('pools.erase_drive', { 'device' => '/dev/sdi' })).to eq("type the pool's name (tank) to erase /dev/sdi")
        expect(refusal('pools.erase_drive', { 'device' => '/dev/sdi', 'confirm' => 'TANK' })).to eq("type the pool's name (tank) to erase /dev/sdi")
        expect(steps('pools.erase_drive', { 'device' => '/dev/sdi', 'confirm' => 'tank' }).first)
          .to eq(['/usr/sbin/zpool', 'labelclear', '-f', '/dev/sdi1', { allow_failure: true }])
        expect(refusal('pools.erase_drive', { 'device' => '/dev/sdd', 'confirm' => 'away' })).to include('which is offline')
      end
    end

    it 'uninstalls ZFS only when no pool is left, online or offline' do
      expect(refusal('zfs.uninstall', {})).to eq('the pool old is still here; delete it on Disks → ZFS Pools first')
      allow(helper).to receive(:pool_names).and_return([])
      File.write(offline_file, { 'away' => '1234' }.to_json)
      expect(refusal('zfs.uninstall', {})).to eq('the pool away is offline; bring it online and delete it first')
      File.write(offline_file, '{}')
      expect(steps('zfs.uninstall', {})).to eq(
        [['/usr/bin/apt-get', '-y', '-o', 'DPkg::Lock::Timeout=300', 'purge', 'zfsutils-linux', 'zfs-zed',
          { env: AmahiHelper::APT_ENV, stream: true }],
         [:remove_files, '/etc/modprobe.d/zfs-amahi.conf', offline_file],
         ['/usr/sbin/modprobe', '-r', 'zfs', { allow_failure: true }]]
      )
    end

    it 'removes only the files a plan names' do
      File.write("#{dir}/a", 'x')
      helper.do_remove_files("#{dir}/a", "#{dir}/not-there")
      expect(File.exist?("#{dir}/a")).to be(false)
    end
  end

  describe 'managing a pool' do
    # The pool "old": a 3-drive RAIDZ1 with one drive missing. Its drive on sdh is in the tree.
    let(:status) do
      <<~STATUS
          pool: old
         state: DEGRADED
        config:

        \tNAME                                   STATE     READ WRITE CKSUM
        \told                                    DEGRADED     0     0     0
        \t  raidz1-0                             DEGRADED     0     0     0
        \t    /dev/disk/by-id/ata-SSD_8-part1    ONLINE       0     0     0
        \t    1234567890123456789                UNAVAIL      0     0     0  was /dev/disk/by-id/ata-SSD_7-part1
        \t    /dev/disk/by-id/ata-SSD_9-part1    ONLINE       0     0     0

        errors: No known data errors
      STATUS
    end

    before do
      allow(helper).to receive(:capture).and_call_original
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool status -P old]).and_return(status)
      allow(File).to receive(:realpath).and_call_original
      allow(File).to receive(:realpath).with('/dev/disk/by-id/ata-SSD_8-part1').and_return('/dev/sdh1')
      allow(File).to receive(:realpath).with('/dev/disk/by-id/ata-SSD_9-part1').and_return('/dev/sdz1')
    end

    it 'replaces a drive, missing or not, with a free whole disk' do
      expect(steps('pools.replace', { 'name' => 'old', 'old' => '1234567890123456789', 'new' => '/dev/sdd' })).to eq(
        [%w[/usr/sbin/wipefs -a /dev/sdd], ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         ['/usr/sbin/zpool', 'replace', 'old', '1234567890123456789', '/dev/disk/by-id/ata-SSD_sdd'], [:pool_status]]
      )
      expect(steps('pools.replace', { 'name' => 'old', 'old' => '/dev/disk/by-id/ata-SSD_8-part1', 'new' => '/dev/sdc' }).first(2))
        .to eq([%w[/usr/sbin/wipefs -a /dev/sdc1], %w[/usr/sbin/wipefs -a /dev/sdc]])
    end

    it "brings back a drive ZFS took out once it's connected again, and only then" do
      removed = status.sub("ata-SSD_9-part1    ONLINE ", "ata-SSD_9-part1    REMOVED")
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool status -P old]).and_return(removed)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/dev/disk/by-id/ata-SSD_9-part1').and_return(true)
      expect(steps('pools.online_drive', { 'name' => 'old', 'drive' => '/dev/disk/by-id/ata-SSD_9-part1' }))
        .to eq([['/usr/sbin/zpool', 'online', 'old', '/dev/disk/by-id/ata-SSD_9-part1'], [:pool_status]])
      # A whole disk ZFS partitioned (-part1 and -part9): zpool online gets the disk, whose size it
      # reads to grow the drive with autoexpand on
      allow(File).to receive(:exist?).with('/dev/disk/by-id/ata-SSD_9').and_return(true)
      allow(File).to receive(:exist?).with('/dev/disk/by-id/ata-SSD_9-part9').and_return(true)
      expect(steps('pools.online_drive', { 'name' => 'old', 'drive' => '/dev/disk/by-id/ata-SSD_9-part1' }).first)
        .to eq(['/usr/sbin/zpool', 'online', 'old', '/dev/disk/by-id/ata-SSD_9'])
      allow(File).to receive(:exist?).with('/dev/disk/by-id/ata-SSD_9').and_return(false)

      online = ->(drive) { refusal('pools.online_drive', { 'name' => 'old', 'drive' => drive }) }
      expect(online.call('/dev/disk/by-id/ata-SSD_8-part1')).to eq('/dev/disk/by-id/ata-SSD_8-part1 is ONLINE, in the pool already')
      expect(online.call('1234567890123456789')).to eq("1234567890123456789 isn't connected: connect it again, or replace it")
      expect(online.call('/dev/sdc1')).to eq(%("/dev/sdc1" isn't a drive in the pool old))
      allow(File).to receive(:exist?).with('/dev/disk/by-id/ata-SSD_9-part1').and_return(false)
      expect(online.call('/dev/disk/by-id/ata-SSD_9-part1')).to include("isn't connected")
      expect(refusal('pools.online_drive', { 'name' => 'nope', 'drive' => '/dev/disk/by-id/ata-SSD_9-part1' })).to eq(%(there's no pool named "nope"))
    end

    it "erases the old ZFS label on a free disk, and only on one" do
      left = { 'path' => '/dev/sdi', 'type' => 'disk', 'mountpoints' => [nil],
               'children' => [{ 'path' => '/dev/sdi1', 'type' => 'part', 'fstype' => 'zfs_member', 'label' => 'old', 'mountpoints' => [nil] },
                              { 'path' => '/dev/sdi9', 'type' => 'part', 'mountpoints' => [nil] }] }
      allow(helper).to receive(:block_tree).and_return(tree + [left])
      expect(steps('pools.erase_drive', { 'device' => '/dev/sdi' })).to eq(
        [['/usr/sbin/zpool', 'labelclear', '-f', '/dev/sdi1', { allow_failure: true }],
         %w[/usr/sbin/wipefs -a /dev/sdi1], %w[/usr/sbin/wipefs -a /dev/sdi9], %w[/usr/sbin/wipefs -a /dev/sdi],
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }], [:pool_status]]
      )
      erase = ->(device) { refusal('pools.erase_drive', { 'device' => device }) }
      expect(erase.call('/dev/sdh')).to eq('/dev/sdh is in the pool old')
      expect(erase.call('/dev/sdd')).to eq('/dev/sdd has no ZFS label to erase')
      expect(erase.call('/dev/sda')).to include('a disk the system uses')
      expect(erase.call('/dev/sdg')).to include('which is in use')
      expect(erase.call('/dev/sdi1')).to eq('"/dev/sdi1" is not a whole disk')
      allow(helper).to receive(:offline_devices).and_return('/dev/sdi1' => 'away')
      expect(erase.call('/dev/sdi')).to include('is in the pool away, which is offline')
    end

    it "refuses a drive that isn't in the pool, and a new one that isn't free" do
      replace = ->(old, new) { refusal('pools.replace', { 'name' => 'old', 'old' => old, 'new' => new }) }
      expect(replace.call('/dev/sdc1', '/dev/sdd')).to eq('"/dev/sdc1" isn\'t a drive in the pool old')
      expect(replace.call('1234567890123456789', '/dev/sdb')).to include('unmount it first')
      expect(replace.call('1234567890123456789', '/dev/sdh')).to eq('/dev/sdh is in the pool old')
      expect(replace.call('1234567890123456789', '/dev/sda')).to include('a disk the system uses')
      expect(refusal('pools.replace', { 'name' => 'tank', 'old' => 'x', 'new' => '/dev/sdd' })).to include("there's no pool named")
    end

    it "adds a group shaped like the pool's: same layout, same number of drives" do
      expect(steps('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sde] })).to eq(
        [%w[/usr/sbin/wipefs -a /dev/sdc1], %w[/usr/sbin/wipefs -a /dev/sdc], %w[/usr/sbin/wipefs -a /dev/sdd],
         %w[/usr/sbin/wipefs -a /dev/sde], ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         ['/usr/sbin/zpool', 'add', '-o', 'ashift=12', 'old', 'raidz1',
          '/dev/disk/by-id/ata-SSD_sdc', '/dev/disk/by-id/ata-SSD_sdd', '/dev/disk/by-id/ata-SSD_sde'],
         [:pool_status]]
      )
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd] }))
        .to eq('a new raidz1 group in old needs 3 drives, like the others')
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sdd] })).to eq('/dev/sdd is listed twice')
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sdb] })).to include('unmount it first')
    end

    it "won't add to a pool whose groups don't match" do
      mixed = status.sub("\t  raidz1-0 ", "\t  mirror-0 ").sub("\nerrors:", "\t  raidz1-1  ONLINE 0 0 0\n\t    /dev/sdq1  ONLINE 0 0 0\n\nerrors:")
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool status -P old]).and_return(mixed)
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sde] })).to include("isn't made of matching")
    end

    it "won't take a pool offline or delete it under an installed app's data, and forgets the data an uninstalled one kept" do
      File.write("#{dir}/app-storage.json", { 'store' => 'old', 'gone' => 'old', 'other' => 'tank' }.to_json)
      allow(helper).to receive(:app_image) { |id| id == 'store' ? "example/store:1@sha256:#{'a' * 64}" : nil }
      why = "store keeps its data on old, so it can't be %s: uninstall it on Apps first (the data stays on the pool unless you delete it)"
      expect(refusal('pools.export', { 'name' => 'old' })).to eq(format(why, 'taken offline'))
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to eq(format(why, 'deleted'))

      allow(helper).to receive(:app_image).and_return(nil) # store uninstalled too, its data kept
      expect(steps('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to include([:forget_app_storage, %w[gone store]])
      allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
      helper.do_forget_app_storage(%w[gone store])
      expect(JSON.parse(File.read("#{dir}/app-storage.json"))).to eq('other' => 'tank')
    end

    it "won't take a pool offline or delete it while an app's container has a folder on it mounted, and names the app" do
      id = 'b' * 64
      allow(helper).to receive(:system_peer_groups).and_return(%w[45])
      allow(helper).to receive(:container_names).and_return(id => 'amahi-bitshare')
      # the share Vault, given to bitShare and deleted since: its folder is still bound in the container
      container = { mountinfo: "700 650 0:52 /vault /shares/Vault rw,relatime - zfs old/shares rw,xattr\n",
                    cgroup: "0::/system.slice/docker-#{id}.scope\n", comm: 'bitshare-server' }
      # a service systemd sandboxes sees the pool too, but its copy follows the system's mount
      service = { mountinfo: "180 111 0:52 / /srv/pools/old/shares rw shared:90 master:45 - zfs old/shares rw\n",
                  cgroup: "0::/system.slice/systemd-logind.service\n", comm: 'systemd-logind' }
      other = { mountinfo: "701 650 0:60 / /data rw - zfs tank/apps/x rw\n", cgroup: "0::/x\n", comm: 'x' }
      allow(helper).to receive(:other_mount_views).and_return([container, service, other])
      why = 'old is still in use by the app bitshare, which has folders on it mounted: stop it on Apps, then %s'
      expect(refusal('pools.export', { 'name' => 'old' })).to eq(format(why, 'take it offline'))
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to eq(format(why, 'delete it'))

      allow(helper).to receive(:other_mount_views).and_return([service, other])
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to be_nil
      expect(helper.pool_mount_holders('tank')).to eq(['x']) # no container by that id: its program
      expect(helper.pool_mount_holders('ol')).to eq([])
    end

    it "changes only Amahi-kai's pools: one mounted elsewhere (a system's rpool) is refused" do
      allow(helper).to receive(:pool_mountpoint).with('old').and_return('/')
      why = "old isn't one of Amahi-kai's pools (it mounts at /); manage it from the command line"
      expect(refusal('pools.export', { 'name' => 'old' })).to eq(why)
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to eq(why)
      expect(refusal('pools.scrub', { 'name' => 'old' })).to eq(why)
      expect(refusal('pools.snapshot', { 'name' => 'old' })).to eq(why)
      expect(refusal('pools.snapshot_policy', { 'name' => 'old', 'hourly' => 1, 'daily' => 1 })).to eq(why)
      expect(refusal('pools.rollback', { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-04-0010', 'confirm' => 'old' })).to eq(why)
      expect(refusal('pools.replace', { 'name' => 'old', 'old' => '1234567890123456789', 'new' => '/dev/sdd' })).to eq(why)
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sde] })).to eq(why)
      allow(File).to receive(:executable?).with('/usr/sbin/zfs').and_return(true)
      expect(refusal('pools.shares_root', { 'name' => 'old' })).to eq(why)
    end

    # A pool whose drives are failing may not tell ZFS where it mounts: its folder in POOL_ROOT
    # says it's Amahi-kai's, so Replace and Delete still work on it.
    it "takes a pool whose mount point ZFS can't read as Amahi-kai's when its folder is in the pools' folder" do
      allow(helper).to receive(:pool_mountpoint).and_call_original
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs get -H -o value mountpoint old]).and_raise(AmahiHelper::Failed, 'zfs exited 1: I/O error')
      expect(refusal('pools.scrub', { 'name' => 'old' }))
        .to eq("old isn't one of Amahi-kai's pools (ZFS can't say where it mounts); manage it from the command line")
      FileUtils.mkdir_p("#{dir}/pools/old")
      expect(steps('pools.scrub', { 'name' => 'old' })).to eq([%w[/usr/sbin/zpool scrub old]])
    end

    it "keeps a pool found on the drives out of a new group, and out of Replace" do
      allow(helper).to receive(:importable_pools).and_return([{ 'name' => 'tank', 'id' => '5678', 'state' => 'ONLINE', 'force' => false,
                                                                 'status' => nil, 'devices' => ['/dev/sdd'] }])
      expect(refusal('pools.add_group', { 'name' => 'old', 'devices' => %w[/dev/sdc /dev/sdd /dev/sde] })).to include('/dev/sdd holds the pool tank')
      expect(refusal('pools.replace', { 'name' => 'old', 'old' => '1234567890123456789', 'new' => '/dev/sdd' })).to include('/dev/sdd holds the pool tank')
    end

    it 'destroys a pool only when its name is typed again, then frees its drives' do
      expect(refusal('pools.destroy', { 'name' => 'old', 'confirm' => 'OLD' })).to eq("type the pool's name (old) to destroy it")
      expect(steps('pools.destroy', { 'name' => 'old', 'confirm' => 'old' })).to eq(
        [[:release_pool, 'old'], # SMB sessions holding it end first
         %w[/usr/sbin/zpool destroy old],
         ['/usr/sbin/zpool', 'labelclear', '-f', '/dev/sdh1', { allow_failure: true }],
         ['/usr/sbin/zpool', 'labelclear', '-f', '/dev/sdz1', { allow_failure: true }],
         ['/usr/sbin/wipefs', '-a', '/dev/sdh1', { allow_failure: true }],
         ['/usr/sbin/wipefs', '-a', '/dev/sdh9', { allow_failure: true }],
         ['/usr/sbin/wipefs', '-a', '/dev/sdh', { allow_failure: true }],
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [:remove_pool_dir, 'old'], [:forget_app_storage, []], [:pool_status]]
      )
    end

    # A pool on a partition beside others (a system's bpool, beside its EFI partition and rpool)
    # took the whole disk with it.
    it 'wipes a whole disk with the pool only when all of it was the pool\'s' do
      shared = { 'path' => '/dev/sdh', 'type' => 'disk', 'mountpoints' => [nil],
                 'children' => [{ 'path' => '/dev/sdh1', 'type' => 'part', 'fstype' => 'zfs_member', 'mountpoints' => [nil] },
                                { 'path' => '/dev/sdh2', 'type' => 'part', 'fstype' => 'vfat', 'mountpoints' => [nil] }] }
      allow(helper).to receive(:block_tree).and_return(tree.reject { |disk| disk['path'] == '/dev/sdh' } + [shared])
      wiped = steps('pools.destroy', { 'name' => 'old', 'confirm' => 'old' }).select { |step| step[0] == '/usr/sbin/wipefs' }.map { |step| step[2] }
      expect(wiped).to eq(['/dev/sdh1']) # the EFI partition beside it stays
    end

    it "removes the pool's mount point only when it's an empty folder" do
      Dir.mkdir("#{dir}/pools")
      Dir.mkdir("#{dir}/pools/old")
      helper.do_remove_pool_dir('old')
      expect(File.exist?("#{dir}/pools/old")).to be(false)
      FileUtils.mkdir_p("#{dir}/pools/kept/data")
      helper.do_remove_pool_dir('kept')
      expect(File.exist?("#{dir}/pools/kept/data")).to be(true)
    end
  end

  describe 'snapshots' do
    let(:now) { Time.utc(2026, 10, 5, 14, 5) } # names are in UTC
    let(:list_cmd) { %w[/usr/sbin/zfs list -H -p -t snapshot -d 1 -s creation -o name,creation,used old] }
    let(:get_cmd) { %w[/usr/sbin/zfs get -H -p -o property,value amahi:snapshot-hourly,amahi:snapshot-daily old] }
    let(:snapshots) do
      [['amahi-manual-2026-10-01-101500', now - (4 * 86_400)], ['amahi-daily-2026-10-03-0010', now - (2 * 86_400)],
       ['my-own', now - 86_500], ['amahi-daily-2026-10-04-0010', now - 86_400],
       ['amahi-hourly-2026-10-05-1305', now - 3600], ['amahi-hourly-2026-10-05-1345', now - 1200]]
    end
    let(:policy) { "amahi:snapshot-hourly\t1\namahi:snapshot-daily\t-\n" }
    let(:ran) { [] }

    before do
      allow(helper).to receive(:capture).and_call_original
      allow(helper).to receive(:capture).with(list_cmd) { snapshots.map { |name, at| "old@#{name}\t#{at.to_i}\t100\n" }.join }
      allow(helper).to receive(:capture).with(get_cmd) { policy }
      allow(helper).to receive(:run_command) { |argv| ran << argv }
    end

    it "lists a pool's snapshots with their kind (nil for ones Amahi-kai didn't take), and its policy" do
      expect(helper.pool_snapshots('old').map { |snap| [snap['name'], snap['kind']] }).to eq(
        [['amahi-manual-2026-10-01-101500', 'manual'], ['amahi-daily-2026-10-03-0010', 'daily'], ['my-own', nil],
         ['amahi-daily-2026-10-04-0010', 'daily'], ['amahi-hourly-2026-10-05-1305', 'hourly'], ['amahi-hourly-2026-10-05-1345', 'hourly']]
      )
      expect(helper.snapshot_policy('old')).to eq('hourly' => 1, 'daily' => 30)
      policy.replace("amahi:snapshot-hourly\t999\namahi:snapshot-daily\tjunk\n")
      expect(helper.snapshot_policy('old')).to eq('hourly' => 168, 'daily' => 30)
    end

    it 'takes a snapshot now, kept until deleted, named in UTC' do
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 5, 4, 32, 1, '-10:00'))
      expect(steps('pools.snapshot', { 'name' => 'old' })).to eq([%w[/usr/sbin/zfs snapshot -r old@amahi-manual-2026-10-05-143201], [:pool_status]])
    end

    # Where the clocks go back, an hour's local times come twice: in the server's time, the
    # second hourly snapshot was named like the first, and zfs refused it.
    it 'names the hourly snapshots in UTC, so the hour the clocks go back gets names of its own' do
      snapshots.replace([])
      first = Time.new(2026, 11, 1, 1, 30, 0, '-04:00') # 01:30 summer time
      helper.do_run_snapshots(first)
      helper.do_run_snapshots(Time.new(2026, 11, 1, 1, 30, 0, '-05:00')) # 01:30 again, an hour later
      expect(ran.map(&:last).grep(/hourly/)).to eq(%w[old@amahi-hourly-2026-11-01-0530 old@amahi-hourly-2026-11-01-0630])
    end

    it "takes no snapshots of a pool that isn't Amahi-kai's (a system's rpool)" do
      allow(helper).to receive(:pool_mountpoint).with('old').and_return('/')
      expect(helper.do_run_snapshots(now)).to eq('pools' => [])
      expect(ran).to eq([])
    end

    it 'sets how many snapshots a pool keeps, and prunes at once' do
      expect(steps('pools.snapshot_policy', { 'name' => 'old', 'hourly' => 0, 'daily' => 7 })).to eq(
        [%w[/usr/sbin/zfs set amahi:snapshot-hourly=0 amahi:snapshot-daily=7 old], [:prune_snapshots, 'old'], [:pool_status]]
      )
      [200, -1, '5', 2.5].each do |bad|
        expect(refusal('pools.snapshot_policy', { 'name' => 'old', 'hourly' => bad, 'daily' => 7 })).to include('whole number from 0 to 168'), bad.inspect
      end
      expect(refusal('pools.snapshot_policy', { 'name' => 'old', 'hourly' => 1, 'daily' => 400 })).to include('from 0 to 366')
    end

    it "deletes and rolls back only Amahi-kai's snapshots that exist, rollback behind the pool's name" do
      expect(steps('pools.destroy_snapshot', { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-03-0010' }))
        .to eq([%w[/usr/sbin/zfs destroy -r old@amahi-daily-2026-10-03-0010], [:pool_status]])
      expect(refusal('pools.destroy_snapshot', { 'name' => 'old', 'snapshot' => 'my-own' })).to eq('"my-own" isn\'t one of Amahi-kai\'s snapshots')
      expect(refusal('pools.destroy_snapshot', { 'name' => 'old', 'snapshot' => 'amahi-daily-2020-01-01-0000' }))
        .to eq('the pool old has no snapshot amahi-daily-2020-01-01-0000')
      expect(refusal('pools.destroy_snapshot', { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-03-0010; rm' })).to include("isn't one of")

      rollback = { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-04-0010' }
      expect(refusal('pools.rollback', rollback.merge('confirm' => 'nope'))).to eq("type the pool's name (old) to roll it back")
      expect(steps('pools.rollback', rollback.merge('confirm' => 'old')))
        .to eq([[:rollback_pool, 'old', 'amahi-daily-2026-10-04-0010'], [:pool_status]])
    end

    it 'rolls back every dataset in the pool that has the snapshot' do
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name -r -t filesystem,volume old]).and_return("old\nold/bitshare\nold/new\n")
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name -r -t snapshot old])
                                        .and_return("old@amahi-daily-2026-10-04-0010\nold/bitshare@amahi-daily-2026-10-04-0010\n")
      expect(helper.do_rollback_pool('old', 'amahi-daily-2026-10-04-0010')).to eq('rolled_back' => %w[old old/bitshare], 'apps_stopped' => [])
      expect(ran).to eq([%w[/usr/sbin/zfs rollback -r old@amahi-daily-2026-10-04-0010],
                         %w[/usr/sbin/zfs rollback -r old/bitshare@amahi-daily-2026-10-04-0010]])
    end

    # Apps keeping their data on the pool (P4.6): a roll-back comes first, so they're stopped while
    # it runs, and the ones that were running start again whether it worked or not.
    it 'stops the running apps whose data is on the pool while it rolls back, and starts them again' do
      File.write("#{dir}/app-storage.json", { 'store' => 'old', 'idle' => 'old', 'gone' => 'old', 'other' => 'tank' }.to_json)
      allow(helper).to receive(:app_image) { |id| %w[store idle].include?(id) ? "example/#{id}:1@sha256:#{'a' * 64}" : nil }
      allow(helper).to receive(:app_running?) { |id| id == 'store' }
      allow(helper).to receive(:say)
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name -r -t filesystem,volume old]).and_return("old\nold/apps/store\n")
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zfs list -H -o name -r -t snapshot old])
                                        .and_return("old@amahi-daily-2026-10-04-0010\nold/apps/store@amahi-daily-2026-10-04-0010\n")
      expect(helper.do_rollback_pool('old', 'amahi-daily-2026-10-04-0010'))
        .to eq('rolled_back' => %w[old old/apps/store], 'apps_stopped' => ['store'])
      expect(ran).to eq([%w[/usr/bin/docker stop --time 30 amahi-store],
                         %w[/usr/sbin/zfs rollback -r old@amahi-daily-2026-10-04-0010],
                         %w[/usr/sbin/zfs rollback -r old/apps/store@amahi-daily-2026-10-04-0010],
                         ['/usr/bin/docker', 'start', 'amahi-store', { allow_failure: true }]])

      ran.clear
      allow(helper).to receive(:run_command) do |argv|
        ran << argv
        raise AmahiHelper::Failed, 'dataset is busy' if argv[1] == 'rollback'
      end
      expect { helper.do_rollback_pool('old', 'amahi-daily-2026-10-04-0010') }.to raise_error(AmahiHelper::Failed, 'dataset is busy')
      expect(ran.last).to eq(['/usr/bin/docker', 'start', 'amahi-store', { allow_failure: true }]) # started again anyway
    end

    it "takes the snapshots that are due, then prunes the oldest of each kind beyond what's kept, never manual or others'" do
      reply = helper.do_run_snapshots(now)
      # The last hourly is 20 minutes old (not due); the last daily a day old (due).
      expect(reply['pools'].sole).to include('pool' => 'old', 'taken' => ['amahi-daily-2026-10-05-1405'])
      expect(reply['pools'].sole['pruned']).to eq(['amahi-hourly-2026-10-05-1305'])
      expect(ran).to eq([%w[/usr/sbin/zfs snapshot -r old@amahi-daily-2026-10-05-1405],
                         %w[/usr/sbin/zfs destroy -r old@amahi-hourly-2026-10-05-1305]])
    end

    it 'takes nothing of a kind turned off, removes those it kept, and fails at the end when a pool fails' do
      policy.replace("amahi:snapshot-hourly\t0\namahi:snapshot-daily\t0\n")
      helper.do_run_snapshots(now)
      expect(ran.map(&:last)).to eq(%w[old@amahi-hourly-2026-10-05-1305 old@amahi-hourly-2026-10-05-1345
                                       old@amahi-daily-2026-10-03-0010 old@amahi-daily-2026-10-04-0010])
      expect(ran.map { |argv| argv[1] }.uniq).to eq(['destroy'])

      allow(helper).to receive(:capture).with(list_cmd).and_raise(AmahiHelper::Failed, 'zfs exited 1: busy')
      expect { helper.do_run_snapshots(now) }.to raise_error(AmahiHelper::Failed, 'old: zfs exited 1: busy')
    end
  end

  describe 'pools.scrub' do
    it 'scrubs a pool that exists' do
      expect(steps('pools.scrub', { 'name' => 'old' })).to eq([%w[/usr/sbin/zpool scrub old]])
      expect(refusal('pools.scrub', { 'name' => 'tank' })).to eq('there\'s no pool named "tank"')
      expect(refusal('pools.scrub', { 'name' => 'old; reboot' })).to include("there's no pool named")
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(false)
      expect(refusal('pools.scrub', { 'name' => 'old' })).to eq("zpool isn't installed")
    end
  end

  describe 'packages.install' do
    it "leaves out recommended packages when asked (smartmontools' would bring a mail server)" do
      install = ->(args) { steps('packages.install', args).last }
      expect(install.call({ 'packages' => ['smartmontools'], 'recommends' => false })).to include('--no-install-recommends')
      expect(install.call({ 'packages' => ['zfsutils-linux'] })).not_to include('--no-install-recommends')
      expect(install.call({ 'packages' => ['zfsutils-linux'], 'recommends' => true })).not_to include('--no-install-recommends')
      expect(refusal('packages.install', { 'packages' => ['smartmontools'], 'recommends' => 'no' })).to eq('recommends must be true or false')
    end
  end

  describe 'storage.check_health' do
    let(:health_file) { "#{dir}/storage-health.json" }
    let(:samsung) do
      { 'smartctl' => { 'exit_status' => 0 }, 'model_name' => 'Samsung SSD 870 EVO 1TB', 'serial_number' => 'S6PXNM0T1',
        'firmware_version' => 'SVT02B6Q', 'rotation_rate' => 0, 'smart_status' => { 'passed' => true },
        'power_on_time' => { 'hours' => 4210 }, 'temperature' => { 'current' => 31 },
        'ata_smart_attributes' => { 'table' => [
          { 'id' => 5, 'name' => 'Reallocated_Sector_Ct', 'value' => 100, 'worst' => 100, 'thresh' => 10, 'raw' => { 'value' => 0 } },
          { 'id' => 9, 'name' => 'Power_On_Hours', 'value' => 99, 'worst' => 99, 'thresh' => 0, 'raw' => { 'value' => 4210 } },
          { 'id' => 177, 'name' => 'Wear_Leveling_Count', 'value' => 98, 'worst' => 98, 'thresh' => 0, 'raw' => { 'value' => 21 } },
          { 'id' => 194, 'name' => 'Temperature_Celsius', 'value' => 69, 'worst' => 52, 'thresh' => 0, 'raw' => { 'value' => 31 } }
        ] } }
    end
    let(:failing) do
      { 'model_name' => 'WDC WD40EFZX', 'serial_number' => 'WD-1', 'firmware_version' => '81.00A81', 'rotation_rate' => 5400,
        'smart_status' => { 'passed' => false }, 'power_on_time' => { 'hours' => 40_000 },
        'ata_smart_attributes' => { 'table' => [
          { 'id' => 5, 'name' => 'Reallocated_Sector_Ct', 'value' => 1, 'worst' => 1, 'thresh' => 140, 'raw' => { 'value' => 2000 } }
        ] } }
    end
    let(:nvme) do
      { 'model_name' => 'Samsung SSD 980 1TB', 'serial_number' => 'S2', 'firmware_version' => '1B4QFXO7', 'smart_status' => { 'passed' => true },
        'power_on_time' => { 'hours' => 800 }, 'temperature' => { 'current' => 40 },
        'nvme_smart_health_information_log' => { 'critical_warning' => 0, 'temperature' => 40, 'available_spare' => 100,
                                                  'available_spare_threshold' => 10, 'percentage_used' => 3, 'media_errors' => 0 } }
    end
    let(:no_smart) { { 'smartctl' => { 'exit_status' => 1, 'messages' => [{ 'string' => '/dev/sda: Unable to detect device type' }] } } }
    let(:outputs) do
      { '/dev/sdc' => [samsung, 0], '/dev/sdd' => [failing, 8], '/dev/nvme0n1' => [nvme, 0],
        '/dev/sde' => [{ 'smartctl' => { 'exit_status' => 9 } }, 9] }
    end

    before do
      stub_const('AmahiHelper::STORAGE_HEALTH', health_file)
      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(true)
      allow(helper).to receive(:do_pool_status).and_return('zfs' => true, 'pools' => [{ 'name' => 'old', 'health' => 'ONLINE' }])
      allow(helper).to receive(:do_smartd_follow_need) # smartd following the drives: see 'services that run while they have work'
      allow(helper).to receive(:do_install) { |path, content, *| File.write(path, content) }
      allow(Open3).to receive(:capture3) do |_env, _cmd, *args, **_opts|
        data, code = outputs.fetch(args.last, [no_smart, 1])
        [data.to_json, '', instance_double(Process::Status, exitstatus: code)]
      end
    end

    it 'plans one action with no arguments' do
      expect(steps('storage.check_health', {})).to eq([[:check_health]])
      expect(refusal('storage.check_health', { 'drive' => '/dev/sda' })).to eq('unexpected argument drive')
    end

    it "reads every whole disk's SMART data without waking sleeping drives, and saves it with the pools for the app" do
      File.write(health_file, { 'drives' => { '/dev/sde' => { 'model' => 'Sleepy HDD', 'passed' => true } } }.to_json)
      reply = helper.do_check_health
      saved = JSON.parse(File.read(health_file))
      expect(saved).to eq(reply['health'])
      expect(saved).to include('smartctl' => true, 'zfs' => true, 'pools' => [{ 'name' => 'old', 'health' => 'ONLINE' }])
      expect(saved['checked_at']).to match(/\A\d{4}-\d\d-\d\dT/)
      expect(saved['drives'].keys).to eq(%w[/dev/sda /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg /dev/sdh /dev/nvme0n1])
      expect(saved['drives']['/dev/sda']).to be_nil
      expect(saved['drives']['/dev/sdc']).to eq(
        'model' => 'Samsung SSD 870 EVO 1TB', 'serial' => 'S6PXNM0T1', 'firmware' => 'SVT02B6Q', 'passed' => true,
        'power_on_hours' => 4210, 'temperature' => 31, 'ssd' => true,
        'attributes' => { '5' => { 'name' => 'Reallocated_Sector_Ct', 'value' => 100, 'thresh' => 10, 'raw' => 0 },
                          '9' => { 'name' => 'Power_On_Hours', 'value' => 99, 'thresh' => 0, 'raw' => 4210 },
                          '177' => { 'name' => 'Wear_Leveling_Count', 'value' => 98, 'thresh' => 0, 'raw' => 21 } },
        'nvme' => nil
      )
      expect(saved['drives']['/dev/sdd']).to include('passed' => false, 'ssd' => false)
      expect(saved['drives']['/dev/nvme0n1']).to include('ssd' => true, 'nvme' => include('percentage_used' => 3, 'media_errors' => 0))
      expect(saved['drives']['/dev/sde']).to eq('model' => 'Sleepy HDD', 'passed' => true, 'asleep' => true)
      expect(Open3).to have_received(:capture3)
        .with(AmahiHelper::ENV_MIN, ['/usr/bin/timeout', '/usr/bin/timeout'], '10', '/usr/sbin/smartctl', '--json',
              '-n', 'standby,9', '-i', '-H', '-A', '/dev/sdc', unsetenv_others: true, chdir: '/')
      expect(helper).to have_received(:do_install).with(health_file, anything, nil, '0640', 'amahi')
      expect(helper).to have_received(:do_pool_status).with(false) # no scan of the drives, which would wake them
    end

    it 'has smartd follow the drives it read' do
      helper.do_check_health
      expect(helper).to have_received(:do_smartd_follow_need).with(include('/dev/sdc' => include('model' => 'Samsung SSD 870 EVO 1TB'), '/dev/sda' => nil))
    end

    it 'records no SMART data without smartctl' do
      allow(File).to receive(:executable?).with('/usr/sbin/smartctl').and_return(false)
      saved = helper.do_check_health['health']
      expect(saved['smartctl']).to be(false)
      expect(saved['drives'].values.uniq).to eq([nil])
      expect(Open3).not_to have_received(:capture3)
    end
  end

  describe 'by-id names' do
    it 'prefers the model-and-serial link, ignoring partitions, and falls back to the plain path' do
      allow(helper).to receive(:stable_path).and_call_original
      by_id = "#{dir}/by-id"
      FileUtils.mkdir_p(by_id)
      File.write("#{dir}/sdc", '')
      File.write("#{dir}/sdc1", '')
      File.symlink("#{dir}/sdc", "#{by_id}/wwn-0x5002538f0000001")
      File.symlink("#{dir}/sdc", "#{by_id}/ata-Samsung_SSD_870_EVO_1TB_S6P")
      File.symlink("#{dir}/sdc1", "#{by_id}/ata-Samsung_SSD_870_EVO_1TB_S6P-part1")
      stub_const('AmahiHelper::BY_ID', by_id)
      expect(helper.stable_path("#{dir}/sdc")).to eq("#{by_id}/ata-Samsung_SSD_870_EVO_1TB_S6P")
      expect(helper.stable_path("#{dir}/sdd")).to eq("#{dir}/sdd")
    end
  end
end
