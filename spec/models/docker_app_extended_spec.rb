require 'rails_helper'

RSpec.describe DockerApp, type: :model do
  let(:app) do
    DockerApp.create!(
      identifier: "testapp_#{SecureRandom.hex(4)}",
      name: "Test App",
      image: "testimage:latest",
      status: "stopped",
      host_port: 8080
    )
  end

  describe "#port_mappings" do
    it "returns hash" do
      expect(app.port_mappings).to eq({})
    end

    it "round-trips hash values" do
      app.port_mappings = { "80/tcp" => 9090 }
      app.save!
      expect(app.reload.port_mappings).to eq({ "80/tcp" => 9090 })
    end
  end

  describe "#volume_mappings" do
    it "returns hash" do
      expect(app.volume_mappings).to eq({})
    end

    it "round-trips hash values" do
      app.volume_mappings = { "/host" => "/container" }
      app.save!
      expect(app.reload.volume_mappings).to eq({ "/host" => "/container" })
    end
  end

  describe "#environment" do
    it "returns hash" do
      expect(app.environment).to eq({})
    end

    it "round-trips hash values" do
      app.environment = { "FOO" => "bar" }
      app.save!
      expect(app.reload.environment).to eq({ "FOO" => "bar" })
    end
  end

  describe "#url" do
    it "returns app proxy URL" do
      expect(app.url).to eq("/app/#{app.identifier}")
    end
  end

  describe "#effective_container_name" do
    it "returns amahi-identifier when no container_name" do
      app.container_name = nil
      expect(app.effective_container_name).to eq("amahi-#{app.identifier}")
    end

    it "returns container_name when set" do
      app.container_name = "custom-name"
      expect(app.effective_container_name).to eq("custom-name")
    end
  end

  describe "#refresh_status!" do
    it "does nothing when no container_name" do
      app.update!(container_name: nil)
      expect { app.refresh_status! }.not_to raise_error
    end
  end

  describe "#uninstall!" do
    it "resets status to available" do
      app.update!(status: "running", container_name: "amahi-test")
      allow(app).to receive(:system).and_return(true)
      app.uninstall!
      expect(app.reload.status).to eq("available")
      expect(app.container_name).to be_nil
    end
  end

  describe "#start!" do
    it "raises when docker not available" do
      app.update!(container_name: "amahi-test")
      allow(Shell).to receive(:run).and_return(false)
      expect { app.start! }.to raise_error(RuntimeError)
      expect(app.reload.status).to eq("error")
    end
  end

  describe "#restart!" do
    it "updates status to running" do
      app.update!(container_name: "amahi-test")
      allow(app).to receive(:system).and_return(true)
      app.restart!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "validations" do
    it "requires identifier" do
      a = DockerApp.new(name: "Test", image: "img", status: "stopped")
      expect(a).not_to be_valid
    end

    it "requires name" do
      a = DockerApp.new(identifier: "test", image: "img", status: "stopped")
      expect(a).not_to be_valid
    end

    it "requires image" do
      a = DockerApp.new(identifier: "test", name: "Test", status: "stopped")
      expect(a).not_to be_valid
    end

    it "enforces unique identifier" do
      ident = "dup_test_#{SecureRandom.hex(4)}"
      DockerApp.create!(identifier: ident, name: "A", image: "img:1", status: "stopped")
      dup = DockerApp.new(identifier: ident, name: "B", image: "img:2", status: "stopped")
      expect(dup).not_to be_valid
    end
  end
end
