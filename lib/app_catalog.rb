require 'yaml'
require 'json'
require 'time'

# The app catalog (docs/plans/apps.md): one manifest per app in config/apps/<id>.yml. The root
# helper reads the same files to install an app (apps.install, which checks every field); this
# is what the Apps pages show, plus where an app's data and secrets are.
class AppCatalog
  CATALOG_DIR = File.expand_path('../config/apps', __dir__)
  # Where the helper keeps each app's folders and generated secrets (outside production: tmp/).
  APPS_ROOT = '/var/lib/amahi-kai/apps'.freeze
  SECRETS_DIR = '/var/lib/amahi-kai/app-secrets'.freeze
  # The copy of an app's data from before its last update (the helper's apps.update), kept
  # BACKUP_DAYS for Undo update; <id>.json describes it.
  BACKUPS_DIR = '/var/lib/amahi-kai/app-backups'.freeze
  BACKUP_DAYS = 30

  class << self
    def all
      @all ||= Dir[File.join(CATALOG_DIR, '*.yml')].map { |path| entry(path) }.sort_by { |app| app[:name].downcase }
    end

    def find(id)
      all.find { |app| app[:identifier] == id.to_s }
    end

    def by_category(category)
      all.select { |app| app[:category] == category.to_s }
    end

    def search(query)
      q = query.to_s.downcase
      all.select { |app| app[:name].downcase.include?(q) || app[:description].to_s.downcase.include?(q) }
    end

    def categories
      all.map { |app| app[:category] }.compact.uniq.sort
    end

    def reload!
      @all = nil
    end

    # The app's folders are still there from an earlier install (uninstall keeps them).
    def data_kept?(id)
      File.directory?(File.join(apps_root, id.to_s))
    end

    def apps_root
      production? ? APPS_ROOT : Rails.root.join('tmp', 'apps').to_s
    end

    # [{ label:, value: }] for the app's generated secrets, in its manifest's order, for admins;
    # [] when there are none (or the app isn't installed yet).
    def secrets(id)
      app = find(id) or return []
      values = JSON.parse(File.read(File.join(secrets_dir, "#{app[:identifier]}.json")))
      app[:secrets].filter_map { |secret| { label: secret[:label], value: values[secret[:env]] } if values[secret[:env]] }
    rescue SystemCallError, JSON::ParserError
      []
    end

    def secrets_dir
      production? ? SECRETS_DIR : Rails.root.join('tmp', 'app-secrets').to_s
    end

    # "1.37.3" for vaultwarden/server:1.37.3@sha256:...
    def tag(image)
      image.to_s.sub(/@.*/, '').split(':', 2)[1]
    end

    # The release notes for the version +image+ runs (the manifest's releases, {version} being
    # the tag's leading number), or nil.
    def releases_url(id, image)
      app = find(id) or return nil
      version = tag(image).to_s[/\A\d+(?:\.\d+)*/]
      app[:releases].sub('{version}', version) if app[:releases].present? && version
    end

    # { from: image, taken_at: Time, until: Time } for the copy from before the app's last update,
    # or nil when there's none to undo to.
    def backup(id)
      info = JSON.parse(File.read(File.join(backups_dir, "#{id}.json")))
      taken = Time.iso8601(info['taken_at'].to_s)
      expires = taken + BACKUP_DAYS.days
      { from: info['from'].to_s, taken_at: taken, until: expires } if expires > Time.current && info['from'].present?
    rescue SystemCallError, JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def backups_dir
      production? ? BACKUPS_DIR : Rails.root.join('tmp', 'app-backups').to_s
    end

    private

    def entry(path)
      data = YAML.safe_load(File.read(path))
      { identifier: File.basename(path, '.yml'), name: data['name'], description: data['description'],
        category: data['category'], logo_url: data['logo'], image: data['image'], web_port: data['web_port'],
        writes_shares: data['writes_shares'] == true, releases: data['releases'],
        ports: Array(data['ports']).map do |p|
          { host: p['host'], container: p['container'], protocol: p['protocol'] || 'tcp',
            label: p['host'] == data['web_port'] ? 'web' : p['label'] }
        end,
        secrets: Array(data['secrets']).map { |s| { env: s['env'], label: s['label'] } } }
    end

    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
