require 'spec_helper'

describe Plugin do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  it "should create a plugin with name and path" do
    plugin = Plugin.create!(name: "Test Plugin", path: "/tab/test_plugin")
    expect(plugin).to be_valid
    expect(plugin.name).to eq("Test Plugin")
    expect(plugin.path).to eq("/tab/test_plugin")
  end

  it "should persist and be retrievable" do
    Plugin.create!(name: "My Plugin", path: "/tab/my_plugin")
    expect(Plugin.count).to be >= 1
    expect(Plugin.last.name).to eq("My Plugin")
  end

  it "should allow nil name and path (no validations on model)" do
    plugin = Plugin.create!(name: nil, path: nil)
    expect(plugin).to be_persisted
  end

  it "should allow duplicate names" do
    Plugin.create!(name: "Dupe", path: "/tab/dupe1")
    plugin2 = Plugin.create!(name: "Dupe", path: "/tab/dupe2")
    expect(plugin2).to be_persisted
  end

  it "should allow empty strings for name and path" do
    plugin = Plugin.create!(name: "", path: "")
    expect(plugin).to be_persisted
  end

  describe "#before_destroy" do
    it "should call before_destroy callback on destroy" do
      plugin = Plugin.create!(name: "Destroyable", path: "/tab/destroyable")
      expect(plugin).to receive(:before_destroy)
      plugin.destroy
    end
  end

  describe "querying" do
    it "should find plugins by name" do
      Plugin.create!(name: "Unique Plugin", path: "/tab/unique")
      expect(Plugin.where(name: "Unique Plugin").count).to eq(1)
    end

    it "should find plugins by path" do
      Plugin.create!(name: "Path Plugin", path: "/tab/path_plugin")
      expect(Plugin.find_by(path: "/tab/path_plugin")).not_to be_nil
    end
  end

  describe "special characters" do
    it "should handle names with special characters" do
      plugin = Plugin.create!(name: "Plugin & <Test> 'Quotes\"", path: "/tab/special")
      expect(plugin.reload.name).to eq("Plugin & <Test> 'Quotes\"")
    end

    it "should handle unicode in names" do
      plugin = Plugin.create!(name: "Plügïn Ñame", path: "/tab/unicode")
      expect(plugin.reload.name).to eq("Plügïn Ñame")
    end
  end
end
