require 'rails_helper'

RSpec.describe DiskManager do
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
