require 'spec_helper'
require 'greyhole'

describe Greyhole do
  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  describe '.enabled?' do
    it 'returns false in non-production (stubbed)' do
      expect(Greyhole.enabled?).to eq(false)
    end
  end

  describe '.status' do
    it 'returns a status hash' do
      status = Greyhole.status
      expect(status).to have_key(:installed)
      expect(status).to have_key(:running)
      expect(status).to have_key(:queue)
      expect(status).to have_key(:pool_drives)
    end

    it 'returns dummy status in non-production' do
      status = Greyhole.status
      expect(status[:installed]).to eq(false)
      expect(status[:running]).to eq(false)
    end
  end

  describe '.pool_drives' do
    it 'returns empty when no partitions' do
      expect(Greyhole.pool_drives).to eq([])
    end

    it 'returns drive info for each partition' do
      DiskPoolPartition.create!(path: '/mnt/drive1', minimum_free: 10)
      drives = Greyhole.pool_drives
      expect(drives.length).to eq(1)
      expect(drives.first[:path]).to eq('/mnt/drive1')
      expect(drives.first[:total]).to be > 0
    end
  end

  describe '.generate_config' do
    it 'generates config with pool drives' do
      DiskPoolPartition.create!(path: '/mnt/drive1', minimum_free: 10)
      config = Greyhole.generate_config
      expect(config).to include('storage_pool_drive = /mnt/drive1, min_free: 10gb')
    end

    it 'generates config with share settings' do
      share = Share.create!(name: 'Movies', path: '/var/hda/files/movies', disk_pool_copies: 2)
      config = Greyhole.generate_config
      expect(config).to include('[Movies]')
      expect(config).to include('num_copies = 2')
    end

    it 'uses max for copies >= 99' do
      Share.create!(name: 'Important', path: '/var/hda/files/important', disk_pool_copies: 99)
      config = Greyhole.generate_config
      expect(config).to include('num_copies = max')
    end
  end

  describe '.configure!' do
    it 'returns true in non-production' do
      expect(Greyhole.configure!).to eq(true)
    end
  end

  describe '.install!' do
    it 'returns true in non-production' do
      expect(Greyhole.install!).to eq(true)
    end
  end

  describe '.fsck' do
    it 'returns true in non-production' do
      expect(Greyhole.fsck).to eq(true)
    end
  end

  describe '.start!' do
    it 'returns true in non-production' do
      expect(Greyhole.start!).to eq(true)
    end
  end

  describe '.stop!' do
    it 'returns true in non-production' do
      expect(Greyhole.stop!).to eq(true)
    end
  end
end
