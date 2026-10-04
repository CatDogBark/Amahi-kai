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
end
