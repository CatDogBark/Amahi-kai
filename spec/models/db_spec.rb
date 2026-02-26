require 'spec_helper'

describe Db do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  let(:db) { Db.new(name: "testdb") }

  describe "#username" do
    it "returns the name" do
      expect(db.username).to eq("testdb")
    end
  end

  describe "#password" do
    it "returns the name" do
      expect(db.password).to eq("testdb")
    end
  end

  describe "#hostname" do
    it "returns localhost" do
      expect(db.hostname).to eq("localhost")
    end
  end

  describe "DB_BACKUPS_DIR" do
    it "is set to /var/hda/dbs" do
      expect(Db::DB_BACKUPS_DIR).to eq("/var/hda/dbs")
    end
  end

  describe "#after_create_hook" do
    it "is skipped in non-production environment" do
      expect(Rails.env.production?).to be false
      # If the hook ran, it would call execute with CREATE DATABASE etc.
      # In non-production it returns early, so we just verify creation succeeds
      # without any SQL errors (no actual DB creation commands are run)
      db_record = Db.create!(name: "testcreatedb")
      expect(db_record).to be_persisted
    end
  end

  describe "#after_destroy_hook" do
    it "is skipped in non-production environment" do
      expect(Rails.env.production?).to be false
      db_record = Db.create!(name: "testdestroydb")
      # In non-production, system() should never be called (no mysqldump)
      expect_any_instance_of(Db).not_to receive(:system)
      db_record.destroy!
    end
  end
end
