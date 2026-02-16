require 'spec_helper'
require 'partition_utils'

RSpec.describe PartitionUtils do
  describe '#initialize' do
    it 'initializes with empty info when /etc/mtab does not exist' do
      allow(File).to receive(:open).with('/etc/mtab').and_raise(Errno::ENOENT)
      pu = PartitionUtils.new
      expect(pu.info).to eq([])
    end

    it 'parses /dev entries from mtab' do
      mtab_content = "/dev/sda1 / ext4 rw 0 0\ntmpfs /tmp tmpfs rw 0 0\n/dev/sdb1 /media/data ext4 rw 0 0\n"
      fake_file = StringIO.new(mtab_content)
      allow(File).to receive(:open).with('/etc/mtab').and_return(fake_file)
      allow_any_instance_of(PartitionUtils).to receive(:disk_stats).and_return([1000, 500])

      pu = PartitionUtils.new
      paths = pu.info.map { |i| i[:path] }
      expect(paths).to include('/')
      expect(paths).to include('/media/data')
    end

    it 'skips /boot partitions' do
      mtab_content = "/dev/sda1 /boot ext4 rw 0 0\n/dev/sda2 / ext4 rw 0 0\n"
      fake_file = StringIO.new(mtab_content)
      allow(File).to receive(:open).with('/etc/mtab').and_return(fake_file)
      allow_any_instance_of(PartitionUtils).to receive(:disk_stats).and_return([1000, 500])

      pu = PartitionUtils.new
      paths = pu.info.map { |i| i[:path] }
      expect(paths).not_to include('/boot')
      expect(paths).to include('/')
    end
  end

  describe '#part2device (via initialize)' do
    it 'strips partition number from device' do
      pu = PartitionUtils.allocate
      result = pu.send(:part2device, '/dev/sda1')
      expect(result).to eq('/dev/sda')
    end
  end

  describe '#cleanup_path' do
    it 'replaces \\040 with space' do
      pu = PartitionUtils.allocate
      result = pu.send(:cleanup_path, '/media/My\\040Drive')
      expect(result).to eq('/media/My Drive')
    end
  end
end
