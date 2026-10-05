require 'rails_helper'

RSpec.describe DiskManager do
  # Use the built-in sample devices, not the disks of whatever machine runs the
  # specs: lsblk on a CI runner varies between runs, which made these flaky.
  before { allow(DiskManager).to receive(:execute_command).and_return("") }

  describe '.devices' do
    it 'returns an array of device hashes' do
      devices = DiskManager.devices
      expect(devices).to be_an(Array)
      expect(devices.length).to be >= 1
    end

    it 'each device has required keys' do
      devices = DiskManager.devices
      devices.each do |dev|
        expect(dev).to include(:name, :path, :model, :size, :os_disk, :partitions)
      end
    end

    it 'each partition has required keys' do
      devices = DiskManager.devices
      devices.each do |dev|
        dev[:partitions].each do |part|
          expect(part).to include(:name, :path, :size, :status)
          expect([:mounted, :unmounted, :unformatted]).to include(part[:status])
        end
      end
    end

    it 'identifies the OS disk' do
      devices = DiskManager.devices
      os_disks = devices.select { |d| d[:os_disk] }
      expect(os_disks.length).to be >= 1
    end
  end

  describe '.validate_device!' do
    it 'accepts valid sda paths' do
      expect { DiskManager.send(:validate_device!, '/dev/sda1') }.not_to raise_error
    end

    it 'accepts valid nvme paths' do
      expect { DiskManager.send(:validate_device!, '/dev/nvme0n1p1') }.not_to raise_error
    end

    it 'rejects invalid paths' do
      expect { DiskManager.send(:validate_device!, '/tmp/evil') }.to raise_error(DiskManager::DiskError, /Invalid device path/)
    end

    it 'rejects shell injection attempts' do
      expect { DiskManager.send(:validate_device!, '/dev/sda1; rm -rf /') }.to raise_error(DiskManager::DiskError)
    end
  end

  describe '.format_disk!' do
    it 'rejects invalid device paths' do
      expect { DiskManager.format_disk!('/tmp/not-a-device') }.to raise_error(DiskManager::DiskError)
    end

    it 'formats through the root helper' do
      expect(DiskManager.format_disk!('/dev/sdb1')).to be true
      expect(Privileged.calls).to eq([['disks.format', { device: '/dev/sdb1' }]])
    end

    it "raises the helper's reason as a DiskError" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('disks.format', '/dev/sdb1 is mounted at /mnt/storage-1; unmount it first'))
      expect { DiskManager.format_disk!('/dev/sdb1') }.to raise_error(DiskManager::DiskError, /unmount it first/)
    end
  end

  describe '.os_disk?' do
    it 'returns true for the OS device' do
      # Sample devices mark sda as OS disk
      expect(DiskManager.os_disk?('/dev/sda')).to be true
    end

    it 'returns false for non-OS device' do
      expect(DiskManager.os_disk?('/dev/sdb')).to be false
    end
  end

  describe '.mount!' do
    it 'rejects invalid device paths' do
      expect { DiskManager.mount!('/tmp/evil') }.to raise_error(DiskManager::DiskError)
    end

    it 'rejects mounting OS disk' do
      expect { DiskManager.mount!('/dev/sda1') }.to raise_error(DiskManager::DiskError, /OS disk/)
      expect(Privileged.calls).to be_empty
    end

    it 'mounts through the root helper at the next free slot and returns the mount point' do
      allow(DiskManager).to receive(:auto_mount_point).and_return('/mnt/storage-3')
      expect(DiskManager.mount!('/dev/sdb1')).to eq('/mnt/storage-3')
      expect(Privileged.calls).to eq([['disks.mount', { device: '/dev/sdb1', mount_point: '/mnt/storage-3' }]])
    end

    it 'uses the mount point the helper reports' do
      allow(Privileged).to receive(:call).and_return('ok' => true, 'mount_point' => '/mnt/media')
      expect(DiskManager.mount!('/dev/sdb1', '/mnt/media')).to eq('/mnt/media')
    end
  end

  describe '.unmount!' do
    it 'rejects invalid device paths' do
      expect { DiskManager.unmount!('/tmp/evil') }.to raise_error(DiskManager::DiskError)
    end

    it 'unmounts through the root helper' do
      expect(DiskManager.unmount!('/dev/sdb1')).to be true
      expect(Privileged.calls).to eq([['disks.unmount', { device: '/dev/sdb1' }]])
    end

    it "raises the helper's reason as a DiskError" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('disks.unmount', "/dev/sdb1 isn't mounted"))
      expect { DiskManager.unmount!('/dev/sdb1') }.to raise_error(DiskManager::DiskError, "/dev/sdb1 isn't mounted")
    end
  end

  describe '.preview in production' do
    before { allow(DiskManager).to receive(:production?).and_return(true) }

    it "lists an unmounted drive through the root helper, in the page's format" do
      allow(DiskManager).to receive(:devices).and_return(DiskManager.send(:sample_devices))
      allow(Privileged).to receive(:call).with('disks.preview', device: '/dev/sdb1').and_return(
        'ok' => true, 'total_used' => 6000, 'file_count' => 2,
        'entries' => [{ 'name' => 'Movies', 'type' => 'directory', 'size' => 5000, 'file_count' => 1 },
                      { 'name' => 'a.txt', 'type' => 'file', 'size' => 1000, 'file_count' => 1 }]
      )
      preview = DiskManager.preview('/dev/sdb1')
      expect(preview[:entries].first).to eq(name: 'Movies', type: :directory, size: 5000, file_count: 1)
      expect(preview.slice(:total_used, :file_count)).to eq(total_used: 6000, file_count: 2)
    end
  end

  describe '.base_device' do
    it 'strips the partition number from SATA and NVMe names' do
      expect(DiskManager.base_device('/dev/sda1')).to eq('/dev/sda')
      expect(DiskManager.base_device('/dev/nvme0n1p2')).to eq('/dev/nvme0n1')
      expect(DiskManager.base_device('/dev/nvme0n1')).to eq('/dev/nvme0n1')
    end
  end

  describe '.os_disk? with an NVMe boot disk' do
    it 'protects every partition on it' do
      allow(DiskManager).to receive(:devices).and_return([
        { name: 'nvme0n1', path: '/dev/nvme0n1', os_disk: true, partitions: [] },
        { name: 'sda', path: '/dev/sda', os_disk: false, partitions: [] }
      ])
      expect(DiskManager.os_disk?('/dev/nvme0n1p3')).to be true
      expect(DiskManager.os_disk?('/dev/sda1')).to be false
    end
  end

  describe 'OS disk detection' do
    # Ubuntu Server's default layout: / on LVM inside a partition, no separate /boot.
    let(:lsblk) do
      { "blockdevices" => [
        { "name" => "sda", "type" => "disk", "children" => [
          { "name" => "sda1", "type" => "part", "fstype" => "vfat", "mountpoint" => nil },
          { "name" => "sda2", "type" => "part", "fstype" => "LVM2_member", "mountpoint" => nil, "children" => [
            { "name" => "ubuntu--vg-ubuntu--lv", "type" => "lvm", "fstype" => "ext4", "mountpoint" => "/" }
          ] }
        ] },
        { "name" => "sdb", "type" => "disk", "fstype" => nil, "mountpoint" => nil }
      ] }.to_json
    end

    it 'finds / on an LVM volume inside a partition' do
      allow(DiskManager).to receive(:execute_command).with(/\Alsblk -J/).and_return(lsblk)
      devices = DiskManager.devices
      expect(devices.find { |d| d[:path] == '/dev/sda' }[:os_disk]).to be true
      expect(devices.find { |d| d[:path] == '/dev/sdb' }[:os_disk]).to be false
    end
  end

  describe 'drives with ZFS on them' do
    it 'names the pool, so the Devices page and the setup wizard leave the drive alone' do
      lsblk = { "blockdevices" => [
        { "name" => "sdc", "type" => "disk", "children" => [
          { "name" => "sdc1", "type" => "part", "fstype" => "zfs_member", "label" => "tank" },
          { "name" => "sdc9", "type" => "part", "fstype" => nil }
        ] },
        { "name" => "sdd", "type" => "disk", "fstype" => "zfs_member", "label" => nil },
        { "name" => "sde", "type" => "disk", "children" => [{ "name" => "sde1", "type" => "part", "fstype" => "ext4" }] }
      ] }.to_json
      allow(DiskManager).to receive(:execute_command).with(/\Alsblk -J -o .*,LABEL /).and_return(lsblk)
      expect(DiskManager.devices.to_h { |d| [d[:path], d[:zfs_pool]] }).to eq('/dev/sdc' => 'tank', '/dev/sdd' => 'unnamed', '/dev/sde' => nil)
    end
  end

  describe '.auto_mount_point' do
    before do
      allow(File).to receive(:read).and_call_original
      allow(Dir).to receive(:exist?).and_call_original
      allow(Dir).to receive(:exist?).with(%r{\A/mnt/storage-\d+\z}).and_return(false)
    end

    it 'skips a slot fstab still claims for an unplugged drive' do
      allow(File).to receive(:read).with('/etc/fstab')
        .and_return("UUID=gone /mnt/storage-1 ext4 defaults,nofail 0 2\n")
      expect(DiskManager.auto_mount_point).to eq('/mnt/storage-2')
    end

    it 'never rewrites fstab' do
      allow(File).to receive(:read).with('/etc/fstab').and_return("")
      DiskManager.auto_mount_point
      expect(DiskManager).not_to have_received(:execute_command).with(%r{/etc/fstab})
      expect(Privileged.calls).to be_empty
    end
  end

  describe '.sample_devices' do
    it 'returns three sample devices' do
      samples = DiskManager.send(:sample_devices)
      expect(samples.length).to eq(3)
    end

    it 'includes mounted, unmounted, and unformatted partitions' do
      samples = DiskManager.send(:sample_devices)
      statuses = samples.flat_map { |d| d[:partitions].map { |p| p[:status] } }
      expect(statuses).to include(:mounted, :unmounted, :unformatted)
    end
  end
end
