require 'spec_helper'

describe Command do
  describe "EXEC_MODE" do
    it "is :dummy in test environment" do
      expect(Command::EXEC_MODE).to eq(:dummy)
    end
  end

  describe "#initialize" do
    it "creates with no command" do
      cmd = Command.new
      expect(cmd).to be_a(Command)
    end

    it "creates with initial command" do
      cmd = Command.new("echo hello")
      expect(cmd).to be_a(Command)
    end
  end

  describe "#submit" do
    it "queues commands" do
      cmd = Command.new
      cmd.submit("echo one")
      cmd.submit("echo two")
      # In dummy mode, execute is a no-op
      expect { cmd.execute }.not_to raise_error
    end
  end

  describe "#execute" do
    it "is a no-op in dummy mode" do
      cmd = Command.new("dangerous-system-command")
      cmd.submit("another-dangerous-command")
      expect { cmd.execute }.not_to raise_error
    end
  end

  describe "#run_now" do
    it "is a no-op in dummy mode" do
      cmd = Command.new("echo test")
      expect { cmd.run_now }.not_to raise_error
    end
  end

  describe "#needs_sudo?" do
    let(:cmd) { Command.new }

    before do
      # Ensure we're not detected as root, so needs_sudo? actually checks commands
      allow(Process).to receive(:uid).and_return(1000)
    end

    it "detects privileged commands" do
      %w[useradd usermod systemctl chmod chown apt-get].each do |prog|
        expect(cmd.send(:needs_sudo?, "#{prog} something")).to be true
      end
    end

    it "does not flag non-privileged commands" do
      %w[echo sleep ls cat].each do |prog|
        expect(cmd.send(:needs_sudo?, "#{prog} something")).to be false
      end
    end

    it "handles env var prefixes" do
      expect(cmd.send(:needs_sudo?, "DEBIAN_FRONTEND=noninteractive apt-get -y install foo")).to be true
    end

    it "handles full paths" do
      expect(cmd.send(:needs_sudo?, "/usr/sbin/useradd testuser")).to be true
    end
  end
end
