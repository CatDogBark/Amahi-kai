require 'spec_helper'

describe DockerApp do
  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  def build_app(attrs = {})
    defaults = {
      identifier: "test-app",
      name: "Test App",
      image: "test/app:latest",
      status: "available"
    }
    DockerApp.new(defaults.merge(attrs))
  end

  describe "validations" do
    it "requires identifier" do
      expect(build_app(identifier: nil)).not_to be_valid
    end

    it "requires name" do
      expect(build_app(name: nil)).not_to be_valid
    end

    it "requires image" do
      expect(build_app(image: nil)).not_to be_valid
    end

    it "requires valid status" do
      expect(build_app(status: "invalid")).not_to be_valid
    end

    it "accepts valid statuses" do
      %w[available pulling installing running stopped error].each do |s|
        expect(build_app(status: s)).to be_valid
      end
    end

    it "enforces unique identifier" do
      build_app.save!
      expect(build_app(name: "Other")).not_to be_valid
    end
  end

  describe "JSON accessors" do
    it "serializes port_mappings" do
      app = build_app
      app.port_mappings = { "80" => "8080" }
      app.save!
      app.reload
      expect(app.port_mappings).to eq({ "80" => "8080" })
    end

    it "serializes volume_mappings" do
      app = build_app
      app.volume_mappings = { "/data" => "/var/hda/apps/test/data" }
      app.save!
      app.reload
      expect(app.volume_mappings).to eq({ "/data" => "/var/hda/apps/test/data" })
    end

    it "serializes environment" do
      app = build_app
      app.environment = { "PUID" => "1000" }
      app.save!
      app.reload
      expect(app.environment).to eq({ "PUID" => "1000" })
    end

    it "returns empty hash for nil values" do
      app = build_app
      expect(app.port_mappings).to eq({})
      expect(app.volume_mappings).to eq({})
      expect(app.environment).to eq({})
    end
  end

  describe "#effective_container_name" do
    it "returns container_name if set" do
      app = build_app(container_name: "my-container")
      expect(app.effective_container_name).to eq("my-container")
    end

    it "returns amahi-identifier if container_name not set" do
      app = build_app(identifier: "nextcloud")
      expect(app.effective_container_name).to eq("amahi-nextcloud")
    end
  end

  describe "scopes" do
    before do
      build_app(identifier: "app1", status: "running").save!
      build_app(identifier: "app2", name: "App 2", status: "stopped").save!
      build_app(identifier: "app3", name: "App 3", status: "running", category: "media").save!
    end

    it "running scope returns only running apps" do
      expect(DockerApp.running.count).to eq(2)
    end

    it "by_category filters by category" do
      expect(DockerApp.by_category("media").count).to eq(1)
    end
  end

  describe "#install!" do
    it "installs and updates status to running" do
      app = build_app
      app.save!
      app.install!
      expect(app.reload.status).to eq("running")
      expect(app.container_name).to eq("amahi-test-app")
    end
  end

  describe "#uninstall!" do
    it "uninstalls and resets status" do
      app = build_app(status: "running", container_name: "amahi-test-app")
      app.save!
      app.uninstall!
      expect(app.reload.status).to eq("available")
      expect(app.container_name).to be_nil
    end
  end

  describe "#start!" do
    it "starts and sets status to running", :docker do
      app = build_app(status: "stopped", container_name: "amahi-test-app")
      app.save!
      app.start!
      expect(app.reload.status).to eq("running")
    end
  end

  describe "#stop!" do
    it "stops and sets status to stopped" do
      app = build_app(status: "running", container_name: "amahi-test-app")
      app.save!
      app.stop!
      expect(app.reload.status).to eq("stopped")
    end
  end
end
