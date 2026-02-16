require 'spec_helper'

RSpec.describe Tab do
  describe ".all" do
    it "returns an array of tabs" do
      expect(Tab.all).to be_an(Array)
    end
  end

  describe ".find" do
    it "finds a tab by controller name" do
      # Tabs are registered during app initialization
      tabs = Tab.all
      if tabs.any?
        first_tab = tabs.first
        found = Tab.find(first_tab.id)
        expect(found).to eq(first_tab)
      end
    end

    it "returns nil for nonexistent tab" do
      expect(Tab.find("nonexistent_tab_xyz")).to be_nil
    end
  end

  describe "#add" do
    it "adds a subtab" do
      original_tabs = Tab.all.dup
      tab = Tab.new("test_parent", "Test", "/test", nil)
      tab.add("settings", "Settings")
      expect(tab.subtabs.size).to eq(1)
      expect(tab.subtabs.first.label).to eq("Settings")
      expect(tab.subtabs.first.url).to eq("/test/settings")
      # Clean up
      AmahiHDA::Application.config.tabs.delete(tab)
    end

    it "uses parent url for index action" do
      tab = Tab.new("test_idx", "Test", "/test", nil)
      tab.add("index", "Index")
      expect(tab.subtabs.first.url).to eq("/test")
      AmahiHDA::Application.config.tabs.delete(tab)
    end
  end

  describe "#subtabs?" do
    it "returns false when no subtabs" do
      tab = Tab.new("test_empty", "Empty", "/empty", nil)
      expect(tab.subtabs?).to be false
      AmahiHDA::Application.config.tabs.delete(tab)
    end

    it "returns true when subtabs exist" do
      tab = Tab.new("test_sub", "Sub", "/sub", nil)
      tab.add("child", "Child")
      expect(tab.subtabs?).to be true
      AmahiHDA::Application.config.tabs.delete(tab)
    end
  end

  describe ".ischild" do
    it "returns true when controller is a subtab" do
      tab = Tab.new("test_parent2", "Parent", "/parent", nil)
      tab.add("child_action", "Child")
      expect(Tab.ischild("child_action", tab)).to be true
      AmahiHDA::Application.config.tabs.delete(tab)
    end

    it "returns false when controller is not a subtab" do
      tab = Tab.new("test_parent3", "Parent", "/parent", nil)
      tab.add("other", "Other")
      expect(Tab.ischild("nonexistent", tab)).to be false
      AmahiHDA::Application.config.tabs.delete(tab)
    end
  end

  describe "#basic_subtabs" do
    it "excludes advanced subtabs" do
      tab = Tab.new("test_basic", "Basic", "/basic", nil)
      tab.add("normal", "Normal")
      tab.add("adv", "Advanced", true)
      expect(tab.basic_subtabs.size).to eq(1)
      expect(tab.basic_subtabs.first.label).to eq("Normal")
      AmahiHDA::Application.config.tabs.delete(tab)
    end
  end
end
