require 'rails_helper'

RSpec.describe DiskService do
  describe '.toggle_pool_partition' do
    let(:path) { '/mnt/data1' }

    before do
      allow(Greyhole).to receive(:installed?).and_return(false)
    end

    context 'when partition exists in pool' do
      let!(:partition) { DiskPoolPartition.create!(path: path, minimum_free: 10) }

      it 'removes the partition and returns checked: false' do
        result = described_class.toggle_pool_partition(path)
        expect(result).to eq({ checked: false, path: path })
        expect(DiskPoolPartition.where(path: path)).to be_empty
      end
    end

    context 'when partition does not exist in pool' do
      it 'creates the partition and returns checked: true' do
        result = described_class.toggle_pool_partition(path)
        expect(result).to eq({ checked: true, path: path })
        expect(DiskPoolPartition.where(path: path).count).to eq(1)
      end
    end

    context 'when Greyhole is installed' do
      before do
        allow(Greyhole).to receive(:installed?).and_return(true)
        allow(Greyhole).to receive(:configure!)
      end

      it 'calls Greyhole.configure!' do
        described_class.toggle_pool_partition(path)
        expect(Greyhole).to have_received(:configure!)
      end
    end

    context 'when Greyhole.configure! raises' do
      before do
        allow(Greyhole).to receive(:installed?).and_return(true)
        allow(Greyhole).to receive(:configure!).and_raise(StandardError, 'boom')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and does not raise' do
        expect { described_class.toggle_pool_partition(path) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/Greyhole configure failed: boom/)
      end
    end
  end

  describe '.toggle_greyhole' do
    context 'when running' do
      before { allow(Greyhole).to receive(:running?).and_return(true) }

      it 'stops Greyhole' do
        expect(Greyhole).to receive(:stop!)
        described_class.toggle_greyhole
      end
    end

    context 'when not running' do
      before { allow(Greyhole).to receive(:running?).and_return(false) }

      it 'starts Greyhole' do
        expect(Greyhole).to receive(:start!)
        described_class.toggle_greyhole
      end
    end
  end

  describe '.create_share_from_mount' do
    let(:device) { '/dev/sdb1' }
    let(:mount_point) { '/mnt/sdb1' }

    before do
      allow(DiskManager).to receive(:mount!).with(device).and_return(mount_point)
    end

    it 'mounts the device and creates a share' do
      result = described_class.create_share_from_mount(device)
      expect(result[:mount_point]).to eq(mount_point)
      expect(result[:share_name]).to eq('sdb1')
      expect(Share.find_by(path: mount_point)).to be_present
    end

    it 'does not create duplicate shares' do
      described_class.create_share_from_mount(device)
      described_class.create_share_from_mount(device)
      expect(Share.where(path: mount_point).count).to eq(1)
    end

    it 'generates fallback name for blank basename' do
      allow(DiskManager).to receive(:mount!).and_return('/mnt/')
      allow(File).to receive(:basename).with('/mnt/').and_return('')
      result = described_class.create_share_from_mount(device)
      expect(result[:share_name]).to start_with('drive-')
    end
  end

  describe '.partition_list' do
    it 'returns partition info from PartitionUtils' do
      info = [{ path: '/dev/sda1' }]
      partition_utils = instance_double('PartitionUtils', info: info)
      allow(PartitionUtils).to receive(:new).and_return(partition_utils)
      expect(described_class.partition_list).to eq(info)
    end

    it 'returns empty array on error' do
      allow(PartitionUtils).to receive(:new).and_raise(StandardError)
      expect(described_class.partition_list).to eq([])
    end
  end

  describe '.stream_greyhole_install' do
    let(:sse) { double('sse', send: nil, done: nil) }

    context 'in non-production' do
      before { allow(Rails.env).to receive(:production?).and_return(false) }

      it 'streams dev messages and calls done' do
        described_class.stream_greyhole_install(sse)
        expect(sse).to have_received(:send).at_least(:once)
        expect(sse).to have_received(:done).with(no_args)
      end
    end
  end
end
