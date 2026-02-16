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
end
