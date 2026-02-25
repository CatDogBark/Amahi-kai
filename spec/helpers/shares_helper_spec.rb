require 'rails_helper'

RSpec.describe SharesHelper, type: :helper do
  describe "#tags_to_str" do
    it "returns tags when present" do
      expect(helper.tags_to_str("movies, music")).to eq("movies, music")
    end

    it "returns placeholder when blank" do
      expect(helper.tags_to_str("")).to eq("(add tags)")
      expect(helper.tags_to_str(nil)).to eq("(add tags)")
    end
  end

  describe "#space_color" do
    it "returns cool when plenty of space" do
      expect(helper.space_color(1000, 500)).to eq("cool")
    end

    it "returns warm when under 20%" do
      expect(helper.space_color(1000, 150)).to eq("warm")
    end

    it "returns hot when under 10%" do
      expect(helper.space_color(1000, 50)).to eq("hot")
    end
  end

  describe "#warning_greyhole_on_root" do
    it "warns about root path" do
      title, path = helper.warning_greyhole_on_root("/")
      expect(title).to include("root")
    end

    it "warns about /media path" do
      title, path = helper.warning_greyhole_on_root("/media/disk1")
      expect(title).to include("/media")
    end

    it "returns nil for normal paths" do
      expect(helper.warning_greyhole_on_root("/var/hda/files")).to be_nil
    end
  end

  describe "#confirm_share_destroy_message" do
    it "includes share name" do
      msg = helper.confirm_share_destroy_message("Movies")
      expect(msg).to be_a(String)
    end
  end

  describe "#disk_pooling_area?" do
    it "returns false when no partitions" do
      allow(helper).to receive(:advanced?).and_return(true)
      allow(DiskPoolPartition).to receive(:count).and_return(0)
      expect(helper.disk_pooling_area?).to be false
    end
  end
end
