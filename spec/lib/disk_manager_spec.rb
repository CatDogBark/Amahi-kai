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

    it 'simulates formatting in non-production' do
      # In test env, format_disk! should simulate (not actually format)
      expect(DiskManager.format_disk!('/dev/sdb1')).to be true
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
    end
  end

  describe '.unmount!' do
    it 'rejects invalid device paths' do
      expect { DiskManager.unmount!('/tmp/evil') }.to raise_error(DiskManager::DiskError)
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

  describe '.fstab_entry' do
    it 'marks data drives nofail so a missing one cannot block boot' do
      line = DiskManager.fstab_entry('abcd-1234', '/mnt/storage-1', 'ext4')
      expect(line).to eq('UUID=abcd-1234 /mnt/storage-1 ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2')
    end

    it 'mounts NTFS with ntfs-3g' do
      expect(DiskManager.fstab_entry('A1B2', '/mnt/storage-2', 'ntfs')).to include(' ntfs-3g defaults,nofail')
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
