require "spec_helper"
require "app_catalog"

RSpec.describe AppCatalog do
  before { AppCatalog.reload! }

  describe ".all" do
    it "returns all 14 apps" do
      expect(AppCatalog.all.size).to eq(14)
    end

    it "includes identifier and name in each entry" do
      first = AppCatalog.all.first
      expect(first).to have_key(:identifier)
      expect(first).to have_key(:name)
      expect(AppCatalog.all.all? { |a| a.key?(:identifier) && a.key?(:name) }).to be true
    end
  end

  describe ".find" do
    it "finds an app by identifier" do
      app = AppCatalog.find("jellyfin")
      expect(app[:name]).to eq("Jellyfin")
      expect(app[:image]).to eq("jellyfin/jellyfin")
    end

    it "returns nil for unknown id" do
      expect(AppCatalog.find("nonexistent")).to be_nil
    end
  end

  describe ".by_category" do
    it "filters apps by category" do
      media = AppCatalog.by_category("media")
      expect(media.map { |a| a[:identifier] }).to include("jellyfin")
    end

    it "returns empty array for unknown category" do
      expect(AppCatalog.by_category("gaming")).to eq([])
    end
  end

  describe ".search" do
    it "matches on name" do
      results = AppCatalog.search("Grafana")
      expect(results.size).to eq(1)
      expect(results.first[:identifier]).to eq("grafana")
    end

    it "matches on description" do
      results = AppCatalog.search("password")
      expect(results.size).to eq(1)
      expect(results.first[:identifier]).to eq("vaultwarden")
    end

    it "is case-insensitive" do
      results = AppCatalog.search("docker")
      expect(results.size).to be >= 1
    end

    it "returns empty for no match" do
      expect(AppCatalog.search("zzzznotfound")).to eq([])
    end
  end

  describe ".categories" do
    it "returns unique sorted categories" do
      cats = AppCatalog.categories
      expect(cats).to include("media", "productivity", "monitoring")
      expect(cats).to eq(cats.sort)
    end
  end
end
