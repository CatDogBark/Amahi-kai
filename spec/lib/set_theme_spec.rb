require 'spec_helper'

RSpec.describe SetTheme do
  describe ".default" do
    it "returns the configured default theme" do
      expect(SetTheme.default).to eq(Yetting.default_theme)
    end
  end

  describe ".find" do
    it "returns a SetTheme instance" do
      theme = SetTheme.find
      expect(theme).to be_a(SetTheme)
    end

    it "has a name attribute" do
      theme = SetTheme.find
      expect(theme.name).to be_a(String)
    end

    it "has a path attribute" do
      theme = SetTheme.find
      expect(theme.path).not_to be_nil
    end
  end

  describe "theme name from the setting" do
    let(:evil_dir) { Rails.root.join("tmp", "evil_theme") }

    before do
      SetTheme.instance_variable_set(:@info, nil)
      FileUtils.mkdir_p(evil_dir)
      File.write(evil_dir.join("init.rb"), "$amahi_evil_theme_loaded = true\n")
      $amahi_evil_theme_loaded = nil
    end

    after { FileUtils.rm_rf(evil_dir) }

    it "ignores a name that climbs out of public/themes" do
      Setting.set('theme', '../../tmp/evil_theme')
      theme = SetTheme.find
      expect(theme.path).to eq(SetTheme.default)
      expect($amahi_evil_theme_loaded).to be_nil
    end

    it "loads a theme's init.rb once, not on every request" do
      Setting.set('theme', SetTheme.default)
      expect(SetTheme).to receive(:init).once.and_call_original
      3.times { SetTheme.find }
    end
  end

  describe "#initialize" do
    it "sets attributes from a hash" do
      theme = SetTheme.new(name: "test", author_name: "nobody", path: "default")
      expect(theme.name).to eq("test")
      expect(theme.author).to eq("nobody")
      expect(theme.path).to eq("default")
    end
  end
end
