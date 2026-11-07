require 'yaml'
require 'json'
require 'time'
require 'digest'

# The app catalog (docs/plans/apps.md): one manifest per app, <id>.yml. It has a repo of its
# own (CatDogBark/amahi-kai-apps), which the root helper fetches with the update check
# (system.check_update, every 6 hours and on Check now) into FETCHED_DIR, keeping only the manifests that pass its checks; config/apps is the copy
# that comes with Amahi-kai, used until the first fetch. The helper installs from the same files
# (apps.install checks every field); this is what the Apps pages show, plus where an app's data
# and secrets are.
class AppCatalog
  CATALOG_DIR = File.expand_path('../config/apps', __dir__)
  FETCHED_DIR = '/var/lib/amahi-kai/catalog/apps'.freeze
  # What the last fetch found (written by the helper): when, which commit, the apps kept and the
  # ones skipped, and why it failed if it did.
  STATUS_PATH = '/var/lib/amahi-kai/catalog-status.json'.freeze
  # The catalog format this Amahi-kai knows (the helper's CATALOG_FORMAT). An app whose
  # `requires` is higher is listed, but installing it waits for System Update. Format 2 adds
  # `web_tls`; 3, folders kept on a ZFS pool (`kind: dataset`, and `required`); 4, environment
  # names as the app spells them, and generated secrets inside values (`{{secret:NAME}}`); 5,
  # apps reached only through Tailscale, over HTTPS (`access: tailscale`, `{{tailscale_url}}`),
  # and secrets the container gets hashed (`hash: argon2`).
  FORMAT = 5
  # Where the helper keeps each app's folders and generated secrets (outside production: tmp/).
  APPS_ROOT = '/var/lib/amahi-kai/apps'.freeze
  SECRETS_DIR = '/var/lib/amahi-kai/app-secrets'.freeze
  # The copy of an app's data from before its last update (the helper's apps.update), kept
  # BACKUP_DAYS for Undo update; <id>.json describes it.
  BACKUPS_DIR = '/var/lib/amahi-kai/app-backups'.freeze
  BACKUP_DAYS = 30
  # The ZFS pool each app keeps its dataset folders on (the helper's APP_STORAGE), { id => pool }.
  STORAGE_PATH = '/var/lib/amahi-kai/app-storage.json'.freeze
  # The owner's own apps (the helper's APP_CUSTOM, custom.rb): app files kept on this NAS only,
  # written by the root helper, listed with the catalog's and marked custom. One with the id of a
  # catalog app comes first, as the helper installs it, so the catalog's isn't listed.
  CUSTOM_DIR = '/var/lib/amahi-kai/custom-apps'.freeze
  # The definition each app's container was made from (the helper's APP_DEFINITIONS): a custom
  # app's file saved since shows as changes waiting.
  DEFINITIONS_DIR = '/var/lib/amahi-kai/app-definitions'.freeze
  ID = /\A[a-z][a-z0-9]{1,23}\z/
  # A custom app's logo, kept beside its file as <id>.<type> (the helper's APP_LOGO_TYPES): the
  # NAS serves it (CustomAppsController#logo). A logo link in a custom app's file isn't used.
  LOGO_TYPES = { 'png' => 'image/png', 'jpg' => 'image/jpeg', 'webp' => 'image/webp', 'svg' => 'image/svg+xml' }.freeze

  class << self
    # Read again whenever the helper swaps in a newly fetched catalog (a new folder).
    def all
      dir = source_dir
      stamp = [dir, (stat = File.stat(dir)).ino, stat.mtime, custom_stamp]
      @all = nil unless @stamp == stamp
      @stamp = stamp
      @all ||= begin
        custom = Dir[File.join(custom_dir, '*.yml')].select { |path| File.basename(path, '.yml').match?(ID) }
                                                    .filter_map { |path| custom_entry(path) }
        ids = custom.map { |app| app[:identifier] }
        official = Dir[File.join(dir, '*.yml')].filter_map { |path| entry(path) }.reject { |app| ids.include?(app[:identifier]) }
        (official + custom).sort_by { |app| app[:name].downcase }
      end
    end

    def custom_dir
      production? ? CUSTOM_DIR : Rails.root.join('tmp', 'custom-apps').to_s
    end

    # A custom app's file as it was saved, or nil. Found among the files there, never by a path
    # made from the id asked for (the pages pass one from the request).
    def custom_file(id)
      return nil unless id.to_s.match?(ID)

      path = Dir[File.join(custom_dir, '*.yml')].find { |file| File.basename(file, '.yml') == id.to_s }
      path && File.read(path)
    rescue SystemCallError
      nil
    end

    # A custom app's logo, { path:, type:, version: } (version: a short hash of the picture, for its
    # address), or nil. Found among the files there, as custom_file is.
    def custom_logo(id)
      return nil unless id.to_s.match?(ID)

      path = Dir[File.join(custom_dir, '*')].find do |file|
        LOGO_TYPES.key?(File.extname(file).delete_prefix('.')) && File.basename(file, '.*') == id.to_s
      end
      path && { path: path, type: LOGO_TYPES.fetch(File.extname(path).delete_prefix('.')), version: Digest::SHA256.file(path).hexdigest[0, 12] }
    rescue SystemCallError
      nil
    end

    # The fields of the definition the app's container was made from, or nil.
    def definition(id)
      return nil unless id.to_s.match?(ID)

      data = JSON.parse(File.read(File.join(definitions_dir, "#{id}.json")))
      data.is_a?(Hash) ? data : nil
    rescue SystemCallError, JSON::ParserError
      nil
    end

    def definitions_dir
      production? ? DEFINITIONS_DIR : Rails.root.join('tmp', 'app-definitions').to_s
    end

    # The fetched catalog once there is one, else the copy in the code.
    def source_dir
      File.directory?(fetched_dir) ? fetched_dir : CATALOG_DIR
    end

    def fetched_dir
      production? ? FETCHED_DIR : Rails.root.join('tmp', 'catalog', 'apps').to_s
    end

    # { checked_at: Time, tag:, signer:, commit:, apps: [ids], problems: [{ app:, problem: }], error: }
    # from the last fetch, or nil before the first. tag is the signed version it has (catalog-N),
    # and signer the release key that signed it ("release key B"); neither before signed versions.
    def status
      data = JSON.parse(File.read(status_path))
      signer = data['signer'].to_s[/\Arelease-key-([a-z])\z/, 1]
      { checked_at: (Time.iso8601(data['checked_at'].to_s) rescue nil), commit: data['commit'].presence,
        tag: data['tag'].to_s[/\Acatalog-[1-9][0-9]{0,5}\z/], signer: signer && "release key #{signer.upcase}",
        apps: Array(data['apps']).grep(String),
        problems: Array(data['problems']).select { |p| p.is_a?(Hash) }.map { |p| { app: p['app'].to_s, problem: p['problem'].to_s } },
        error: data['error'].presence }
    rescue SystemCallError, JSON::ParserError, TypeError
      nil
    end

    def status_path
      production? ? STATUS_PATH : Rails.root.join('tmp', 'catalog-status.json').to_s
    end

    def find(id)
      all.find { |app| app[:identifier] == id.to_s }
    end

    # What an app reaches out to, as the Apps page says it (the catalog entry's network). It never
    # reaches another app, or the NAS but for its DNS.
    NETWORK_WORDS = {
      'internet' => 'Reaches the internet, not the devices on your network',
      'lan' => 'Reaches the internet and the devices on your network',
      'none' => 'Reaches nothing past the NAS'
    }.freeze

    def network_words(network)
      NETWORK_WORDS.fetch(network.to_s, NETWORK_WORDS['internet'])
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
      @stamp = nil
    end

    # Whether the custom apps' folder changed (an app file saved or removed renames into it)
    def custom_stamp
      stat = File.stat(custom_dir)
      [stat.ino, stat.mtime]
    rescue SystemCallError
      nil
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

    # Whether version tag +a+ is below +b+, by their numbers in order ("4.0.16-ls253" < "4.0.17-ls254");
    # false when either has none, or they're the same numbers (the root helper's version_below?).
    def version_below?(a, b)
      left = a.to_s.scan(/\d+/).map(&:to_i)
      right = b.to_s.scan(/\d+/).map(&:to_i)
      return false if left.empty? || right.empty?

      (left <=> right) == -1
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
      return unless expires > Time.current && info['from'].present?

      # snapshot: its data on a ZFS pool goes back to the snapshot taken then
      { from: info['from'].to_s, taken_at: taken, until: expires, snapshot: info['snapshot'].present? }
    rescue SystemCallError, JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def backups_dir
      production? ? BACKUPS_DIR : Rails.root.join('tmp', 'app-backups').to_s
    end

    # The ZFS pool the app keeps its data on (installed, or kept from an earlier install), or nil.
    def storage_pool(id)
      storage_records[id.to_s]
    end

    # The ids of the apps whose data is on the pool +name+, installed or kept.
    def apps_on_pool(name)
      storage_records.select { |_id, pool| pool == name.to_s }.keys.sort
    end

    def storage_records
      data = JSON.parse(File.read(storage_path))
      data.is_a?(Hash) ? data.select { |id, pool| id.is_a?(String) && pool.is_a?(String) } : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def storage_path
      production? ? STORAGE_PATH : Rails.root.join('tmp', 'app-storage.json').to_s
    end

    private

    # A custom app's entry: its logo is the one kept on the NAS, or none, never its file's link.
    def custom_entry(path)
      found = entry(path) or return nil
      logo = custom_logo(found[:identifier])
      url = Rails.application.routes.url_helpers.custom_apps_logo_path(found[:identifier], v: logo[:version]) if logo
      found.merge(custom: true, logo_url: url)
    end

    # nil for a manifest that can't be read (the helper's checks make that a bug, but one
    # broken entry mustn't take the Apps page down).
    def entry(path)
      data = YAML.safe_load(File.read(path))
      requires = data['requires'].is_a?(Integer) ? data['requires'] : 1
      { identifier: File.basename(path, '.yml'), name: data['name'].to_s, description: data['description'],
        sign_in: (data['sign_in'].strip.presence if data['sign_in'].is_a?(String)),
        requires: requires, installable: requires <= FORMAT, custom: false,
        category: data['category'], logo_url: data['logo'], image: data['image'], web_port: data['web_port'],
        web_tls: data['web_tls'] == true, access: data['access'] == 'tailscale' ? 'tailscale' : 'lan',
        writes_shares: data['writes_shares'] == true, releases: data['releases'],
        # What it reaches out to (the helper's APP_NETWORK_ACCESS): the internet unless it says
        network: %w[lan none].include?(data['network']) ? data['network'] : 'internet',
        # Whether Install asks which shares to give it: an app that works with files in shares
        # says so (`shares: true`), and one that writes in them does too
        uses_shares: data['shares'] == true || data['writes_shares'] == true,
        storage: storage_need(data['folders']),
        ports: Array(data['ports']).map do |p|
          { host: p['host'], container: p['container'], protocol: p['protocol'] || 'tcp',
            label: p['host'] == data['web_port'] ? 'web' : p['label'] }
        end,
        secrets: Array(data['secrets']).map { |s| { env: s['env'], label: s['label'] } } }
    rescue Psych::Exception, SystemCallError, NoMethodError, TypeError => e
      Rails.logger.warn("AppCatalog: #{path}: #{e.message}") if defined?(Rails.logger)
      nil
    end

    # Whether the app keeps folders on a ZFS pool (kind: dataset): :required, :optional or nil, as
    # the helper reads it.
    def storage_need(folders)
      datasets = Array(folders).select { |folder| folder.is_a?(Hash) && folder['kind'] == 'dataset' }
      return nil if datasets.empty?

      datasets.any? { |folder| folder.fetch('required', true) != false } ? :required : :optional
    end

    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
