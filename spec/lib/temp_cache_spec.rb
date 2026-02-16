require 'spec_helper'

RSpec.describe TempCache do
  describe ".unique_filename" do
    it "returns a path inside HDA_TMP_DIR" do
      filename = TempCache.unique_filename("test")
      expect(filename).to start_with(HDA_TMP_DIR)
    end

    it "includes the base name" do
      filename = TempCache.unique_filename("myfile")
      expect(filename).to include("myfile")
    end

    it "generates different names on repeated calls" do
      names = 5.times.map { TempCache.unique_filename("test") }
      # Names include random component, so most should be unique
      expect(names.uniq.size).to be > 1
    end
  end
end
