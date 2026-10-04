require 'rails_helper'

RSpec.describe SwapService do
  describe '.create!' do
    it 'asks the root helper for a swap file of the chosen size' do
      expect(described_class.create!('4G')).to be true
      expect(Privileged.calls).to eq([['system.create_swap', { size_gb: 4 }]])
    end

    it "returns false and reports the helper's reason when it fails" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('system.create_swap', '/swapfile already exists'))
      messages = []
      expect(described_class.create!('2G') { |msg| messages << msg }).to be false
      expect(messages.last).to include('/swapfile already exists')
    end

    it 'yields status messages to the block' do
      messages = []
      described_class.create!('4G') { |msg| messages << msg }
      expect(messages.first).to include('4G swap file')
    end

    it 'works without a block' do
      expect { described_class.create!('4G') }.not_to raise_error
    end
  end
end
