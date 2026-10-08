require 'rails_helper'

RSpec.describe Shell do
  describe '.output' do
    it "runs an argument list without a shell and returns what it prints, whatever its status" do
      expect(described_class.output('printf', '%s', 'a b; echo shell')).to eq('a b; echo shell')
      expect(described_class.output('sh', '-c', 'echo partial; exit 1')).to eq("partial\n")
    end

    it 'is empty when the command is not installed' do
      expect(described_class.output('amahi-no-such-command')).to eq('')
    end
  end

  describe '.success?' do
    it 'says whether the command ran and succeeded' do
      expect(described_class.success?('true')).to be true
      expect(described_class.success?('false')).to be false
      expect(described_class.success?('amahi-no-such-command')).to be false
    end
  end

  # Outside production the root helper never runs; production always runs it, and no setting
  # changes that (it used to be "dummy mode", which AMAHI_DUMMY_MODE in amahi.env could switch on).
  describe '.simulated?' do
    before { described_class.simulated = nil }

    it "is true outside production, where Privileged.call records the helper's calls" do
      expect(described_class).to be_simulated
    end

    it 'is false in production, whatever AMAHI_DUMMY_MODE says' do
      allow(Rails.env).to receive(:production?).and_return(true)
      ENV['AMAHI_DUMMY_MODE'] = '1'
      expect(described_class).not_to be_simulated
    ensure
      ENV.delete('AMAHI_DUMMY_MODE')
    end
  end

  it 'has no sudo step: root goes through the root helper' do
    expect(described_class.private_methods).not_to include(:prepare)
    expect(described_class.const_defined?(:SUDO_COMMANDS)).to be false
    expect(described_class).not_to respond_to(:run, :run!, :capture)
  end
end
