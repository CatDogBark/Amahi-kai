require 'spec_helper'

RSpec.describe SystemUtils do
  describe ".uptime" do
    it "returns uptime string" do
      result = SystemUtils.uptime
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe ".run" do
    it "executes a command and returns output" do
      result = SystemUtils.run("echo hello")
      expect(result.strip).to eq("hello")
    end

    it "returns empty string for commands with no output" do
      result = SystemUtils.run("true")
      expect(result).to eq("")
    end
  end
end
