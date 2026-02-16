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
end
