require 'rails_helper'

RSpec.describe Server, type: :model do
  before do
    # Stub all Command execution to prevent real system calls
    allow_any_instance_of(Command).to receive(:execute)
    allow_any_instance_of(Command).to receive(:submit).and_return(nil)
  end

  let(:server) { Server.create!(name: "test-svc-#{SecureRandom.hex(4)}", comment: "Test Service", pidfile: "/var/run/test.pid") }

  describe "#clean_name" do
    it "removes @ from name" do
      s = Server.new(name: "openvpn@amahi")
      expect(s.clean_name).to eq("openvpn-amahi")
    end

    it "returns name unchanged when no @" do
      expect(server.clean_name).to eq(server.name)
    end
  end

  describe "#stopped?" do
    it "returns true when no pids" do
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

  describe "#do_start" do
    it "executes without error" do
      server.do_start
    end
  end

  describe "#do_stop" do
    it "executes without error" do
      server.do_stop
    end
  end

  describe "#do_restart" do
    it "executes without error" do
      server.do_restart
    end
  end

  describe ".create_default_servers" do
    it "creates servers" do
      allow(File).to receive(:new).and_call_original
      Server.create_default_servers
      expect(Server.where(name: "smb")).to exist
    end
  end

  describe "validations" do
    it "requires a name" do
      server = Server.new(comment: "Test")
      expect(server).not_to be_valid
    end

    it "requires unique name" do
      Server.create!(name: "unique-test-svc", comment: "A")
      dup = Server.new(name: "unique-test-svc", comment: "B")
      expect(dup).not_to be_valid
    end
  end
end
