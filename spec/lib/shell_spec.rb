require 'rails_helper'

RSpec.describe Shell do
  before do
    # Force non-dummy mode for these tests
    described_class.dummy = false
  end

  after do
    described_class.dummy = nil  # reset to auto-detect
  end

  describe '.run' do
    it 'executes a command and returns true on success' do
      expect(described_class.run("true")).to eq(true)
    end

    it 'returns false on failure' do
      expect(described_class.run("false")).to eq(false)
    end

    it 'executes multiple commands sequentially' do
      expect(described_class.run("true", "true")).to eq(true)
    end

    it 'stops and returns false on first failure' do
      expect(described_class.run("true", "false", "true")).to eq(false)
    end
  end

  describe '.run!' do
    it 'returns true on success' do
      expect(described_class.run!("true")).to eq(true)
    end

    it 'raises CommandError on failure' do
      expect { described_class.run!("false") }.to raise_error(Shell::CommandError)
    end

    it 'includes command info in error' do
      begin
        described_class.run!("false")
      rescue Shell::CommandError => e
        expect(e.command).to eq("false")
        expect(e.exit_code).to eq(1)
      end
    end
  end

  describe '.capture' do
    it 'returns stdout, stderr, and status' do
      stdout, stderr, status = described_class.capture("echo hello")
      expect(stdout.strip).to eq("hello")
      expect(status.success?).to be true
    end

    it 'captures stderr' do
      _stdout, stderr, _status = described_class.capture("echo error >&2")
      expect(stderr.strip).to eq("error")
    end
  end

  describe '.dummy?' do
    it 'can be explicitly set' do
      described_class.dummy = true
      expect(described_class.dummy?).to be true
    end
  end

  describe 'dummy mode' do
    before { described_class.dummy = true }

    it 'does not execute commands' do
      # This would fail if actually executed
      expect(described_class.run("exit 1")).to eq(true)
    end
  end

  describe 'SUDO_COMMANDS' do
    it 'includes common privileged commands' do
      expect(Shell::SUDO_COMMANDS).to include('systemctl', 'docker', 'chmod', 'chown')
    end

    it 'does not include unprivileged commands' do
      expect(Shell::SUDO_COMMANDS).not_to include('echo', 'cat', 'ls')
    end
  end
end
