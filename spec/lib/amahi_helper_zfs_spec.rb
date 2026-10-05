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
         ['/usr/sbin/zpool', 'create', '-f', '-o', 'ashift=12', '-o', 'autotrim=on', '-O', 'compression=lz4',
          '-O', "mountpoint=#{dir}/pools/tank", 'tank', 'raidz1',
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

    it 'sets the running value when the module is loaded' do
      stub_const('AmahiHelper::ZFS_ARC_MAX', "#{dir}/zfs_arc_max")
      expect(helper.do_set_arc_max(5)).to eq('arc_max' => 5)
      expect(File.exist?("#{dir}/zfs_arc_max")).to be(false)
      File.write("#{dir}/zfs_arc_max", '0')
      helper.do_set_arc_max(2_147_483_648)
      expect(File.read("#{dir}/zfs_arc_max")).to eq('2147483648')
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

    it 'lists the pools with their sizes, mount points and status' do
      allow(helper).to receive(:capture) do |argv|
        case argv
        when %w[/usr/sbin/zpool list -H -p -o name,size,allocated,free,health] then "tank\t2980000000000\t1000\t2979999999000\tONLINE\n"
        when %w[/usr/sbin/zfs list -H -p -o used,available,mountpoint tank] then "1000\t2000000000000\t/srv/pools/tank\n"
        when %w[/usr/sbin/zpool status -P tank] then healthy
        else raise "unexpected #{argv}"
        end
      end
      pool = helper.do_pool_status['pools'].sole
      expect(pool).to include('name' => 'tank', 'size' => 2_980_000_000_000, 'allocated' => 1000, 'free' => 2_979_999_999_000,
                              'health' => 'ONLINE', 'used' => 1000, 'available' => 2_000_000_000_000,
                              'mountpoint' => '/srv/pools/tank', 'state' => 'ONLINE')
      expect(pool['vdevs'].sole['children'].size).to eq(3)
    end

    it "says ZFS isn't installed, and passes on a zpool failure" do
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(false)
      expect(helper.do_pool_status).to eq('zfs' => false, 'pools' => [])
      allow(File).to receive(:executable?).with('/usr/sbin/zpool').and_return(true)
      allow(helper).to receive(:capture).and_raise(AmahiHelper::Failed, 'zpool exited 1: The ZFS modules are not loaded.')
      expect(helper.do_pool_status).to eq('zfs' => true, 'pools' => [], 'error' => 'zpool exited 1: The ZFS modules are not loaded.')
    end

    it 'maps every device in an imported pool to its pool' do
      allow(helper).to receive(:pooled_devices).and_call_original
      allow(helper).to receive(:pool_names).and_return(['tank'])
      allow(helper).to receive(:capture).with(%w[/usr/sbin/zpool status -P tank]).and_return(degraded)
      expect(helper.pooled_devices).to eq('/dev/sdc1' => 'tank', '/dev/sde1' => 'tank')
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
