require 'rails_helper'

RSpec.describe DashboardStats do
  describe '.summary' do
    it 'returns a hash with all sections' do
      summary = DashboardStats.summary
      expect(summary).to include(:system, :resources, :services, :storage, :counts, :drives, :pools, :pool)
    end
  end

  # One ZFS pool as the health check's file has it (the helper's pools.status).
  def zfs_pool(name, managed: true, **fields)
    drive = ->(n) { { 'name' => "/dev/disk/by-id/ata-Samsung_SSD_870_S#{n}-part1", 'device' => "/dev/sd#{n}1", 'state' => 'ONLINE', 'children' => [] } }
    { 'name' => name, 'health' => 'ONLINE', 'managed' => managed, 'used' => 1_500_000_000_000, 'available' => 1_300_000_000_000,
      'mountpoint' => "/srv/pools/#{name}", 'vdevs' => [{ 'name' => 'raidz1-0', 'state' => 'ONLINE', 'children' => %w[b c d e].map(&drive) }] }
      .merge(fields)
  end

  describe '.zfs_pools' do
    it "lists Amahi-kai's pools with the space ZFS gives them, usable after parity" do
      health = StorageHealth.new('pools' => [zfs_pool('data'), zfs_pool('rpool', managed: false)])
      expect(DashboardStats.zfs_pools(health)).to eq([
        { name: 'data', layout: 'RAIDZ1', drives: 4, health: 'ONLINE', used: 1_500_000_000_000, free: 1_300_000_000_000,
          total: 2_800_000_000_000, percent: 53.6 }
      ])
    end

    it "says the space is unknown (total 0) for a pool the check couldn't read" do
      health = StorageHealth.new('pools' => [{ 'name' => 'data', 'health' => 'FAULTED', 'managed' => true, 'error' => 'cannot open' }])
      expect(DashboardStats.zfs_pools(health)).to eq([{ name: 'data', layout: 'Stripe', drives: 0, health: 'FAULTED', used: 0, free: 0, total: 0, percent: 0 }])
    end

    it 'is empty before the first check' do
      expect(DashboardStats.zfs_pools(StorageHealth.new({}))).to eq([])
    end
  end

  describe 'the drives' do
    let(:df) do
      <<~DF
        Filesystem     1G-blocks  Used Available Use% Mounted on
        tmpfs                 1G    1G        1G   1% /run
        /dev/sda2            62G   21G       38G  36% /
        /dev/sda1             2G    1G        2G  10% /boot
        /dev/sdb1           916G  300G      570G  35% /mnt/sdb1
        /dev/sdc1           916G  280G      590G  33% /mnt/sdc1
        /dev/sdd1           458G   10G      425G   3% /mnt/backup
        data/shares        2603G 1394G     1209G  54% /srv/pools/data/shares
      DF
    end

    before do
      allow(Shell).to receive(:output).and_call_original
      allow(Shell).to receive(:output).with('df', '-BG').and_return(df)
    end

    it "shows the system disk and drives on their own, not the pools': their space is on the Storage card" do
      DiskPoolPartition.add!('/mnt/sdb1')
      DiskPoolPartition.add!('/mnt/sdc1/pool')
      expect(DashboardStats.summary(StorageHealth.new({}))[:drives].map { |d| [d[:label], d[:device]] })
        .to eq([%w[System /dev/sda2], %w[boot /dev/sda1], %w[backup /dev/sdd1]])
    end

    it 'shows every drive without a Greyhole pool' do
      expect(DashboardStats.summary(StorageHealth.new({}))[:drives].map { |d| d[:mount] }).to eq(%w[/ /boot /mnt/sdb1 /mnt/sdc1 /mnt/backup])
    end
  end

  describe '.system_info' do
    it 'returns hostname, uptime, and os' do
      info = DashboardStats.system_info
      expect(info).to include(:hostname, :uptime, :os)
      expect(info[:hostname]).to be_a(String)
      expect(info[:os]).to be_a(String)
    end
  end

  describe '.resource_usage' do
    it 'returns cpu, memory, and disk' do
      usage = DashboardStats.resource_usage
      expect(usage).to include(:cpu, :memory, :disk)
    end

    it 'cpu has percent and detail' do
      cpu = DashboardStats.resource_usage[:cpu]
      expect(cpu).to include(:percent, :detail)
      expect(cpu[:percent]).to be_a(Integer)
    end

    it 'memory has percent and detail' do
      mem = DashboardStats.resource_usage[:memory]
      expect(mem).to include(:percent, :detail)
    end

    it 'disk has percent and detail' do
      disk = DashboardStats.resource_usage[:disk]
      expect(disk).to include(:percent, :detail)
    end
  end

  describe '.service_status' do
    it 'returns an array of service hashes' do
      services = DashboardStats.service_status
      expect(services).to be_an(Array)
      services.each do |svc|
        expect(svc).to include(:name, :unit, :running, :status)
      end
    end

    it 'always includes core services' do
      names = DashboardStats.service_status.map { |s| s[:name] }
      expect(names).to include('Samba', 'MariaDB')
    end
  end

  describe '.storage_summary' do
    it 'returns storage counts' do
      summary = DashboardStats.storage_summary
      expect(summary).to include(:shares_count, :total_files, :pool_drives, :greyhole_installed)
      expect(summary[:shares_count]).to be_a(Integer)
    end
  end

  describe '.entity_counts' do
    it 'returns entity counts' do
      counts = DashboardStats.entity_counts
      expect(counts).to include(:users, :shares, :dns_aliases, :docker_apps)
      counts.each_value { |v| expect(v).to be_a(Integer) }
    end

    it 'counts created shares' do
      create(:share)
      create(:share)
      expect(DashboardStats.entity_counts[:shares]).to be >= 2
    end
  end
end
