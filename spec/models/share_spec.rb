require 'spec_helper'

describe Share do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  it "should have a valid factory" do
    expect(create(:share)).to be_valid
  end

  it "should be invalid without a valid name" do
    expect { create(:share, name: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:share, name: "") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:share, name: "this name is too long because it is over 32 chars") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { 2.times{ create(:share, name: "not_unique") } }.to raise_error(ActiveRecord::RecordInvalid) # name must be unique
  end

  it "keeps a share's extra Samba settings in its own section" do
    expect(build(:share, extras: "veto files = /.DS_Store/\nhide dot files = yes")).to be_valid
    share = build(:share, extras: "veto files = /x/\n[homes]\npath = /etc")
    expect(share).not_to be_valid
    expect(share.errors[:extras]).to eq(["can't open another section ([homes])"])
  end

  it "should be invalid without a valid path" do
    expect { create(:share, path: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:share, path: "this path is too way long because it has more than sixty four characters") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe "a user's accessibility to a share" do

    it "should give a user read and write access if the share has everyone: true" do
      user = create(:user)
      share = create(:share)
      # When everyone=true, access is implicit (not through associations)
      # The users_with_share_access association is only populated when everyone=false
      expect(share.everyone).to be true
    end

    it "should NOT give a user readn and write access if the share has everyone: false" do
      user = create(:user)
      share = create(:share, everyone: false)
      expect(share.users_with_share_access).not_to include(user)
      expect(share.users_with_write_access).not_to include(user)
    end

  end

  describe "associations" do
    it "should have many cap_accesses" do
      share = create(:share)
      expect(share).to respond_to(:cap_accesses)
    end

    it "should have many cap_writers" do
      share = create(:share)
      expect(share).to respond_to(:cap_writers)
    end

    it "should have many share_files" do
      share = create(:share)
      expect(share).to respond_to(:share_files)
    end
  end

  describe "name validation edge cases" do
    it "should reject names with only spaces" do
      expect { create(:share, name: "   ") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should reject names starting with a space" do
      expect { create(:share, name: " leading") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should allow names with internal spaces" do
      expect(create(:share, name: "My Share")).to be_valid
    end

    it "should enforce case-insensitive uniqueness" do
      create(:share, name: "TestShare")
      expect { create(:share, name: "testshare") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should allow exactly 32 character names" do
      expect(create(:share, name: "a" * 32)).to be_valid
    end
  end

  describe ".default_full_path" do
    it "should return path under DEFAULT_SHARES_ROOT" do
      expect(Share.default_full_path("Books")).to eq("/var/lib/amahi-kai/files/books")
    end

    it "should downcase the name" do
      expect(Share.default_full_path("MOVIES")).to eq("/var/lib/amahi-kai/files/movies")
    end
  end

  describe "#toggle_visible!" do
    it "should toggle visible from true to false" do
      share = create(:share, visible: true)
      share.toggle_visible!
      expect(share.reload.visible).to eq(false)
    end

    it "should toggle visible from false to true" do
      share = create(:share, visible: false)
      share.toggle_visible!
      expect(share.reload.visible).to eq(true)
    end
  end

  describe "#toggle_readonly!" do
    it "should toggle rdonly" do
      share = create(:share, rdonly: false)
      share.toggle_readonly!
      expect(share.reload.rdonly).to eq(true)
    end
  end

  describe "default ordering" do
    it "should order by name" do
      create(:share, name: "Zebra")
      create(:share, name: "Alpha")
      names = Share.by_name.map(&:name)
      expect(names).to eq(names.sort)
    end
  end

end
