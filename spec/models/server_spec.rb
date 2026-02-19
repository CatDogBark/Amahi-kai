require 'spec_helper'

describe Server do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    # Stub system hooks
    allow_any_instance_of(Server).to receive(:create_hook)
    allow_any_instance_of(Server).to receive(:before_save_hook)
    allow_any_instance_of(Server).to receive(:destroy_hook)
  end

  it "should require a name" do
    server = Server.new(name: nil)
    expect(server).not_to be_valid
  end

  it "should require a unique name" do
    Server.create!(name: "smb")
    duplicate = Server.new(name: "smb")
    expect(duplicate).not_to be_valid
  end

  it "should create a valid server" do
    server = Server.create!(name: "nginx", comment: "Web server")
    expect(server).to be_valid
    expect(server.name).to eq("nginx")
    expect(server.comment).to eq("Web server")
  end

  describe "#clean_name" do
    it "should replace @ with -" do
      server = Server.new(name: "openvpn@amahi")
      expect(server.clean_name).to eq("openvpn-amahi")
    end

    it "should return name unchanged if no @" do
      server = Server.new(name: "nginx")
      expect(server.clean_name).to eq("nginx")
    end
  end

  describe "#stopped? and #running?" do
    it "should report stopped when no pids" do
      server = Server.create!(name: "testservice")
      allow(server).to receive(:estimate_pids).and_return([])
      expect(server.stopped?).to be true
      expect(server.running?).to be false
    end

    it "should report running when pids exist" do
      server = Server.create!(name: "testservice2")
      allow(server).to receive(:estimate_pids).and_return(["1234"])
      expect(server.stopped?).to be false
      expect(server.running?).to be true
    end
  end

  it "should allow creating a server without a comment" do
    server = Server.create!(name: "nocomment")
    expect(server.comment).to be_nil
  end

  it "should reject empty name" do
    server = Server.new(name: "")
    expect(server).not_to be_valid
  end

  it "should reject nil name" do
    server = Server.new(name: nil)
    expect(server).not_to be_valid
  end

  describe "#clean_name" do
    it "should handle multiple @ symbols" do
      server = Server.new(name: "a@b@c")
      expect(server.clean_name).to eq("a-b-c")
    end

    it "should handle name with no special characters" do
      server = Server.new(name: "simple")
      expect(server.clean_name).to eq("simple")
    end
  end

  describe "#pids" do
    it "should delegate to estimate_pids" do
      server = Server.create!(name: "pidtest")
      allow(server).to receive(:estimate_pids).and_return(["999"])
      expect(server.pids).to eq(["999"])
    end
  end

  describe "#do_start, #do_stop, #do_restart" do
    it "should execute start command" do
      server = Server.create!(name: "starttest")
      command_double = instance_double(Command)
      allow(Command).to receive(:new).and_return(command_double)
      allow(command_double).to receive(:execute)
      allow(command_double).to receive(:submit)
      expect { server.do_start }.not_to raise_error
    end

    it "should execute stop command" do
      server = Server.create!(name: "stoptest")
      command_double = instance_double(Command)
      allow(Command).to receive(:new).and_return(command_double)
      allow(command_double).to receive(:execute)
      expect { server.do_stop }.not_to raise_error
    end

    it "should execute restart (stop then start)" do
      server = Server.create!(name: "restarttest")
      command_double = instance_double(Command)
      allow(Command).to receive(:new).and_return(command_double)
      allow(command_double).to receive(:submit)
      allow(command_double).to receive(:execute)
      expect { server.do_restart }.not_to raise_error
    end
  end
end
