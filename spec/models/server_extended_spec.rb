require 'rails_helper'

RSpec.describe Server, type: :model do
  let(:server) { Server.create!(name: "test-svc", comment: "Test Service", pidfile: "/var/run/test.pid") }

  describe "#clean_name" do
    it "returns cleaned service name" do
      expect(server.clean_name).to eq("test-svc")
    end
  end

  describe "#pid_file" do
    it "returns the pid file path" do
      expect(server.pid_file).to eq("/var/run/test.pid")
    end
  end

  describe "#stopped?" do
    it "returns true when not running" do
      allow(server).to receive(:pids).and_return([])
      expect(server.stopped?).to be true
    end
  end

  describe "#running?" do
    it "returns false when stopped" do
      allow(server).to receive(:pids).and_return([])
      expect(server.running?).to be false
    end

    it "returns true when pids exist" do
      allow(server).to receive(:pids).and_return([1234])
      expect(server.running?).to be true
    end
  end

  describe "#start_cmd" do
    it "returns systemctl start command" do
      expect(server.start_cmd).to include("start")
    end
  end

  describe "#stop_cmd" do
    it "returns systemctl stop command" do
      expect(server.stop_cmd).to include("stop")
    end
  end

  describe "#enable_cmd" do
    it "returns systemctl enable command" do
      expect(server.enable_cmd).to include("enable")
    end
  end

  describe "#disable_cmd" do
    it "returns systemctl disable command" do
      expect(server.disable_cmd).to include("disable")
    end
  end

  describe "#do_start" do
    it "executes start command" do
      allow(server).to receive(:system)
      server.do_start
    end
  end

  describe "#do_stop" do
    it "executes stop command" do
      allow(server).to receive(:system)
      server.do_stop
    end
  end

  describe "#do_restart" do
    it "executes restart command" do
      allow(server).to receive(:system)
      server.do_restart
    end
  end

  describe ".create_default_servers" do
    it "creates default servers" do
      Server.create_default_servers
      expect(Server.count).to be >= 4
    end
  end

  describe "validations" do
    it "requires a name" do
      server = Server.new(comment: "Test")
      expect(server).not_to be_valid
    end
  end

  describe "toggle attributes" do
    it "toggles monitored" do
      original = server.monitored
      server.toggle!(:monitored)
      expect(server.reload.monitored).not_to eq(original)
    end

    it "toggles start_at_boot" do
      original = server.start_at_boot
      server.toggle!(:start_at_boot)
      expect(server.reload.start_at_boot).not_to eq(original)
    end
  end
end
