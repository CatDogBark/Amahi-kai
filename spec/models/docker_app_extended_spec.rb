require 'rails_helper'

RSpec.describe DockerApp, type: :model do
  let(:app) do
    DockerApp.create!(
      identifier: "testapp",
      name: "Test App",
      image: "testimage:latest",
      status: "stopped",
      host_port: 8080,
      container_port: 80
    )
  end

  describe "#port_mappings" do
    it "returns array of port mappings" do
      result = app.port_mappings
      expect(result).to be_an(Array)
    end
  end

  describe "#port_mappings=" do
    it "sets port mappings from array" do
      app.port_mappings = [{ "host" => 9090, "container" => 80 }]
      expect(app.port_mappings).to be_an(Array)
    end
  end

  describe "#volume_mappings" do
    it "returns array" do
      expect(app.volume_mappings).to be_an(Array)
    end
  end

  describe "#volume_mappings=" do
    it "accepts array" do
      app.volume_mappings = [{ "host" => "/data", "container" => "/app/data" }]
      expect(app.volume_mappings).to be_an(Array)
    end
  end

  describe "#environment" do
    it "returns hash" do
      expect(app.environment).to be_a(Hash).or be_an(Array)
    end
  end

  describe "#url" do
    it "returns app proxy URL" do
      expect(app.url).to include("/app/testapp")
    end
  end

  describe "#effective_container_name" do
    it "returns container name based on identifier" do
      expect(app.effective_container_name).to include("testapp")
    end
  end

  describe "#refresh_status!" do
    it "updates status from container" do
      allow(ContainerService).to receive(:status).and_return("running")
      app.refresh_status!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "#install!" do
    it "calls ContainerService to install" do
      allow(ContainerService).to receive(:pull)
      allow(ContainerService).to receive(:create)
      allow(ContainerService).to receive(:start)
      allow(ContainerService).to receive(:status).and_return("running")
      allow(app).to receive(:prepare_host_directories!)
      allow(app).to receive(:write_init_files!)
      app.install!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "#uninstall!" do
    it "calls ContainerService to uninstall" do
      allow(ContainerService).to receive(:stop)
      allow(ContainerService).to receive(:remove)
      app.update!(status: "running")
      app.uninstall!
      expect(app.reload.status).to eq("uninstalled")
    end
  end

  describe "#start!" do
    it "starts the container" do
      allow(ContainerService).to receive(:start)
      allow(ContainerService).to receive(:status).and_return("running")
      app.start!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "#stop!" do
    it "stops the container" do
      allow(ContainerService).to receive(:stop)
      allow(ContainerService).to receive(:status).and_return("stopped")
      app.update!(status: "running")
      app.stop!
      expect(app.reload.status).to eq("stopped")
    end
  end

  describe "#restart!" do
    it "restarts the container" do
      allow(ContainerService).to receive(:restart)
      allow(ContainerService).to receive(:status).and_return("running")
      app.restart!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "validations" do
    it "requires identifier" do
      app = DockerApp.new(name: "Test", image: "img")
      expect(app).not_to be_valid
    end

    it "requires name" do
      app = DockerApp.new(identifier: "test", image: "img")
      expect(app).not_to be_valid
    end

    it "requires image" do
      app = DockerApp.new(identifier: "test", name: "Test")
      expect(app).not_to be_valid
    end

    it "enforces unique identifier" do
      DockerApp.create!(identifier: "dup_test", name: "A", image: "img:1", status: "stopped")
      dup = DockerApp.new(identifier: "dup_test", name: "B", image: "img:2", status: "stopped")
      expect(dup).not_to be_valid
    end
  end
end
