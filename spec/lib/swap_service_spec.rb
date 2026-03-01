require 'rails_helper'

RSpec.describe SwapService do
  before do
    allow(Shell).to receive(:run).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/fstab').and_return("")
  end

  describe '.create!' do
    it 'runs all setup commands and returns true' do
      result = described_class.create!('4G')
      expect(result).to be true
      expect(Shell).to have_received(:run).with(/fallocate.*#{SwapService::SWAP_PATH}/)
      expect(Shell).to have_received(:run).with("chmod 600 #{SwapService::SWAP_PATH}")
      expect(Shell).to have_received(:run).with("mkswap #{SwapService::SWAP_PATH} > /dev/null 2>&1")
      expect(Shell).to have_received(:run).with("swapon #{SwapService::SWAP_PATH}")
    end

    it 'adds fstab entry when not present' do
      described_class.create!('2G')
      expect(Shell).to have_received(:run).with(/echo.*#{SwapService::SWAP_PATH}.*fstab/)
    end

    it 'skips fstab entry when already present' do
      allow(File).to receive(:read).with('/etc/fstab').and_return("/swapfile none swap sw 0 0\n")
      described_class.create!('2G')
      expect(Shell).not_to have_received(:run).with(/fstab/)
    end

    it 'returns false if fallocate fails' do
      allow(Shell).to receive(:run).with(/fallocate/).and_return(false)
      expect(described_class.create!('4G')).to be false
    end

    it 'yields status messages to the block' do
      messages = []
      described_class.create!('4G') { |msg| messages << msg }
      expect(messages).to include('Creating 4G swap file...')
      expect(messages).to include('Setting permissions...')
      expect(messages).to include('Enabling swap...')
    end

    it 'works without a block' do
      expect { described_class.create!('4G') }.not_to raise_error
    end
  end
end
