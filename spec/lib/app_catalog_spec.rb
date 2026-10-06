require "spec_helper"
require "app_catalog"

# The catalog the Apps pages show, read from the same manifests the root helper installs from
# (config/apps; the helper's own checks are in amahi_helper_apps_spec.rb).
RSpec.describe AppCatalog do
  let(:dir) { Dir.mktmpdir }

  before { AppCatalog.reload! }
  after { FileUtils.rm_rf(dir) }

  describe ".all" do
    it "lists the apps, by name" do
      expect(AppCatalog.all.map { |app| app[:identifier] }).to eq(%w[bittube gitea jellyfin transmission uptimekuma vaultwarden])
    end

    it "gives each app what the pages show" do
      vaultwarden = AppCatalog.find("vaultwarden")
      expect(vaultwarden).to include(name: "Vaultwarden", category: "security", web_port: 8880,
                                     ports: [{ host: 8880, container: 8080, protocol: "tcp", label: "web" }],
                                     secrets: [{ env: "ADMIN_TOKEN", label: "Admin page token (the /admin page)" }])
      expect(vaultwarden[:image]).to start_with("vaultwarden/server:1.37.3@sha256:")
      expect(vaultwarden[:logo_url]).to start_with("https://")
    end

    it "has a logo for each app, on https" do
      AppCatalog.all.each { |app| expect(app[:logo_url]).to start_with("https://"), app[:identifier] }
    end
  end

  # The catalog fetched from its repo (the helper's apps.refresh_catalog) comes first; outside
  # production it lives in tmp/catalog.
  describe "the fetched catalog" do
    let(:fetched) { Rails.root.join("tmp", "catalog", "apps").to_s }
    let(:status_path) { Rails.root.join("tmp", "catalog-status.json").to_s }

    before do
      FileUtils.rm_rf([File.dirname(fetched), status_path])
      FileUtils.mkdir_p(fetched)
      FileUtils.cp(File.join(AppCatalog::CATALOG_DIR, "gitea.yml"), fetched)
      AppCatalog.reload!
    end

    after do
      FileUtils.rm_rf([File.dirname(fetched), status_path])
      AppCatalog.reload!
    end

    it "is what the pages list, read again when the helper swaps in a new one" do
      expect(AppCatalog.source_dir).to eq(fetched)
      expect(AppCatalog.all.map { |app| app[:identifier] }).to eq(%w[gitea])

      fresh = "#{File.dirname(fetched)}.new"
      FileUtils.mkdir_p("#{fresh}/apps")
      FileUtils.cp(File.join(AppCatalog::CATALOG_DIR, "gitea.yml"), "#{fresh}/apps")
      FileUtils.cp(File.join(AppCatalog::CATALOG_DIR, "jellyfin.yml"), "#{fresh}/apps")
      FileUtils.rm_rf(File.dirname(fetched))
      File.rename(fresh, File.dirname(fetched))
      expect(AppCatalog.all.map { |app| app[:identifier] }).to eq(%w[gitea jellyfin])
    end

    it "lists an app that needs a newer Amahi-kai, but not to install, and skips one it can't read" do
      File.write("#{fetched}/future.yml", "name: Future\ndescription: Later.\ncategory: media\nrequires: #{AppCatalog::FORMAT + 1}\n")
      File.write("#{fetched}/broken.yml", "name: [unclosed\n")
      AppCatalog.reload!
      expect(AppCatalog.all.map { |app| app[:identifier] }).to eq(%w[future gitea])
      expect(AppCatalog.find("future")).to include(installable: false, requires: AppCatalog::FORMAT + 1)
      expect(AppCatalog.find("gitea")).to include(installable: true, requires: 1)
    end

    it "says what the last fetch found" do
      expect(AppCatalog.status).to be_nil
      File.write(status_path, { checked_at: "2026-10-06T10:00:00Z", commit: "abc123", apps: %w[gitea],
                                problems: [{ app: "broken", problem: "image must be name:tag@sha256:digest" }], error: nil }.to_json)
      expect(AppCatalog.status).to include(checked_at: Time.utc(2026, 10, 6, 10), commit: "abc123", apps: %w[gitea], error: nil,
                                           problems: [{ app: "broken", problem: "image must be name:tag@sha256:digest" }])
    end
  end

  describe ".find" do
    it "returns nil for an app that isn't in the catalog" do
      expect(AppCatalog.find("portainer")).to be_nil
      expect(AppCatalog.find("../jellyfin")).to be_nil
    end
  end

  describe "filters" do
    it "finds apps by category and by name or description" do
      expect(AppCatalog.by_category("media").map { |app| app[:identifier] }).to eq(%w[bittube jellyfin])
      expect(AppCatalog.by_category("gaming")).to eq([])
      expect(AppCatalog.search("GITEA").map { |app| app[:identifier] }).to eq(["gitea"])
      expect(AppCatalog.search("password").map { |app| app[:identifier] }).to eq(["vaultwarden"])
      expect(AppCatalog.search("zzzznotfound")).to eq([])
    end

    it "lists the categories in order" do
      expect(AppCatalog.categories).to eq(AppCatalog.categories.sort)
      expect(AppCatalog.categories).to include("media", "security")
    end
  end

  describe "versions" do
    it "reads an image's tag and links its release notes" do
      expect(AppCatalog.tag("louislam/uptime-kuma:2.5.5-rootless@sha256:abc")).to eq("2.5.5-rootless")
      expect(AppCatalog.releases_url("uptimekuma", "louislam/uptime-kuma:2.5.5-rootless@sha256:abc"))
        .to eq("https://github.com/louislam/uptime-kuma/releases/tag/2.5.5")
      expect(AppCatalog.releases_url("jellyfin", AppCatalog.find("jellyfin")[:image]))
        .to eq("https://github.com/jellyfin/jellyfin/releases/tag/v12.1")
      expect(AppCatalog.releases_url("portainer", "x:1")).to be_nil
    end
  end

  describe "data and secrets the helper keeps" do
    before do
      allow(AppCatalog).to receive(:apps_root).and_return(dir)
      allow(AppCatalog).to receive(:secrets_dir).and_return(dir)
    end

    it "knows when an app's folders are still there from an earlier install" do
      expect(AppCatalog.data_kept?("gitea")).to be false
      Dir.mkdir(File.join(dir, "gitea"))
      expect(AppCatalog.data_kept?("gitea")).to be true
    end

    it "shows an app's generated secrets with their labels, and nothing when there are none" do
      expect(AppCatalog.secrets("transmission")).to eq([])
      File.write(File.join(dir, "transmission.json"), { "PASS" => "abc123", "OTHER" => "x" }.to_json)
      expect(AppCatalog.secrets("transmission")).to eq([{ label: "Web interface password (user admin)", value: "abc123" }])
      File.write(File.join(dir, "transmission.json"), "not json")
      expect(AppCatalog.secrets("transmission")).to eq([])
      expect(AppCatalog.secrets("portainer")).to eq([])
    end

    it "reads the copy from before the last update while it's kept, 30 days" do
      allow(AppCatalog).to receive(:backups_dir).and_return(dir)
      expect(AppCatalog.backup("gitea")).to be_nil
      taken = 3.days.ago.utc.change(usec: 0)
      File.write(File.join(dir, "gitea.json"), { "taken_at" => taken.iso8601, "from" => "gitea/gitea:1.27.2-rootless@sha256:x" }.to_json)
      expect(AppCatalog.backup("gitea")).to eq(from: "gitea/gitea:1.27.2-rootless@sha256:x", taken_at: taken, until: taken + 30.days)
      File.write(File.join(dir, "gitea.json"), { "taken_at" => 31.days.ago.utc.iso8601, "from" => "x" }.to_json)
      expect(AppCatalog.backup("gitea")).to be_nil
    end

    it "keeps them under /var/lib/amahi-kai in production" do
      allow(AppCatalog).to receive(:apps_root).and_call_original
      allow(AppCatalog).to receive(:secrets_dir).and_call_original
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(AppCatalog.apps_root).to eq("/var/lib/amahi-kai/apps")
      expect(AppCatalog.secrets_dir).to eq("/var/lib/amahi-kai/app-secrets")
    end
  end
end
