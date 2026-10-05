require 'rails_helper'
require 'storage_health'

RSpec.describe StorageHealth do
  def smart(**fields)
    { 'model' => 'Samsung SSD 870 EVO 1TB', 'passed' => true, 'power_on_hours' => 4210, 'firmware' => 'SVT02B6Q',
      'attributes' => { '5' => { 'value' => 100, 'raw' => 0 }, '177' => { 'value' => 98, 'raw' => 21 } } }.merge(fields.transform_keys(&:to_s))
  end

  def pool(**fields)
    { 'name' => 'tank', 'health' => 'ONLINE', 'scan' => 'scrub repaired 0B in 00:41:07 with 0 errors on Sun Oct  4 02:41:08 2026',
      'errors' => 'No known data errors',
      'vdevs' => [{ 'name' => 'raidz1-0', 'children' => [
        { 'name' => '/dev/disk/by-id/ata-S1-part1', 'device' => '/dev/sdc1', 'read' => '0', 'write' => '0', 'cksum' => '0', 'children' => [] },
        { 'name' => '/dev/disk/by-id/ata-S2-part1', 'device' => '/dev/sdd1', 'read' => '0', 'write' => '0', 'cksum' => '0', 'children' => [] }
      ] }] }.merge(fields.transform_keys(&:to_s))
  end

  def health(pools: [pool], drives: { '/dev/sdc' => smart, '/dev/sdd' => smart })
    described_class.new('checked_at' => '2026-10-04T12:00:00Z', 'smartctl' => true, 'pools' => pools, 'drives' => drives)
  end

  it 'has nothing to say about healthy pools and drives' do
    expect(health.alerts).to be_empty
    expect(health.drive_details('/dev/sdc')).to eq('2% worn · 4,210 hours · firmware SVT02B6Q')
    expect(health.drive_level('/dev/sdc')).to eq(:ok)
  end

  it 'reads a missing or broken file as never checked' do
    expect(described_class.load('/nonexistent/health.json')).not_to be_checked
    expect(described_class.new('drives' => 'x', 'pools' => 'y').alerts).to be_empty
  end

  it "warns about a pool that isn't ONLINE, data errors, drive errors and what a scrub found, worst first" do
    degraded = pool(health: 'DEGRADED', action: "Replace the device using 'zpool replace'.",
                    scan: 'scrub repaired 12K in 00:01:02 with 0 errors on Sun Oct  4 02:41:08 2026', errors: '3 data errors, use -v for a list')
    degraded['vdevs'][0]['children'][1]['cksum'] = '7'
    alerts = health(pools: [degraded]).alerts
    expect(alerts.map { |a| [a.level, a.message, a.path] }).to eq([
      [:danger, "Pool tank is DEGRADED: Replace the device using 'zpool replace'.", '/disks/pools'],
      [:danger, 'Pool tank has data errors: 3 data errors, use -v for a list', '/disks/pools'],
      [:warning, '/dev/sdd in pool tank has read/write/checksum errors (0 / 0 / 7)', '/disks/pools'],
      [:warning, 'The last scrub of tank repaired 12K of damaged data', '/disks/pools']
    ])
    unrepaired = pool(scan: 'scrub repaired 0B in 00:01:02 with 2 errors on Sun Oct  4 02:41:08 2026')
    expect(health(pools: [unrepaired]).alerts.sole.message).to eq("The last scrub of tank found 2 errors it couldn't repair")
    expect(health(pools: [pool(scan: 'scrub in progress since Sun Oct  4 10:00:00 2026')]).alerts).to be_empty
  end

  it "warns about a failing, damaged or worn-out drive, linking pool drives to ZFS Pools and others to Devices" do
    drives = {
      '/dev/sdc' => smart(passed: false),
      '/dev/sdd' => smart(attributes: { '5' => { 'raw' => 8 }, '197' => { 'raw' => 2 }, '177' => { 'value' => 5 } }),
      '/dev/sdb' => smart(model: 'WDC WD40EFZX', attributes: { '198' => { 'raw' => 1 }, '187' => { 'raw' => 4 } }),
      '/dev/nvme0n1' => { 'model' => 'Samsung SSD 980', 'nvme' => { 'critical_warning' => 4, 'media_errors' => 2, 'percentage_used' => 91 } }
    }
    alerts = health(drives: drives).alerts
    expect(alerts.map { |a| [a.level, a.message, a.path] }).to eq([
      [:danger, "/dev/sdc (Samsung SSD 870 EVO 1TB) says it's failing (its own SMART health check)", '/disks/pools'],
      [:danger, '/dev/nvme0n1 (Samsung SSD 980) reports a critical warning (NVMe)', '/disks/devices'],
      [:warning, '/dev/sdd (Samsung SSD 870 EVO 1TB) has 8 reallocated sectors', '/disks/pools'],
      [:warning, '/dev/sdd (Samsung SSD 870 EVO 1TB) has 2 sectors waiting to be reallocated', '/disks/pools'],
      [:warning, '/dev/sdd (Samsung SSD 870 EVO 1TB) is 95% worn out', '/disks/pools'],
      [:warning, '/dev/sdb (WDC WD40EFZX) has 1 uncorrectable sectors', '/disks/devices'],
      [:warning, '/dev/sdb (WDC WD40EFZX) has 4 uncorrectable errors reported', '/disks/devices'],
      [:warning, '/dev/nvme0n1 (Samsung SSD 980) has 2 media errors', '/disks/devices'],
      [:warning, '/dev/nvme0n1 (Samsung SSD 980) is 91% worn out', '/disks/devices']
    ])
    h = health(drives: drives)
    expect(h.drive_level('/dev/sdc')).to eq(:danger)
    expect(h.drive_level('/dev/sdd')).to eq(:warning)
  end

  it 'tells virtual disks by their model or virtio name, not real drives passed through to a VM' do
    expect(described_class.virtual_disk?('/dev/sda', 'QEMU HARDDISK')).to be(true)
    expect(described_class.virtual_disk?('/dev/sda', 'VBOX HARDDISK')).to be(true)
    expect(described_class.virtual_disk?('/dev/sdb', 'VMware Virtual S')).to be(true)
    expect(described_class.virtual_disk?('/dev/sdb', 'Virtual Disk')).to be(true)
    expect(described_class.virtual_disk?('/dev/vda', nil)).to be(true)
    expect(described_class.virtual_disk?('/dev/sdc', 'Samsung SSD 870 EVO 1TB')).to be(false)
    expect(described_class.virtual_disk?('/dev/nvme0n1', 'PM981a NVMe SAMSUNG 2048GB')).to be(false)
  end

  it 'says why a drive has no SMART data' do
    h = described_class.new('checked_at' => '2026-10-04T12:00:00Z', 'smartctl' => true, 'drives' => { '/dev/sda' => nil, '/dev/sdb' => nil })
    expect(h.missing_reason('/dev/sda', 'QEMU HARDDISK')).to eq(:virtual)
    expect(h.missing_reason('/dev/sdb', 'Some USB bridge')).to eq(:no_smart)
    expect(h.missing_reason('/dev/sdz', 'New drive')).to eq(:not_checked)
    no_tool = described_class.new('checked_at' => '2026-10-04T12:00:00Z', 'smartctl' => false, 'drives' => { '/dev/sda' => nil })
    expect(no_tool.missing_reason('/dev/sda', 'QEMU HARDDISK')).to eq(:no_smartctl)
  end

  it "takes an SSD's wear from NVMe's figure or the first ATA wear attribute, and says when a drive was asleep" do
    h = health
    expect(h.wear({ 'nvme' => { 'percentage_used' => 3 } })).to eq(3)
    expect(h.wear({ 'attributes' => { '231' => { 'value' => 88 } } })).to eq(12)
    expect(h.wear({ 'attributes' => { '5' => { 'value' => 100 } } })).to be_nil
    asleep = health(drives: { '/dev/sdb' => { 'model' => 'HDD', 'power_on_hours' => 10, 'asleep' => true } })
    expect(asleep.drive_details('/dev/sdb')).to eq('10 hours · asleep')
    expect(asleep.drive_details('/dev/sdz')).to be_nil
  end
end
