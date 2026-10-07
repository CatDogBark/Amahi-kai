require 'spec_helper'

describe DiskPoolPartition do
  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  describe 'validations' do
    it 'requires path' do
      part = DiskPoolPartition.new(minimum_free: 10)
      expect(part).not_to be_valid
      expect(part.errors[:path]).to include("can't be blank")
    end

    it 'requires unique path' do
      DiskPoolPartition.create!(path: '/mnt/drive1', minimum_free: 10)
      dup = DiskPoolPartition.new(path: '/mnt/drive1', minimum_free: 10)
      expect(dup).not_to be_valid
      expect(dup.errors[:path]).to include('has already been taken')
    end

    it 'requires minimum_free to be non-negative' do
      part = DiskPoolPartition.new(path: '/mnt/drive1', minimum_free: -1)
      expect(part).not_to be_valid
    end

    it 'requires a data drive under /mnt, since Greyhole only pools those' do
      %w[/ /etc /mnt /mnt/ /mnt/../etc /mnt/.hidden /mnt/a/.. /mnt/a/./b /mnt/a//b /var/lib/mysql].each do |path|
        expect(DiskPoolPartition.new(path: path, minimum_free: 10)).not_to be_valid, path
      end
      %w[/mnt/storage-1 /mnt/media/pool /mnt/media/.pool].each do |path|
        expect(DiskPoolPartition.new(path: path, minimum_free: 10)).to be_valid, path
      end
    end

    it 'is valid with path and minimum_free' do
      part = DiskPoolPartition.new(path: '/mnt/drive1', minimum_free: 10)
      expect(part).to be_valid
    end

    it 'defaults minimum_free to 10' do
      part = DiskPoolPartition.create!(path: '/mnt/drive1')
      expect(part.minimum_free).to eq(10)
    end
  end

  describe '.pool_paths' do
    it 'returns array of paths' do
      DiskPoolPartition.create!(path: '/mnt/a', minimum_free: 10)
      DiskPoolPartition.create!(path: '/mnt/b', minimum_free: 20)
      expect(DiskPoolPartition.pool_paths).to match_array(['/mnt/a', '/mnt/b'])
    end
  end

  describe '.default_minimum_free' do
    def drive_of(gigabytes)
      instance_double(Sys::Filesystem::Stat, block_size: 4096, blocks: (gigabytes * 1024**3 / 4096).to_i)
    end

    it 'leaves 10 GB free on a big drive, 5% of a smaller one, and 1 GB at least' do
      allow(Sys::Filesystem).to receive(:stat).and_call_original
      allow(Sys::Filesystem).to receive(:stat).with('/mnt/big').and_return(drive_of(931))
      allow(Sys::Filesystem).to receive(:stat).with('/mnt/mid').and_return(drive_of(100))
      allow(Sys::Filesystem).to receive(:stat).with('/mnt/small').and_return(drive_of(7.78))
      expect(DiskPoolPartition.default_minimum_free('/mnt/big')).to eq(10)
      expect(DiskPoolPartition.default_minimum_free('/mnt/mid')).to eq(5)
      expect(DiskPoolPartition.default_minimum_free('/mnt/small')).to eq(1)
      expect(DiskPoolPartition.default_minimum_free('/mnt/not-mounted-here')).to eq(10)
    end
  end
end
