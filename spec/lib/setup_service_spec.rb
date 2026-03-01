require 'rails_helper'

RSpec.describe SetupService do
  describe '.detect_memory' do
    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with('/proc/meminfo').and_return("MemTotal:        4096000 kB\n")
      allow(described_class).to receive(:`).with('swapon --show=SIZE --noheadings --bytes 2>/dev/null').and_return("")
    end

    it 'returns memory info' do
      result = described_class.detect_memory
      expect(result[:total_mb]).to eq(4000) # 4096000 / 1024
      expect(result[:swap_mb]).to eq(0)
      expect(result[:has_swap]).to be false
      expect(result[:needs_swap]).to be true
      expect(result[:recommended_swap]).to eq('2G')
    end

    context 'with swap present' do
      before do
        allow(described_class).to receive(:`).with('swapon --show=SIZE --noheadings --bytes 2>/dev/null').and_return("2147483648\n")
      end

      it 'detects swap' do
        result = described_class.detect_memory
        expect(result[:swap_mb]).to eq(2048)
        expect(result[:has_swap]).to be true
        expect(result[:needs_swap]).to be false
      end
    end

    context 'with plenty of RAM' do
      before do
        allow(File).to receive(:read).with('/proc/meminfo').and_return("MemTotal:        16384000 kB\n")
      end

      it 'does not recommend swap' do
        result = described_class.detect_memory
        expect(result[:needs_swap]).to be false
        expect(result[:recommended_swap]).to be_nil
      end
    end

    context 'with low RAM' do
      before do
        allow(File).to receive(:read).with('/proc/meminfo').and_return("MemTotal:        1024000 kB\n")
      end

      it 'recommends 4G swap' do
        result = described_class.detect_memory
        expect(result[:recommended_swap]).to eq('4G')
      end
    end
  end

  describe '.stream_prepare_drives' do
    let(:sse) { double('sse', send: nil, done: nil) }

    it 'handles empty drive selection' do
      described_class.stream_prepare_drives([], [], sse)
      expect(sse).to have_received(:send).with('⚠ No drives selected')
      expect(sse).to have_received(:done)
    end

    context 'with drives' do
      let(:devices) do
        [{ partitions: [{ path: '/dev/sdb1', mountpoint: '/mnt/data', status: :mounted, fstype: 'ext4' }] }]
      end

      before do
        allow(DiskManager).to receive(:devices).and_return(devices)
      end

      it 'adds ext4 partitions to pool' do
        described_class.stream_prepare_drives(['/dev/sdb1'], [], sse)
        expect(DiskPoolPartition.count).to be >= 1
        expect(sse).to have_received(:done).with('success')
      end

      it 'formats drives in format list' do
        allow(DiskManager).to receive(:format_disk!)
        allow(DiskManager).to receive(:mount!).and_return('/mnt/data')
        devices.first[:partitions].first[:mountpoint] = nil
        devices.first[:partitions].first[:status] = :unformatted

        described_class.stream_prepare_drives(['/dev/sdb1'], ['/dev/sdb1'], sse)
        expect(DiskManager).to have_received(:format_disk!).with('/dev/sdb1')
      end

      it 'skips unknown devices' do
        described_class.stream_prepare_drives(['/dev/sdz1'], [], sse)
        expect(sse).to have_received(:send).with(/not found/)
      end
    end
  end

  describe '.create_first_share' do
    before do
      allow(Setting).to receive(:get).with('default_pool_copies').and_return('0')
    end

    it 'creates a share with the given name' do
      share = described_class.create_first_share('Documents')
      expect(share).to be_a(Share)
      expect(share.name).to eq('Documents')
      expect(share.path).to include('documents')
    end

    it 'raises on validation failure' do
      described_class.create_first_share('Test')
      expect { described_class.create_first_share('Test') }.to raise_error(RuntimeError)
    end
  end

  describe '.stream_greyhole_install' do
    let(:sse) { double('sse', send: nil, done: nil) }

    before do
      allow(Setting).to receive(:set)
      allow(Rails.env).to receive(:production?).and_return(false)
    end

    it 'sets default_pool_copies setting' do
      described_class.stream_greyhole_install(2, sse)
      expect(Setting).to have_received(:set).with('default_pool_copies', '2')
    end

    it 'streams messages in dev mode' do
      described_class.stream_greyhole_install(1, sse)
      expect(sse).to have_received(:send).at_least(:once)
      expect(sse).to have_received(:done)
    end
  end
end
