require 'spec_helper'

RSpec.describe SampleData do
  describe ".load" do
    it "loads servers sample data as an array of hashes" do
      data = SampleData.load('servers')
      expect(data).to be_an(Array)
      expect(data).not_to be_empty
      expect(data.first).to be_a(Hash)
    end

    it "servers have expected attributes" do
      data = SampleData.load('servers')
      server = data.first
      expect(server).to have_key("name")
    end

    it "raises for nonexistent files" do
      expect { SampleData.load('nonexistent_xyz') }.to raise_error(Errno::ENOENT)
    end
  end
end
