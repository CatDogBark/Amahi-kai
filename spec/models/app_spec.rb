require 'spec_helper'

RSpec.describe App, type: :model do
  # App overrides initialize() to require AmahiApi data.
  # For testing, we insert records directly via SQL.

  def create_app(attrs = {})
    defaults = {
      name: "TestApp",
      identifier: "test-app-#{SecureRandom.hex(4)}",
      installed: true,
      show_in_dashboard: false,
      status: "live",
      created_at: Time.current,
      updated_at: Time.current
    }
    merged = defaults.merge(attrs)
    cols = merged.keys.map(&:to_s)
    vals = merged.values.map { |v| v.nil? ? "NULL" : ActiveRecord::Base.connection.quote(v) }
    sql = "INSERT INTO apps (#{cols.join(',')}) VALUES (#{vals.join(',')})"
    ActiveRecord::Base.connection.execute(sql)
    App.find_by(identifier: merged[:identifier])
  end

  describe "scopes" do
    before do
      @installed = create_app(name: "Installed", identifier: "inst-1", installed: true, show_in_dashboard: false)
      @dashboard = create_app(name: "Dashboard", identifier: "dash-1", installed: true, show_in_dashboard: true)
      @uninstalled = create_app(name: "NotInstalled", identifier: "uninst-1", installed: false)
    end

    it ".installed returns only installed apps" do
      expect(App.installed).to include(@installed, @dashboard)
      expect(App.installed).not_to include(@uninstalled)
    end

    it ".in_dashboard returns installed apps shown in dashboard" do
      expect(App.in_dashboard).to include(@dashboard)
      expect(App.in_dashboard).not_to include(@installed, @uninstalled)
    end

    it ".latest_first orders by updated_at desc" do
      @installed.update_column(:updated_at, 1.day.ago)
      @dashboard.update_column(:updated_at, Time.current)
      result = App.latest_first.to_a
      expect(result.index(@dashboard)).to be < result.index(@installed)
    end
  end

  describe "#theme?" do
    it "returns true when theme_id is present" do
      app = create_app(theme_id: 1)
      expect(app.theme?).to be true
    end

    it "returns false when theme_id is nil" do
      app = create_app
      expect(app.theme?).to be false
    end
  end

  describe "#testing?" do
    it "returns true for testing status" do
      app = create_app(status: "testing")
      expect(app).to be_testing
    end

    it "returns false for live status" do
      app = create_app(status: "live")
      expect(app).not_to be_testing
    end
  end

  describe "#live?" do
    it "returns true for live status" do
      app = create_app(status: "live")
      expect(app).to be_live
    end

    it "returns false for testing status" do
      app = create_app(status: "testing")
      expect(app).not_to be_live
    end
  end

  describe "#has_dependents?" do
    it "returns false when no children" do
      app = create_app
      expect(app.has_dependents?).to be false
    end
  end

  describe ".installation_message" do
    it "returns preparing for 0%" do
      expect(App.installation_message(0)).to match(/Preparing/)
    end

    it "returns retrieving for 10%" do
      expect(App.installation_message(10)).to match(/Retrieving/)
    end

    it "returns installed for 100%" do
      expect(App.installation_message(100)).to match(/installed/)
    end

    it "returns failed for 999" do
      expect(App.installation_message(999)).to match(/failed/)
    end

    it "returns another app for 950" do
      expect(App.installation_message(950)).to match(/Another app/)
    end

    it "returns unknown for unexpected values" do
      expect(App.installation_message(55)).to match(/unknown/)
    end
  end

  describe ".update_progress" do
    it "writes progress to cache" do
      App.update_progress(42)
      expect(Rails.cache.read("progress")).to eq(42)
    end
  end

  describe ".check_availability" do
    before do
      Rails.cache.delete("progress")
      Rails.cache.delete("type")
      Rails.cache.delete("app-id")
    end

    it "returns true when no progress cached" do
      expect(App.check_availability).to be true
    end

    it "returns true when progress is 999 (error)" do
      Rails.cache.write("progress", 999)
      expect(App.check_availability).to be true
    end

    it "returns true when install completed" do
      Rails.cache.write("progress", 100)
      Rails.cache.write("type", "install")
      expect(App.check_availability).to be true
    end

    it "returns true when uninstall completed" do
      Rails.cache.write("progress", 0)
      Rails.cache.write("type", "uninstall")
      expect(App.check_availability).to be true
    end

    it "returns false when install in progress" do
      Rails.cache.write("progress", 40)
      Rails.cache.write("type", "install")
      expect(App.check_availability).to be false
    end

    it "returns false when uninstall in progress" do
      Rails.cache.write("progress", 60)
      Rails.cache.write("type", "uninstall")
      expect(App.check_availability).to be false
    end
  end

  describe ".installation_status" do
    before do
      Rails.cache.delete("progress")
      Rails.cache.delete("type")
      Rails.cache.delete("app-id")
    end

    it "returns cached progress for matching identifier" do
      Rails.cache.write("app-id", "my-app")
      Rails.cache.write("progress", 42)
      expect(App.installation_status("my-app")).to eq(42)
    end

    it "returns 950 for non-matching identifier" do
      Rails.cache.write("app-id", "other-app")
      Rails.cache.write("progress", 42)
      expect(App.installation_status("my-app")).to eq(950)
    end
  end

  describe ".available" do
    it "returns empty array when AmahiApi raises" do
      expect(App.available).to eq([])
    end
  end

  describe "#full_url" do
    it "uses webapp url when webapp exists" do
      webapp = Webapp.create!(name: "myapp", path: "/tmp/test", deletable: false)
      app = create_app(webapp_id: webapp.id)
      expect(app.full_url).to include("myapp")
    end

    it "falls back to app_url and domain" do
      app = create_app(app_url: "testapp")
      domain = Setting.value_by_name('domain')
      expect(app.full_url).to eq("http://testapp.#{domain}")
    end
  end
end
