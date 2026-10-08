require 'rails_helper'

RSpec.describe Shell do
  before do
    # Run the real code paths (the system calls are stubbed)
    described_class.simulated = false
  end

  after do
    described_class.simulated = nil  # back to the rule: simulated outside production
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

  describe '.run_with_input' do
    it 'feeds the input on stdin and returns true on success' do
      expect(described_class.run_with_input("grep -qx hello", "hello\n")).to eq(true)
    end

    it 'returns false on failure' do
      expect(described_class.run_with_input("grep -qx hello", "goodbye\n")).to eq(false)
    end

    it 'never logs the input' do
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg }
      described_class.run_with_input("grep -qx nomatch", "s3cret-value\n")
      expect(logged.join("\n")).not_to include("s3cret-value")
    end
  end

  describe '.redact' do
    it 'masks secret-shaped text before it reaches the log' do
      expect(described_class.redact("mysql -e \"CREATE USER x IDENTIFIED BY 'hunter2'\""))
        .to eq("mysql -e \"CREATE USER x IDENTIFIED BY '[FILTERED]'\"")
      expect(described_class.redact("cloudflared tunnel run --token eyJabc")).to eq("cloudflared tunnel run --token [FILTERED]")
      expect(described_class.redact("db_pass = s3cret")).to eq("db_pass = [FILTERED]")
    end

    it 'leaves ordinary commands alone' do
      expect(described_class.redact("systemctl restart smbd.service")).to eq("systemctl restart smbd.service")
    end
  end

  # Outside production nothing runs; production always runs, and no setting changes that
  # (it used to be "dummy mode", which AMAHI_DUMMY_MODE in amahi.env could switch on).
  describe '.simulated?' do
    before { described_class.simulated = nil }

    it 'is true outside production, where commands are only logged' do
      expect(described_class).to be_simulated
      expect(described_class.run("exit 1")).to eq(true) # would fail if it ran
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
  end
end
