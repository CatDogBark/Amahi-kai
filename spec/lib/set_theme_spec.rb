require 'spec_helper'

RSpec.describe SetTheme do
  describe ".default" do
    it "returns 'default'" do
      expect(SetTheme.default).to eq("default")
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

  describe "#initialize" do
    it "sets attributes from a hash" do
      theme = SetTheme.new(name: "test", author_name: "nobody", path: "default")
      expect(theme.name).to eq("test")
      expect(theme.author).to eq("nobody")
      expect(theme.path).to eq("default")
    end
  end
end
