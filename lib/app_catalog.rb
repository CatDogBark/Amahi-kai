require 'yaml'
require 'json'

# The app catalog (docs/plans/apps.md): one manifest per app in config/apps/<id>.yml. The root
# helper reads the same files to install an app (apps.install, which checks every field); this
# is what the Apps pages show, plus where an app's data and secrets are.
class AppCatalog
  CATALOG_DIR = File.expand_path('../config/apps', __dir__)
  # Where the helper keeps each app's folders and generated secrets (outside production: tmp/).
  APPS_ROOT = '/var/lib/amahi-kai/apps'.freeze
  SECRETS_DIR = '/var/lib/amahi-kai/app-secrets'.freeze

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

    private

    def entry(path)
      data = YAML.safe_load(File.read(path))
      { identifier: File.basename(path, '.yml'), name: data['name'], description: data['description'],
        category: data['category'], logo_url: data['logo'], image: data['image'], web_port: data['web_port'],
        writes_shares: data['writes_shares'] == true,
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
