# frozen_string_literal: true

# Docker apps: installing, updating and running the catalog's apps, with their folders, shares,
# ports, secrets and firewall, and checking the catalog.
module AmahiHelper
  APP_IMAGE = %r{\A[a-z0-9]+(?:[._/-][a-z0-9]+)*:[A-Za-z0-9._-]{1,64}@sha256:[0-9a-f]{64}\z}

  APP_FOLDER = /\A[a-z][a-z0-9_-]{0,31}\z/

  APP_ENV_NAME = /\A[A-Z][A-Z0-9_]{0,63}\z/

  APP_SECRET_PLACEHOLDER = /\{\{secret:([A-Z][A-Z0-9_]{0,63})\}\}/

  # Environment names that have an image download and run more code as it starts (linuxserver.io's
  # mods): no manifest sets them.
  APP_REFUSED_ENV = %w[DOCKER_MODS].freeze

  # Each part of a folder's path in an app's container: a plain name, with nothing Docker's mount
  # options read as a separator (, : =).
  APP_PATH_PART = /\A[A-Za-z0-9._-]{1,64}\z/

  APP_MEMORY = /\A[1-9][0-9]{0,4}[mg]\z/

  APP_DEFAULT_MEMORY = '1g'

  # What each app's container may do beyond its memory: a ceiling on its processes, a cap on its
  # logs (Docker keeps them on the system disk), and none of raw sockets (forging traffic to the
  # other containers) or device nodes. Ping works without raw sockets: Docker lets containers use
  # ICMP datagram sockets.
  APP_PIDS_LIMIT = 2048

  APP_LOG_OPTIONS = %w[--log-opt max-size=10m --log-opt max-file=3].freeze

  APP_CAP_DROP = %w[NET_RAW MKNOD].freeze

  # The definition each app's container was made from: its manifest as it was then, with the
  # image the container runs (root:amahi 0640, one file an app). A reinstall that keeps the
  # version, an undo and a roll-back make the container again from it, not from the catalog's
  # newer manifest; an app the catalog dropped is still started, stopped and uninstalled by it.
  APP_DEFINITIONS = '/var/lib/amahi-kai/app-definitions'

  # Copies of the ping an app's manifest names, without its file capability (app_ping_mount):
  # root's, one folder an app, one copy an image.
  APP_PINGS = '/var/lib/amahi-kai/app-pings'

  # apps.follow_dns, run in the background when the NAS's DNS for apps changes (follow_dns_apps_later)
  APPS_FOLLOW_DNS_UNIT = 'amahi-kai-apps-follow-dns'

  # Changes to the records all apps share (APP_PORTS, APP_STORAGE) take this lock, so two apps'
  # jobs at once don't lose each other's writes, nor take the same free port.
  APP_RECORDS_LOCK = '/run/amahi-kai-app-records.lock'

  APP_TAILSCALE_URL = '{{tailscale_url}}'

  ARGON2 = '/usr/bin/argon2'

  ARGON2_SETTINGS = %w[-id -k 19456 -t 2 -p 1 -l 32 -e].freeze

  # A tailnet name, as `tailscale status` gives the NAS's (amahi-kai.tail1234.ts.net)
  TAILNET_NAME = /\A(?=.{1,253}\z)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/

  # Apps on the LAN (mDNS). Avahi announces each installed app with a web page as an HTTP
  # service, "<App> on <hostname>", with a subtype of its own, _<id>._sub._http._tcp, so a device
  # can ask for one app (bitTube Desktop finds bitTube that way). The amahi-app-*.service files
  # in AVAHI_SERVICES are Amahi-kai's; the others aren't touched. UFW lets mDNS in.
  AVAHI_SERVICES = '/etc/avahi/services'

  MDNS_PORT = '5353/udp'

  # Host ports apps can't take: the NAS's own services (SSH, DNS, DHCP, HTTP(S), Samba,
  # Amahi-kai's web UI).
  APP_RESERVED_PORTS = [22, 53, 67, 68, 80, 137, 138, 139, 443, 445, 3000].freeze

  # {{uid}}, {{gid}} and {{timezone}} in a manifest's environment are filled in at install.
  APP_PLACEHOLDERS = /\{\{(uid|gid|timezone)\}\}/

  APP_DATASETS = 'apps'

  # Before an update, an app's dataset is snapshotted (instead of copied) as
  # <pool>/apps/<id>@amahi-update-<UTC time>, and rolled back to if the update fails.
  APP_UPDATE_SNAPSHOT = /\A[a-z][a-z0-9_-]{0,31}\/apps\/[a-z0-9]{1,24}@amahi-update-\d{8}-\d{6}\z/

  # APP_CHAIN's rules are swapped in whole, in one step: rebuilt rule by rule, the chain was
  # empty for a moment, and an empty chain lets everything through.
  IPTABLES_RESTORE = '/usr/sbin/iptables-restore'

  DOCKER_BRIDGE = 'docker0'

  # Shares an app is given (P4.4) appear in it at /shares/<name>. The web app names shares; the
  # helper finds their folders in smb.conf, which only it writes. Shares Greyhole pools are read
  # only (their files change over SMB), and come with their copy folders on each pool drive at
  # the same path, which their files link to.
  APP_SHARE_TARGET = '/shares'

  APP_SHARE_NAME = %r{\A[^/,"'\\\x00-\x1f]{1,64}\z}

  # An app may be given some folders of a share rather than all of it: one appears in the app at
  # /shares/<name>/<folder>, as in the share. A folder in a share, as a choice names it
  # ("media/Pictures"): parts without a control character, a comma or a double quote (Docker's
  # --mount takes those as its own), and none of them . or ..
  APP_SHARE_FOLDER_PART = /\A[^\/\x00-\x1f\x7f,"]+\z/

  # Unlike a share's own folder, made by the helper, a folder in it can be swapped for a link by
  # an app that writes there, and Docker follows a link in a mount's source each time it starts a
  # container (at boot too). So the helper mounts each folder given to an app itself, here, from a
  # handle on the folder that it checked (with_dir), and the app's container mounts that. /run is
  # empty after a restart: amahi-kai-app-shares.service mounts them again before Docker starts
  # (apps.share_binds), from APP_SHARE_BINDS ({ id => [{ 'path', 'share', 'folder' }] }, root only).
  APP_SHARE_BIND_ROOT = '/run/amahi-kai-app-shares'

  MOUNT = '/usr/bin/mount'

  UMOUNT = '/usr/bin/umount'

  SETFACL = '/usr/bin/setfacl'

  # App updates (P4.5). Before an update the helper copies the app's folders (all but those its
  # manifest marks backup: false, like caches) to APP_BACKUPS/<id>/ (root only), described by
  # APP_BACKUPS/<id>.json (root:amahi 0640, for the Apps page's Undo update). One copy per app:
  # the next update replaces it, and apps.prune_backups deletes it after APP_BACKUP_DAYS. If the
  # new version isn't healthy within APP_HEALTH_TIMEOUT, the old one and the copy are put back.
  APP_BACKUPS = '/var/lib/amahi-kai/app-backups'

  APP_BACKUP_MARGIN = 1024**3 # free space to leave after copying


  add_operations(
    # Installs or reinstalls an app from its manifest: its user and folders (kept from an
    # earlier install), its secrets (likewise), the pinned image, pulled with progress, and
    # its container, started, with the shares chosen ([{ "name": "Movies", "write": false }]).
    # Changing an app's shares is a reinstall, which keeps the version it runs and its settings
    # (APP_DEFINITIONS): only apps.update moves it to the manifest's. An app with dataset folders
    # (P4.6) takes the ZFS pool they go on (pool), the first time; after that they stay on theirs
    # (APP_STORAGE). A job of its own (APP_JOBS).
    'apps.install' => {
      params: %w[app shares pool],
      validate: lambda { |a|
        installed!(DOCKER) && app_install_request(a['app']).then do |v|
          v.merge(shares: app_share_choices(a['shares'], v[:id], v[:manifest]), pool: app_pool_choice(v[:id], v[:manifest], a['pool']))
        end
      },
      plan: ->(v) { [[:install_app, v[:id], v[:manifest], v[:shares], true, v[:pool]], [:announce_apps]] }
    },
    # Start, stop and restart go by the app's container, whatever the catalog says now.
    'apps.start' => {
      params: %w[app],
      validate: ->(a) { installed!(DOCKER) && installed_app_request(a['app']) },
      plan: ->(v) { [[DOCKER, 'start', app_container(v[:id])]] }
    },
    'apps.stop' => {
      params: %w[app],
      validate: ->(a) { installed!(DOCKER) && installed_app_request(a['app']) },
      plan: ->(v) { [[DOCKER, 'stop', '--time', '30', app_container(v[:id])]] }
    },
    'apps.restart' => {
      params: %w[app],
      validate: ->(a) { installed!(DOCKER) && installed_app_request(a['app']) },
      plan: ->(v) { [[DOCKER, 'restart', '--time', '30', app_container(v[:id])]] }
    },
    # Updates an installed app to its manifest's version: a copy of its data first, the new
    # version started, and the old version and the copy put back if it isn't healthy in time.
    'apps.update' => {
      params: %w[app shares],
      validate: lambda { |a|
        installed!(DOCKER) && app_request(a['app']).then { |v| v.merge(shares: app_share_choices(a['shares'], v[:id], v[:manifest])) }
      },
      plan: ->(v) { [[:update_app, v[:id], v[:manifest], v[:shares]]] }
    },
    # Puts back the version and data from before the app's last update (within APP_BACKUP_DAYS),
    # with the definition it ran then.
    'apps.undo_update' => {
      params: %w[app shares],
      validate: lambda { |a|
        installed!(DOCKER) && app_undo_request(a['app']).then { |v| v.merge(shares: app_share_choices(a['shares'], v[:id], v[:manifest])) }
      },
      plan: ->(v) { [[:undo_app_update, v[:id], v[:manifest], v[:shares]]] }
    },
    # Deletes pre-update copies older than APP_BACKUP_DAYS. Run daily by amahi-kai-app-backups.timer.
    'apps.prune_backups' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:prune_app_backups]] }
    },
    # Removes an app's container and image. Its folders, secrets, user and definition stay (a
    # reinstall uses them again, on the version it ran) unless delete_data is true. Works when
    # the container is already gone, and for an app the catalog dropped; refused while Docker
    # doesn't answer.
    'apps.uninstall' => {
      params: %w[app delete_data],
      validate: lambda { |a|
        installed!(DOCKER) && docker_running! && { id: app_id(a['app']), delete_data: a.key?('delete_data') ? boolean(a, 'delete_data') : false }
      },
      plan: ->(v) { [[:uninstall_app, v[:id], v[:delete_data]], [:announce_apps]] }
    },
    # Announces the installed apps on the LAN (see AVAHI_SERVICES). Run at every install and
    # uninstall, and by amahi-kai-app-firewall.service each time Docker starts.
    'apps.announce' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:announce_apps]] }
    },
    # Remakes the containers of the apps given pooled shares whose mounts no longer match the
    # pool (do_follow_pool_apps): after a drive joins or leaves it, a share is pooled or turned
    # Off, a pool drive is mounted, and each time Docker starts (amahi-kai-app-firewall.service),
    # when a drive missing at boot would keep an app from starting. Takes nothing from the app.
    'apps.follow_pool' => {
      params: [],
      validate: ->(_a) { installed!(DOCKER) && {} },
      plan: ->(_v) { [[:follow_pool_apps]] }
    },
    # Remakes the containers of the apps whose DNS isn't the NAS's as it is now (app_dns_options):
    # after Unbound starts or stops answering on Docker's bridge (do_dns_config starts this in the
    # background), and each time Docker starts (amahi-kai-app-firewall.service). Takes nothing from
    # the app.
    'apps.follow_dns' => {
      params: [],
      validate: ->(_a) { installed!(DOCKER) && {} },
      plan: ->(_v) { [[:follow_dns_apps]] }
    },
    # Mounts again the folders in shares that apps are given (do_share_binds): /run is empty
    # after a restart. Run by amahi-kai-app-shares.service before Docker starts.
    'apps.share_binds' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:share_binds]] }
    },
    # Limits the apps' ports to the LAN and Tailscale (APP_CHAIN). Run by
    # amahi-kai-app-firewall.service each time Docker starts, and at every install.
    'apps.firewall' => {
      params: [],
      validate: ->(_a) { installed!(DOCKER) && installed!(IPTABLES) && {} },
      plan: ->(_v) { [[:app_firewall]] }
    },
    # Every app container's state, and whether Docker is running. Read-only.
    'apps.status' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:apps_status]] }
    },
    # Every container's published ports, and whether APP_CHAIN limits them, for the security
    # audit. Read-only.
    'docker.published_ports' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:docker_ports]] }
    },
  )

  class << self
    # An existing account the app created: a normal uid with the users group as its
    # primary group. Anything else (root, the install user, system accounts) is refused.
    def app_login(value)
      value = login(value)
      pw = passwd(value) or raise Refused, "#{value} has no Linux account"
      raise Refused, "#{value} is not an account Amahi created" unless app_account?(pw)
      value
    end

    def app_account?(pw)
      pw.uid >= UID_MIN && pw.uid != 65_534 && pw.gid == group_id(USERS_GROUP)
    end

    # --- Apps ---

    def app_request(value)
      id = app_id(value)
      { id: id, manifest: tailscale_ready_for!(app_manifest(id)) }
    end

    def app_id(value)
      id = string(value, 'app', max: 24)
      raise Refused, "app #{id.inspect} isn't one Amahi-kai knows" unless id.match?(APP_ID)
      id
    end

    # An app to install: the definition its container runs, or ran (a reinstall keeps its version
    # and its settings), else the catalog's manifest.
    def app_install_request(value)
      id = app_id(value)
      { id: id, manifest: tailscale_ready_for!(app_definition(id) || app_manifest(id)) }
    end

    # An update to undo: the definition the app ran before it, as its copy recorded it (else, for
    # a copy from before definitions were kept, the one it runs, or the catalog's).
    def app_undo_request(value)
      id = app_id(value)
      before = definition_from(id, Hash(app_backup_info(id))['definition'])
      { id: id, manifest: tailscale_ready_for!(before || app_definition(id) || app_manifest(id)) }
    end

    # An app reached through Tailscale (APP_ACCESS) is refused, before anything changes, while
    # Tailscale can't serve it (tailscale_https_name says what's missing).
    def tailscale_ready_for!(manifest)
      tailscale_https_name if manifest[:access] == 'tailscale'
      manifest
    end

    # An installed app, for start, stop and restart: its container is what counts, not the
    # catalog, which may have moved on or dropped it. Refused while a job changes it.
    def installed_app_request(value)
      id = app_id(value)
      not_in_a_job!(id)
      raise Refused, "#{id} has no container: install it again" unless docker_output('inspect', '--format', '{{.Id}}', app_container(id))
      { id: id }
    end

    # Docker answers: an uninstall while it's stopped left the container, which came back when it
    # started, unlisted.
    def docker_running!
      raise Refused, "Docker isn't running: start it (Apps), then try again" unless docker_output('info', '--format', '{{.ServerVersion}}')

      true
    end

    def app_container(id)
      "amahi-#{id}"
    end

    # Where an app's manifest is: the fetched catalog's, else the code's (see CATALOG_REPO).
    def app_manifest_path(id)
      [File.join(APP_CATALOG, 'apps', "#{id}.yml"), File.join(APP_MANIFESTS, "#{id}.yml")].find { |path| File.file?(path) }
    end

    # An app's manifest, checked field by field. A manifest that fails a check is a bug in the
    # catalog, so it fails rather than being refused; one that needs a newer Amahi-kai is refused.
    def app_manifest(id)
      path = app_manifest_path(id)
      raise Refused, "app #{id.inspect} isn't in Amahi-kai's catalog" unless path
      data = YAML.safe_load(File.read(path))
      raise Failed, "#{path} isn't an app manifest" unless data.is_a?(Hash)
      raise Refused, "#{id} needs a newer Amahi-kai: run System Update first" if manifest_requires(id, data) > CATALOG_FORMAT
      check_manifest(id, data).merge(source: data)
    rescue Psych::Exception => e
      raise Failed, "#{id}'s manifest can't be read: #{e.message}"
    end

    # The definition the app's container was made from (APP_DEFINITIONS): its manifest as it was,
    # checked again, with the image the container runs; nil for a container made before these
    # were kept, or one that no longer passes.
    def app_definition(id)
      definition_from(id, read_json("#{APP_DEFINITIONS}/#{id}.json"))
    end

    # A definition (a manifest's source, with its image) checked again; nil when it isn't one, or
    # no longer passes.
    def definition_from(id, source)
      return nil unless source.is_a?(Hash)

      check_manifest(id, source).merge(source: source)
    rescue Failed
      nil
    end

    def app_record_definition(id, manifest)
      return unless manifest[:source].is_a?(Hash)

      unless File.directory?(APP_DEFINITIONS)
        Dir.mkdir(APP_DEFINITIONS, 0o750)
        File.chown(0, group_id(APP_USER), APP_DEFINITIONS)
      end
      source = manifest[:source].merge('image' => manifest[:image])
      do_install("#{APP_DEFINITIONS}/#{id}.json", "#{JSON.pretty_generate(source)}\n", nil, '0640', APP_USER)
    end

    def app_forget_definition(id)
      FileUtils.rm_f("#{APP_DEFINITIONS}/#{id}.json")
    end

    # The catalog format a manifest needs (`requires`, 1 when it doesn't say).
    def manifest_requires(id, data)
      needs = data.fetch('requires', 1)
      raise Failed, "#{id}'s manifest: requires must be a whole number from 1 to 999" unless needs.is_a?(Integer) && needs.between?(1, 999)
      needs
    end

    # What installing an app takes from its manifest, every field checked.
    def check_manifest(id, data)
      bad = ->(why) { raise Failed, "#{id}'s manifest: #{why}" }
      format = manifest_requires(id, data)
      image = data['image'].to_s
      bad.call('image must be name:tag@sha256:digest') unless image.match?(APP_IMAGE)
      run_as = data['run_as']
      bad.call('run_as must be app or image') unless %w[app image].include?(run_as)
      memory = (data['memory'] || APP_DEFAULT_MEMORY).to_s
      bad.call("memory #{memory.inspect} must be like 512m or 2g") unless memory.match?(APP_MEMORY)
      environment = app_environment_spec(data['environment'], bad, format)
      writes_shares = data.fetch('writes_shares', false)
      bad.call('writes_shares must be true or false') unless [true, false].include?(writes_shares)
      # What writes into shares runs as the app's own user: the whole container (run_as: app),
      # or the image's init drops to it, told by PUID and PGID set to the app's own placeholders
      # (a fixed number, or PUID alone, isn't that).
      drops = environment['PUID'] == '{{uid}}' && environment['PGID'] == '{{gid}}'
      if writes_shares && run_as != 'app' && !drops
        bad.call("an app that writes shares runs as the app's user: run_as: app, or PUID and PGID set to {{uid}} and {{gid}}")
      end
      ports = app_ports(data['ports'], bad)
      web_port = data['web_port']
      bad.call("web_port #{web_port.inspect} must be one of its ports") unless web_port.nil? || ports.any? { |p| p[:host] == web_port }
      web_tls = data.fetch('web_tls', false)
      bad.call('web_tls must be true or false') unless [true, false].include?(web_tls)
      bad.call('web_tls needs a web_port') if web_tls && web_port.nil?
      access = app_access(data, web_port, web_tls, ports, format, bad)
      ping = data['ping']
      unless ping.nil? || (ping.is_a?(String) && normalized_path?(ping) && ping.split('/').drop(1).all? { |part| part.match?(APP_PATH_PART) })
        bad.call("ping #{ping.inspect} must be an absolute, normalized path of plain names")
      end
      folders = app_folders(data['folders'], bad)
      secrets = app_secret_names(data['secrets'], environment, bad, format)
      environment.each do |key, value|
        value.scan(APP_SECRET_PLACEHOLDER).flatten.each do |name|
          bad.call("#{key} has {{secret:#{name}}}, which isn't one of its secrets") unless secrets.include?(name)
        end
        bad.call("#{key} has #{APP_TAILSCALE_URL}, which is for an app with access: tailscale") if value.include?(APP_TAILSCALE_URL) && access != 'tailscale'
      end
      { image: image, run_as: run_as, memory: memory, ports: ports, web_port: web_port, web_tls: web_tls, access: access,
        folders: folders, storage: app_storage_need(folders), environment: environment,
        secrets: secrets, hashed_secrets: app_hashed_secrets(data['secrets']), writes_shares: writes_shares, ping: ping }
    end

    # Who reaches the app (APP_ACCESS): lan unless it says tailscale. That needs requires: 5 (an
    # older Amahi-kai would put the app on the LAN instead of listing it as needing a newer one)
    # and a web page over plain HTTP on a TCP port, for `tailscale serve` to put HTTPS in front of.
    def app_access(data, web_port, web_tls, ports, format, bad)
      access = data.fetch('access', 'lan')
      bad.call('access must be lan or tailscale') unless APP_ACCESS.include?(access)
      return access if access == 'lan'

      bad.call('access: tailscale needs requires: 5') if format < 5
      bad.call('access: tailscale needs a web_port') if web_port.nil?
      bad.call('access: tailscale serves its page over HTTPS itself, so web_tls must be false') if web_tls
      bad.call('access: tailscale needs its web port to be TCP') unless web_port.nil? || ports.any? { |p| p[:host] == web_port && p[:protocol] == 'tcp' }
      access
    end

    def app_ports(list, bad)
      ports = Array(list).map do |port|
        bad.call('a port needs host and container numbers') unless port.is_a?(Hash)
        host = port['host']
        container = port['container']
        protocol = (port['protocol'] || 'tcp').to_s
        bad.call("host port #{host.inspect} must be from 1024 to 65535") unless host.is_a?(Integer) && host.between?(1024, 65_535)
        bad.call("host port #{host} belongs to the NAS") if APP_RESERVED_PORTS.include?(host)
        bad.call("container port #{container.inspect} must be from 1 to 65535") unless container.is_a?(Integer) && container.between?(1, 65_535)
        bad.call("protocol #{protocol.inspect} must be tcp or udp") unless %w[tcp udp].include?(protocol)
        { host: host, container: container, protocol: protocol }
      end
      twice = ports.map { |p| [p[:host], p[:protocol]] }.tally.find { |_port, count| count > 1 }
      bad.call("host port #{twice[0].join('/')} is listed twice") if twice
      ports
    end

    def app_folders(list, bad)
      folders = Array(list).map do |folder|
        bad.call('a folder needs a name and a path') unless folder.is_a?(Hash)
        name = folder['name'].to_s
        path = folder['path'].to_s
        bad.call("folder name #{name.inspect} must be lowercase letters, digits, _ or -") unless name.match?(APP_FOLDER)
        bad.call("folder path #{path.inspect} must be an absolute, normalized path") unless normalized_path?(path)
        bad.call("folder path #{path} must be plain names (letters, digits, . _ -)") unless path.split('/').drop(1).all? { |part| part.match?(APP_PATH_PART) }
        bad.call("folder path #{path} is where the shares go") if path == APP_SHARE_TARGET || path.start_with?("#{APP_SHARE_TARGET}/")
        backup = folder.fetch('backup', true)
        bad.call("folder #{name}'s backup must be true or false") unless [true, false].include?(backup)
        kind = folder.fetch('kind', 'state').to_s
        bad.call("folder #{name}'s kind must be state or dataset") unless %w[state dataset].include?(kind)
        required = folder.fetch('required', true)
        bad.call("folder #{name}'s required must be true or false") unless [true, false].include?(required)
        bad.call("folder #{name}: required is for a dataset folder") if folder.key?('required') && kind != 'dataset'
        { name: name, path: path, backup: backup, kind: kind.to_sym, required: kind == 'dataset' && required }
      end
      bad.call('a folder is listed twice') if folders.map { |f| f[:name] }.uniq.size != folders.size
      bad.call('two folders have the same path') if folders.map { |f| f[:path] }.uniq.size != folders.size
      folders
    end

    # Whether the app keeps folders on a ZFS pool: :required (it can't be installed without one),
    # :optional (it runs without, those folders left out until a pool is chosen) or nil.
    def app_storage_need(folders)
      datasets = folders.select { |folder| folder[:kind] == :dataset }
      return nil if datasets.empty?

      datasets.any? { |folder| folder[:required] } ? :required : :optional
    end

    # The manifest's environment, checked: names like TZ, or as the app spells them with format 4
    # (requires: 4), as are secrets inside values (APP_ENV_NAME_SPELLED), so an Amahi-kai that
    # doesn't know them lists the app as needing a newer one instead of dropping it.
    def app_environment_spec(environment, bad, format = 1)
      environment ||= {}
      bad.call('environment must be a mapping') unless environment.is_a?(Hash)
      environment.to_h do |key, value|
        name = key.to_s
        unless name.match?(APP_ENV_NAME)
          bad.call("environment name #{key.inspect} isn't valid") unless name.match?(APP_ENV_NAME_SPELLED)
          bad.call("environment name #{name} needs requires: 4 (names as the app spells them)") if format < 4
        end
        bad.call("#{name} would have the image download more code as it starts") if APP_REFUSED_ENV.include?(name.upcase)
        bad.call("#{name} must be one line of text") unless value.is_a?(String) && value.length <= 1000 && !value.match?(/[\r\n\0]/)
        bad.call("#{name} has a secret in its value, which needs requires: 4") if format < 4 && value.match?(APP_SECRET_PLACEHOLDER)
        [name, value]
      end
    end

    def app_secret_names(list, environment, bad, format = 1)
      Array(list).map do |secret|
        name = secret.is_a?(Hash) ? secret['env'].to_s : ''
        bad.call("secret #{name.inspect} isn't a valid environment name") unless name.match?(APP_ENV_NAME)
        bad.call("#{name} would have the image download more code as it starts") if APP_REFUSED_ENV.include?(name)
        bad.call("secret #{name} is set in environment too") if environment.key?(name)
        if secret.key?('hash')
          bad.call("secret #{name}'s hash must be #{APP_SECRET_HASHES.join(' or ')}") unless APP_SECRET_HASHES.include?(secret['hash'])
          bad.call("secret #{name}'s hash needs requires: 5") if format < 5
        end
        name
      end
    end

    # The secrets the container gets hashed (APP_SECRET_HASHES); the admin pages show them as made.
    def app_hashed_secrets(list)
      Array(list).select { |secret| secret.is_a?(Hash) && APP_SECRET_HASHES.include?(secret['hash']) }.map { |secret| secret['env'].to_s }
    end

    # [{ name:, path:, pooled:, write: }] for the shares the app is to be given, and folder: for
    # one given only a folder of the share ({ "name": "Vault", "folder": "media/Pictures" }). A
    # share may be given several of its folders, none inside another, or all of it.
    def app_share_choices(value, id, manifest)
      return [] if value.nil?
      raise Refused, 'shares must be a list of at most 32' unless value.is_a?(Array) && value.size <= 32
      shares = samba_shares
      chosen = value.map do |item|
        unless item.is_a?(Hash) && (item.keys - %w[name folder write]).empty?
          raise Refused, 'each share must be {"name": ..., "folder": ..., "write": true or false}'
        end
        share = app_share(string(item['name'], 'share name', max: 64), shares)
        folder = item['folder'].nil? ? nil : app_share_folder(item['folder'])
        if folder && !real_folder?("#{share[:path]}/#{folder}")
          raise Refused, "#{share[:name]}/#{folder} isn't a real folder (a link, or missing)"
        end
        write = item.key?('write') ? boolean(item, 'write') : false
        raise Refused, "#{id} only reads shares" if write && !manifest[:writes_shares]
        raise Refused, "share #{share[:name]} is pooled by Greyhole, so apps can only read it" if write && share[:pooled]
        folder ? share.merge(folder: folder, write: write) : share.merge(write: write)
      end
      chosen.group_by { |share| share[:name] }.each { |name, given| app_share_overlap!(name, given.map { |share| share[:folder] }) }
      chosen
    end

    # The share named +name+ in smb.conf (+shares+, samba_shares), if an app may be given it.
    def app_share(name, shares)
      share = shares[name.downcase] or raise Refused, "#{name.inspect} isn't one of the NAS's shares"
      raise Refused, "share #{share[:name]}'s name can't be a folder in an app" unless share[:name].match?(APP_SHARE_NAME)
      path = share[:path]
      unless normalized_path?(path) && !path.include?(',') && (share_root_of(path) || drive_mount_point?(path))
        raise Refused, "share #{share[:name]}'s folder #{path} isn't in the share root or on a mounted data drive"
      end
      raise Refused, "share #{share[:name]}'s folder #{path} isn't a real folder (a link, or missing)" unless real_folder?(path)
      share
    end

    # A folder in a share, as a choice names it: "media/Pictures".
    def app_share_folder(value)
      folder = string(value, 'folder', max: 255)
      parts = folder.split('/', -1)
      unless parts.all? { |part| part.match?(APP_SHARE_FOLDER_PART) && !%w[. ..].include?(part) }
        raise Refused, "folder #{folder.inspect} must be a folder inside the share, like media/Pictures"
      end
      folder
    end

    # The folders one share is given in (nil: all of it): the share once, or folders none of
    # which is inside another.
    def app_share_overlap!(name, folders)
      return if folders.size == 1
      raise Refused, 'a share is listed twice' if folders.count(nil) > 1
      raise Refused, "#{name} is given whole, so its folders are in it already" if folders.include?(nil)

      folders.combination(2).each do |one, other|
        raise Refused, "#{name}/#{one} is listed twice" if one == other
        outer, inner = [one, other].sort_by(&:length)
        raise Refused, "#{name}/#{inner} is inside #{name}/#{outer}, given too" if inner.start_with?("#{outer}/")
      end
    end

    # A real folder at its own path, no link anywhere on the way: Docker follows links in a mount's
    # source, so a link there would give an app whatever it points to.
    def real_folder?(path)
      File.realpath(path) == path && File.lstat(path).directory?
    rescue SystemCallError
      false
    end

    # A data drive's mount point with the drive mounted there: /mnt/<name>, a real folder.
    def drive_mount_point?(path)
      name = path.delete_prefix("#{drives_root}/")
      path.start_with?("#{drives_root}/") && !name.empty? && !name.include?('/') && real_root?(path)
    end

    def app_running?(id)
      docker_output('inspect', '--format', '{{.State.Running}}', app_container(id)).to_s.strip == 'true'
    end

    def do_install_app(id, manifest, shares = [], keep_version = false, pool = nil)
      if keep_version && (running = app_image(id)) && running != manifest[:image]
        say("Keeping the version it runs (#{image_tag(running)})")
        manifest = manifest.merge(image: running)
      end
      uid, gid = app_account(id)
      dir = "#{APPS_ROOT}/#{id}"
      do_make_dir(APPS_ROOT, '0755')
      app_folder(dir, uid, gid)
      manifest[:folders].each { |folder| app_folder("#{dir}/#{folder[:name]}", uid, gid) if folder[:kind] == :state }
      storage = app_storage(id, manifest, pool, uid, gid)
      secrets = app_secrets(id, manifest[:secrets])
      if image_present?(manifest[:image])
        say("Using #{manifest[:image].sub(/@.*/, '')}, downloaded already")
      else
        say("Pulling #{manifest[:image].sub(/@.*/, '')}...")
        run_command([DOCKER, 'pull', manifest[:image], { stream: true }])
      end
      container = app_container(id)
      ports = app_create_container(id, manifest, shares, uid, gid, dir, storage, secrets)
      shares.select { |share| share[:write] }.each { |share| app_share_writable([share[:path], share[:folder]].compact.join('/')) }
      do_app_firewall
      say('Starting it...')
      run_command([DOCKER, 'start', container])
      { 'app' => id, 'container' => container, 'image' => manifest[:image], 'ports' => ports.map { |p| p.transform_keys(&:to_s) } }
    end

    # Makes the app's new container under a name of its own (<container>-next) while the one it
    # has is only stopped (its ports free for the new one), then swaps it in: a create that fails
    # leaves the app its container, started again if it ran, instead of none. The definition it's
    # made from is recorded (APP_DEFINITIONS). An app reached through Tailscale (APP_ACCESS) is
    # published on the NAS itself only, and served on the tailnet. Returns its ports.
    def app_create_container(id, manifest, shares, uid, gid, dir, storage, secrets)
      container = app_container(id)
      fresh = "#{container}-next"
      tailnet = manifest[:access] == 'tailscale'
      run_command([DOCKER, 'rm', '--force', fresh, { allow_failure: true }]) # one a job cut off left
      running = Hash(app_state(id))['Running'] == true
      run_command([DOCKER, 'stop', '--time', '30', container, { allow_failure: true }]) if running
      begin
        bind = tailnet ? '127.0.0.1' : '0.0.0.0'
        ports = with_records_lock { app_assign_ports(id, manifest[:ports], bind).tap { |given| app_record_ports(id, given) } }
        ports.reject { |p| p[:host] == p[:preferred] }.uniq { |p| p[:host] }.each do |p|
          say("Port #{p[:preferred]} is in use, so it gets port #{p[:host]}")
        end
        web = app_web_host_port(ports, manifest)
        url = "https://#{tailscale_https_name}:#{web}" if tailnet
        binds, set = app_share_binds_make(id, shares)
        share_mounts = app_share_mounts(shares, binds)
        app_share_sources!(shares)
        ping = app_ping_mount(id, manifest)
        say('Creating the container...')
        with_env_file(app_environment(manifest, uid, app_env_gid(manifest, gid, shares), secrets, url)) do |env_file|
          run_command([DOCKER, 'create', '--name', fresh, '--restart', 'unless-stopped',
                       '--security-opt', 'no-new-privileges', # nothing in it gains privileges, setuid files included
                       *APP_CAP_DROP.flat_map { |cap| ['--cap-drop', cap] }, '--pids-limit', APP_PIDS_LIMIT.to_s, *APP_LOG_OPTIONS,
                       '--memory', manifest[:memory], '--label', "amahi.app=#{id}", *app_dns_options, '--env-file', env_file,
                       *(manifest[:run_as] == 'app' ? ['--user', "#{uid}:#{gid}"] : []),
                       *ports.flat_map { |p| ['--publish', "#{bind}:#{p[:host]}:#{p[:container]}/#{p[:protocol]}"] },
                       *app_folder_mounts(manifest, dir, storage), *share_mounts, *ping, manifest[:image]])
        end
      rescue Failed, Refused
        run_command([DOCKER, 'rm', '--force', fresh, { allow_failure: true }])
        app_share_binds_remove(set) if set
        if running
          say('Starting the container it had again...')
          run_command([DOCKER, 'start', container, { allow_failure: true }])
        end
        raise
      end
      run_command([DOCKER, 'rm', '--force', container, { allow_failure: true }])
      run_command([DOCKER, 'rename', fresh, container])
      app_record_definition(id, manifest)
      app_share_binds_keep(id, set, shares)
      app_ping_prune(id, manifest)
      app_tailscale_serve(web) if tailnet
      ports
    end

    # --- An app's ping (the manifest's ping) ---

    # An image's ping is often given cap_net_raw as a file capability, which an app's container
    # doesn't have (APP_CAP_DROP), and the kernel then refuses to run it at all ("Operation not
    # permitted"). Docker lets a container's users ping without it (net.ipv4.ping_group_range), so
    # an app whose manifest names its ping gets that same file, copied out of the same image
    # without the capability, mounted read only in its place. One copy an image: a container made
    # again from the same image reuses it, and one an update falls back to keeps its own.
    def app_ping_mount(id, manifest)
      return [] unless manifest[:ping]

      path = app_ping_path(id, manifest[:image])
      app_ping_copy(id, manifest, path) unless File.file?(path) && !File.symlink?(path)
      ['--mount', "type=bind,source=#{path},target=#{manifest[:ping]},readonly"]
    end

    def app_ping_path(id, image)
      "#{APP_PINGS}/#{id}/ping-#{image[/@sha256:(\h{16})/, 1]}"
    end

    # docker cp out of a container made from the image and never started, then its bytes into a
    # new file, which has no extended attributes (the capability is one).
    def app_ping_copy(id, manifest, path)
      say("Copying #{manifest[:ping]} out of the image, to ping without raw sockets...")
      [APP_PINGS, File.dirname(path)].each do |dir|
        raise Failed, "#{dir} isn't a folder" if File.symlink?(dir)

        Dir.mkdir(dir, 0o755) unless File.directory?(dir)
      end
      taken = "#{path}.image"
      FileUtils.rm_f([taken, "#{path}.new"])
      scratch = "#{app_container(id)}-ping"
      run_command([DOCKER, 'rm', '--force', scratch, { allow_failure: true }])
      run_command([DOCKER, 'create', '--name', scratch, manifest[:image]])
      begin
        run_command([DOCKER, 'cp', '--follow-link', "#{scratch}:#{manifest[:ping]}", taken])
      ensure
        run_command([DOCKER, 'rm', '--force', scratch, { allow_failure: true }])
      end
      raise Failed, "#{manifest[:ping]} isn't a file in #{manifest[:image]}" unless File.file?(taken) && !File.symlink?(taken)

      File.open("#{path}.new", File::WRONLY | File::CREAT | File::EXCL, 0o755) do |copy|
        File.open(taken, 'rb') { |source| IO.copy_stream(source, copy) }
      end
      File.chmod(0o755, "#{path}.new")
      File.rename("#{path}.new", path)
    ensure
      FileUtils.rm_f(taken) if taken
    end

    # Once the container is swapped in, the copies for other images go.
    def app_ping_prune(id, manifest)
      keep = manifest[:ping] && app_ping_path(id, manifest[:image])
      Dir.glob("#{APP_PINGS}/#{id}/ping-*").each { |file| FileUtils.rm_f(file) unless file == keep }
    end

    # The host port the app's web page was given (its web_port, or the next free one), or nil.
    def app_web_host_port(ports, manifest)
      ports.find { |p| p[:preferred] == manifest[:web_port] && p[:protocol] == 'tcp' }&.dig(:host)
    end

    # --- Apps reached through Tailscale (see APP_ACCESS) ---

    # The NAS's name on its tailnet, when Tailscale can serve an app there over HTTPS: connected,
    # with MagicDNS, and HTTPS certificates on for the tailnet (a switch in Tailscale's admin
    # console). Refused with what's missing otherwise.
    def tailscale_https_name
      raise Refused, 'this app is reached through Tailscale: install Tailscale on the NAS first (Remote Access)' unless File.executable?(TAILSCALE)

      out, _err, status = Open3.capture3(ENV_MIN, [TAILSCALE, TAILSCALE], 'status', '--json', unsetenv_others: true, chdir: '/')
      data = status.success? ? JSON.parse(out) : {}
      unless data.is_a?(Hash) && data['BackendState'] == 'Running'
        raise Refused, "this app is reached through Tailscale, which isn't connected: connect it (Remote Access)"
      end

      name = data.dig('Self', 'DNSName').to_s.chomp('.')
      unless data.dig('CurrentTailnet', 'MagicDNSEnabled') == true && name.match?(TAILNET_NAME)
        raise Refused, "this app is reached through Tailscale by the NAS's name there: turn on MagicDNS in Tailscale's admin console (DNS)"
      end
      unless Array(data['CertDomains']).include?(name)
        raise Refused, "this app is reached over HTTPS through Tailscale: turn on HTTPS Certificates in Tailscale's admin console (DNS)"
      end

      name
    rescue JSON::ParserError, SystemCallError
      raise Refused, "Tailscale's status can't be read, so this app can't be served through it"
    end

    # The app's page on the tailnet, over HTTPS at the NAS's name and the app's own port, from that
    # port on the NAS itself. tailscaled keeps it across restarts; done again with each container.
    def app_tailscale_serve(port)
      say("Serving it on your tailnet over HTTPS, on port #{port}...")
      run_command(['/usr/bin/timeout', '30', TAILSCALE, 'serve', '--bg', "--https=#{port}", "http://127.0.0.1:#{port}"])
    end

    def app_tailscale_unserve(port)
      return unless File.executable?(TAILSCALE)

      run_command(['/usr/bin/timeout', '30', TAILSCALE, 'serve', "--https=#{port}", 'off', { allow_failure: true }])
    end

    # An uninstalled app reached through Tailscale comes off the tailnet, at the port it was given.
    def app_unserve_uninstalled(id, definition)
      return unless definition && definition[:access] == 'tailscale'

      given = Array((read_json(APP_PORTS) || {})[id]).grep(Hash).find { |p| p['preferred'] == definition[:web_port] && p['protocol'] == 'tcp' }
      app_tailscale_unserve(given && given['host'].is_a?(Integer) ? given['host'] : definition[:web_port])
    end

    # An Argon2id hash of +secret+ in the PHC form (APP_SECRET_HASHES), from argon2 (installed the
    # first time), the secret on its stdin and a new salt each time.
    def argon2_hash(secret)
      unless File.executable?(ARGON2)
        say('Installing argon2, to hash a password the app is given...')
        run_command(['/usr/bin/apt-get', 'update', { env: APT_ENV, stream: true }])
        run_command(['/usr/bin/apt-get', '-y', '--no-install-recommends', '-o', 'DPkg::Lock::Timeout=300', 'install', 'argon2',
                     { env: APT_ENV, stream: true }])
      end
      out, err, status = Open3.capture3(ENV_MIN, [ARGON2, ARGON2], SecureRandom.alphanumeric(22), *ARGON2_SETTINGS,
                                        stdin_data: secret, unsetenv_others: true, chdir: '/')
      hash = out.strip
      raise Failed, "argon2 didn't hash the app's password: #{last_lines(err, 1)}" unless status.success? && hash.match?(/\A\$argon2id\$\S+\z/)

      hash
    rescue SystemCallError => e
      raise Failed, "argon2 can't run: #{e.message}"
    end

    # Each share's folder and its copy folders, checked again just before the container is made
    # (apps.follow_pool makes containers too): real folders, reached through no link.
    def app_share_sources!(shares)
      shares.each do |share|
        bad = [share[:path], *(share[:pooled] ? greyhole_copies(share[:name], *share[:folder]) : [])].find { |path| !real_folder?(path) }
        raise Failed, "share #{share[:name]}'s folder #{bad} isn't a real folder (a link, or missing)" if bad
      end
    end

    # Mounts each folder +shares+ gives the app (those with a folder) in a new set of its own under
    # APP_SHARE_BIND_ROOT/<id>, for its next container: [{ [share, folder] => where it's mounted },
    # that set's folder]. The ones made are taken down again if one can't be.
    def app_share_binds_make(id, shares)
      given = shares.select { |share| share[:folder] }
      return [{}, nil] if given.empty?

      set = "#{APP_SHARE_BIND_ROOT}/#{id}/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
      binds = given.each_with_index.to_h do |share, index|
        target = "#{set}/#{index}"
        bind_share_folder(share[:path], share[:folder], target)
        [[share[:name], share[:folder]], target]
      end
      [binds, set]
    rescue Failed, Refused
      app_share_binds_remove(set) if set
      raise
    end

    # Mounts the folder +folder+ of the share whose folder is +root+ on +target+ (made, root's
    # only): the folder is opened without following a link and checked to be that path (with_dir),
    # then mounted through the handle, so nothing swapped in meanwhile is mounted instead.
    def bind_share_folder(root, folder, target)
      path = "#{root}/#{folder}"
      # Made by the helper in /run, which only root writes: a folder of its own, not a link
      FileUtils.mkdir_p(APP_SHARE_BIND_ROOT, mode: 0o700)
      own = File.lstat(APP_SHARE_BIND_ROOT)
      raise Failed, "#{APP_SHARE_BIND_ROOT} isn't the helper's own folder" unless own.directory? && own.uid == Process.euid
      FileUtils.mkdir_p(target, mode: 0o700)
      with_dir(path) do |dir|
        _out, err, status = Open3.capture3(ENV_MIN, [MOUNT, MOUNT], '--no-canonicalize', '--bind', "/proc/self/fd/#{dir.fileno}", target,
                                           dir.fileno => dir.fileno, unsetenv_others: true, chdir: '/')
        raise Failed, "mount exited #{status.exitstatus} for #{path}: #{last_lines(err, 2)}" unless status.success?
      end
    rescue Failed
      Dir.rmdir(target) if File.directory?(target) && !mounted_at?(target) && Dir.empty?(target)
      raise
    end

    # Takes down the helper's mounts in the set +set+ (APP_SHARE_BIND_ROOT/<id>/<set>) and removes
    # its folders.
    def app_share_binds_remove(set)
      return unless set.start_with?("#{APP_SHARE_BIND_ROOT}/") && File.directory?(set) && !File.symlink?(set)

      Dir.children(set).each do |name|
        target = "#{set}/#{name}"
        run_command([UMOUNT, '--lazy', target, { allow_failure: true }]) if mounted_at?(target)
        Dir.rmdir(target) unless mounted_at?(target)
      rescue SystemCallError => e
        say("#{target} stays: #{e.message}")
      end
      Dir.rmdir(set)
    rescue SystemCallError => e
      say("#{set} stays: #{e.message}")
    end

    # Records the folders the app's container now mounts (+set+, from app_share_binds_make; nil
    # for none) in APP_SHARE_BINDS for amahi-kai-app-shares.service, and takes down its other sets.
    def app_share_binds_keep(id, set, shares)
      given = shares.select { |share| share[:folder] }
      kept = (given.each_with_index.map { |share, index| { 'path' => "#{set}/#{index}", 'share' => share[:name], 'folder' => share[:folder] } } if set)
      unless (read_json(APP_SHARE_BINDS) || {})[id] == kept # an app given no folder, as before, takes no lock
        with_records_lock do
          records = read_json(APP_SHARE_BINDS) || {}
          records = kept ? records.merge(id => kept) : records.except(id)
          do_install(APP_SHARE_BINDS, "#{JSON.pretty_generate(records)}\n", nil, '0600')
        end
      end
      app_share_binds_sets(id).reject { |other| other == set }.each { |other| app_share_binds_remove(other) }
    end

    # The sets of the helper's mounts made for the app (APP_SHARE_BIND_ROOT/<id>/*).
    def app_share_binds_sets(id)
      dir = "#{APP_SHARE_BIND_ROOT}/#{id}"
      return [] unless File.directory?(dir) && !File.symlink?(dir)

      Dir.children(dir).sort.map { |name| "#{dir}/#{name}" }
    end

    # Mounts again, at the paths their containers mount, the folders apps are given in shares
    # (APP_SHARE_BINDS): /run is empty after a restart. amahi-kai-app-shares.service runs it before
    # Docker starts. Each is mounted from its share's folder as smb.conf has it now, checked as at
    # an install; one that can't be (its folder renamed or gone, say) is left out, so its app can't
    # start without it (Docker refuses a mount whose source is missing) until its shares are changed.
    # { id => { path => 'mounted' | why not } }.
    def do_share_binds
      shares = samba_shares
      (read_json(APP_SHARE_BINDS) || {}).each_with_object({}) do |(id, binds), done|
        next unless id.is_a?(String) && id.match?(APP_ID) && binds.is_a?(Array)

        done[id] = binds.grep(Hash).to_h do |bind|
          path = bind['path'].to_s
          [path, app_share_bind_again(id, path, bind['share'], bind['folder'], shares)]
        end
      end
    end

    def app_share_bind_again(id, path, name, folder, shares)
      unless normalized_path?(path) && path.match?(%r{\A#{Regexp.escape(APP_SHARE_BIND_ROOT)}/#{id}/[0-9]{14}-[0-9a-f]{6}/[0-9]+\z})
        return "#{path} isn't one of the helper's"
      end
      return 'mounted' if mounted_at?(path)

      share = app_share(string(name, 'share name', max: 64), shares)
      bind_share_folder(share[:path], app_share_folder(folder), path)
      'mounted'
    rescue Failed, Refused => e
      say("#{id}: #{e.message}")
      e.message
    end

    def image_present?(image)
      !docker_output('image', 'inspect', '--format', '{{.Id}}', image.sub(%r{:[^:@/]+@}, '@')).nil?
    end

    # Runs the block holding APP_RECORDS_LOCK, waiting for it; inside a block that holds it
    # already, the block just runs.
    def with_records_lock
      return yield if @records_locked

      File.open(APP_RECORDS_LOCK, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        @records_locked = true
        yield
      ensure
        @records_locked = false
      end
    end

    # An app given a pooled share sees its copies through one mount per pool drive, made with
    # its container. Each app container whose drive mounts aren't the ones its shares have now
    # (a drive joined, left, is missing or back; a share pooled or turned Off), or that couldn't
    # start over a mount, is made again (do_install_app, from the definition it was made from,
    # its shares checked as apps.install checks them), with the drives mounted now. One the owner
    # stopped stays stopped; one a job is changing is left to it. One app's failure is its own:
    # { 'apps' => { id => 'remade' | 'remade, stopped' | its reason }, 'shares' => { id => the
    # shares it has now, [{ 'name', 'folder' (for a folder of the share), 'write' }] } }.
    def do_follow_pool_apps
      out = docker_output('ps', '--all', '--filter', 'label=amahi.app', '--format', '{{.Label "amahi.app"}}')
      return { 'apps' => {}, 'shares' => {} } unless out

      shares = samba_shares
      given = {}
      done = out.lines.map(&:strip).grep(APP_ID).uniq.filter_map do |id|
        next if app_job_running?(id) # the job makes its container with the pool as it is

        info = JSON.parse(docker_output('inspect', app_container(id)) || '[]').first or next
        mounts = Array(info['Mounts'])
        chosen = app_container_shares(info, shares)
        have = mounts.map { |mount| mount['Destination'].to_s }.select { |dest| dest.start_with?("#{drives_root}/") }.sort
        want = chosen.select { |share| share[:pooled] }.flat_map { |share| greyhole_copies(share[:name], *share[:folder]) }.uniq.sort
        failed = info.dig('State', 'Error').to_s.include?('mount')
        next if have == want && !failed

        say("#{id}: making its container again with the pool drives mounted now")
        begin
          checked, stopped = app_remake(id, info, chosen, failed: failed)
          given[id] = checked.map { |share| { 'name' => share[:name], 'folder' => share[:folder], 'write' => share[:write] }.compact }
          [id, stopped ? 'remade, stopped' : 'remade']
        rescue Failed, Refused => e
          [id, e.message]
        end
      rescue JSON::ParserError
        nil
      end
      do_app_firewall if done.any?
      { 'apps' => done.to_h, 'shares' => given }
    end

    # An app's shares as its container has them (+info+, docker inspect's), from +shares+
    # (samba_shares): /shares/<name> for a share, /shares/<name>/<folder> for a folder of one.
    def app_container_shares(info, shares)
      Array(info['Mounts']).filter_map do |mount|
        inside = mount['Destination'].to_s.delete_prefix("#{APP_SHARE_TARGET}/")
        next if inside == mount['Destination']

        name, folder = inside.split('/', 2)
        share = shares[name.downcase] or next
        share = share.merge(folder: folder) if folder
        share.merge(write: mount['RW'] == true && !share[:pooled])
      end
    end

    # Makes an app's container again from its definition, with the shares it has (+chosen+,
    # app_container_shares; written to only where its definition writes shares, and checked as
    # apps.install checks them), keeping its version and data, and stopped again if it was
    # stopped (not if it +failed+ to start). Returns [the shares given, whether it's stopped].
    def app_remake(id, info, chosen, failed: false)
      stopped = !info.dig('State', 'Running') && !failed
      manifest = app_definition(id) || app_manifest(id)
      wanted = chosen.map do |share|
        { 'name' => share[:name], 'folder' => share[:folder], 'write' => share[:write] && manifest[:writes_shares] == true }.compact
      end
      checked = app_share_choices(wanted, id, manifest)
      do_install_app(id, manifest, checked, true)
      run_command([DOCKER, 'stop', '--time', '30', app_container(id)]) if stopped
      [checked, stopped]
    end

    # apps.follow_dns: each app container made with other DNS than app_dns_options gives now is
    # made again, keeping its shares, version and data.
    def do_follow_dns_apps
      out = docker_output('ps', '--all', '--filter', 'label=amahi.app', '--format', '{{.Label "amahi.app"}}')
      return { 'apps' => {} } unless out

      want = app_dns_options
      shares = samba_shares
      done = out.lines.map(&:strip).grep(APP_ID).uniq.filter_map do |id|
        next if app_job_running?(id) # the job makes its container with the DNS as it is

        info = JSON.parse(docker_output('inspect', app_container(id)) || '[]').first or next
        next if app_dns_of(info) == want

        say("#{id}: making its container again with #{want.empty? ? "Docker's own DNS" : "the NAS's DNS"}")
        begin
          _checked, stopped = app_remake(id, info, app_container_shares(info, shares))
          [id, stopped ? 'remade, stopped' : 'remade']
        rescue Failed, Refused => e
          [id, e.message]
        end
      rescue JSON::ParserError
        nil
      end
      do_app_firewall if done.any?
      { 'apps' => done.to_h }
    end

    # The NAS's DNS for an app's container while Unbound answers on Docker's bridge
    # (DnsService's config writes the bridge's address while Docker runs): the bridge's address,
    # and the local domain to look short names up in, so an app reaches a device by the name it
    # has on Network → Devices. Nothing otherwise: Docker's own, the NAS's upstream servers.
    def app_dns_options
      return [] unless File.exist?(UNBOUND_CONF)
      bridge = docker_bridge_address or return []
      config = File.read(UNBOUND_CONF)
      return [] unless unbound_listening(config).include?(bridge)
      domain = config[/^\s*local-zone: "(#{UNBOUND_NAME})" static$/o, 1]
      ['--dns', bridge, *(['--dns-search', domain.chomp('.')] if domain)]
    end

    # The IPv4 address of Docker's bridge (its containers' gateway), or nil while Docker isn't up.
    def docker_bridge_address
      Socket.getifaddrs.find { |ifaddr| ifaddr.name == DOCKER_BRIDGE && ifaddr.addr&.ipv4? }&.addr&.ip_address
    end

    # The DNS options a container was made with (+info+, docker inspect's), as app_dns_options
    # gives them.
    def app_dns_of(info)
      [*Array(info.dig('HostConfig', 'Dns')).flat_map { |server| ['--dns', server] },
       *Array(info.dig('HostConfig', 'DnsSearch')).flat_map { |domain| ['--dns-search', domain] }]
    end

    # apps.follow_dns in the background, once Unbound has started or stopped answering on Docker's
    # bridge: remaking every app's container takes minutes, longer than a page waits. One already
    # running (the same unit) does it with the config as it then is.
    def follow_dns_apps_later
      return unless File.executable?(DOCKER) && File.executable?(SYSTEMD_RUN)
      run_command([SYSTEMD_RUN, "--unit=#{APPS_FOLLOW_DNS_UNIT}", '--no-block', '--collect', '--quiet', HELPER_PATH, 'apps.follow_dns',
                   { allow_failure: true }])
    end

    # The image an app's container runs (name:tag@sha256:...), or nil without a container.
    def app_image(id)
      image = docker_output('inspect', '--format', '{{.Config.Image}}', app_container(id)).to_s.strip
      image.match?(APP_IMAGE) ? image : nil
    end

    def image_tag(image)
      image.sub(/@.*/, '').split(':').last
    end

    # --- Updates ---

    def do_update_app(id, manifest, shares)
      from = app_image(id) or raise Failed, "#{id} isn't installed"
      raise Failed, "#{id} runs #{image_tag(from)}, the catalog's version, already" if from == manifest[:image]
      if version_below?(image_tag(manifest[:image]), image_tag(from))
        raise Failed, "the catalog's #{id} (#{image_tag(manifest[:image])}) is older than the one it runs (#{image_tag(from)}), so there's nothing to update to"
      end

      # What it runs now, for the copy and a way back: the definition its container was made from
      # (one made before these were kept: the catalog's, on the image it runs)
      before = app_definition(id) || manifest.merge(image: from)
      app_backup_room!(id, before)
      unless image_present?(manifest[:image])
        say("Pulling #{manifest[:image].sub(/@.*/, '')}...")
        run_command([DOCKER, 'pull', manifest[:image], { stream: true }])
      end
      say("Stopping it (#{image_tag(from)})...")
      run_command([DOCKER, 'stop', '--time', '30', app_container(id)])
      say('Copying its data first, so the update can be undone...')
      begin
        app_backup(id, before, from, manifest[:image])
      rescue Failed, SystemCallError => e
        say("The copy didn't work, so it starts again on #{image_tag(from)}")
        run_command([DOCKER, 'start', app_container(id), { allow_failure: true }])
        raise Failed, "#{id}'s data couldn't be copied before the update (#{e.message}); it runs #{image_tag(from)} as before"
      end
      say("Starting #{image_tag(manifest[:image])}...")
      reply = nil
      problem = begin
        reply = do_install_app(id, manifest, shares)
        say('Waiting for it to come up healthy (up to 5 minutes)...')
        app_health_problem(id, manifest)
      rescue Failed => e
        e.message
      end
      if problem
        say("It didn't come up healthy: #{problem}")
        say("Going back to #{image_tag(from)}, with its data from before the update...")
        app_restore(id, before, from, shares)
        app_forget_backup(id)
        return { 'app' => id, 'updated' => false, 'image' => from, 'problem' => problem }
      end
      run_command([DOCKER, 'image', 'rm', from, { allow_failure: true }])
      { 'app' => id, 'updated' => true, 'image' => manifest[:image], 'from' => from, 'ports' => reply['ports'] }
    end

    def do_undo_app_update(id, manifest, shares)
      backup = app_backup_info(id) or raise Failed, "#{id} has no update to undo"
      raise Failed, "the copy from before #{id}'s update is over #{APP_BACKUP_DAYS} days old" if app_backup_expired?(backup)
      from = backup['from'].to_s
      raise Failed, "the copy from before #{id}'s update doesn't say which version it was" unless from.match?(APP_IMAGE)

      # The old version's image first (an update removes it): nothing changes if it can't be had
      unless image_present?(from)
        say("Downloading #{image_tag(from)} again...")
        run_command([DOCKER, 'pull', from, { stream: true }])
      end
      say("Stopping it (#{image_tag(app_image(id) || manifest[:image])})...")
      run_command([DOCKER, 'stop', '--time', '30', app_container(id), { allow_failure: true }])
      say("Going back to #{image_tag(from)}, with its data from before the update...")
      reply = app_restore(id, manifest, from, shares)
      app_forget_backup(id)
      { 'app' => id, 'image' => from, 'ports' => reply['ports'] }
    end

    def do_prune_app_backups
      removed = Dir.glob("#{APP_BACKUPS}/*.json").filter_map do |path|
        id = File.basename(path, '.json')
        next unless id.match?(APP_ID)
        backup = app_backup_info(id)
        next unless backup.nil? || app_backup_expired?(backup)
        app_forget_backup(id)
        id
      end
      { 'removed' => removed }
    end

    # Fails unless the app's folders fit on the disk with APP_BACKUP_MARGIN left; the copy it
    # replaces counts as free.
    def app_backup_room!(id, manifest)
      folders = app_backup_folders(id, manifest)
      need = folders.empty? ? 0 : disk_usage(folders)
      old = "#{APP_BACKUPS}/#{id}"
      have = free_space(APPS_ROOT) + (File.directory?(old) ? disk_usage([old]) : 0)
      return if need + APP_BACKUP_MARGIN <= have

      raise Failed, "there isn't room to copy #{id}'s data before updating (#{gigabytes(need)} GB, and " \
                    "#{gigabytes(have)} GB is free); free some space or grow the disk"
    end

    # The folders an update copies first: the system disk's that the manifest backs up. A dataset
    # is snapshotted instead (app_update_snapshot).
    def app_backup_folders(id, manifest)
      manifest[:folders].select { |f| f[:backup] && f[:kind] == :state }.map { |f| "#{APPS_ROOT}/#{id}/#{f[:name]}" }
                        .select { |path| File.directory?(path) && !File.symlink?(path) }
    end

    def disk_usage(paths)
      capture(['/usr/bin/du', '-s', '-x', '-B1', '--', *paths]).lines.sum(&:to_i)
    end

    # Replaces the app's copy: the description goes first, so a copy cut short is never offered.
    # +manifest+: the definition the app runs (its folders are the ones copied, and it's what an
    # undo makes the container from again); +to+: the version it's updated to.
    def app_backup(id, manifest, from, to = manifest[:image])
      unless File.directory?(APP_BACKUPS)
        Dir.mkdir(APP_BACKUPS, 0o750)
        File.chown(0, group_id(APP_USER), APP_BACKUPS)
      end
      app_forget_backup(id)
      data = "#{APP_BACKUPS}/#{id}"
      Dir.mkdir(data, 0o700)
      folders = app_backup_folders(id, manifest)
      folders.each { |folder| run_command(['/usr/bin/cp', '-a', '--', folder, "#{data}/#{File.basename(folder)}"]) }
      snapshot = app_update_snapshot(id, manifest)
      info = { 'taken_at' => Time.now.utc.iso8601, 'from' => from, 'to' => to,
               'folders' => folders.map { |folder| File.basename(folder) }, 'snapshot' => snapshot,
               'definition' => manifest[:source].is_a?(Hash) ? manifest[:source].merge('image' => from) : nil }.compact
      do_install("#{APP_BACKUPS}/#{id}.json", "#{JSON.pretty_generate(info)}\n", nil, '0640', APP_USER)
    end

    # A snapshot of the app's dataset, taken before an update (the app stopped), or nil without
    # one. Rolling back to it (app_restore) also removes the pool's own snapshots of the dataset
    # taken after it.
    def app_update_snapshot(id, manifest)
      return nil unless manifest[:storage] && (pool = app_storage_pool(id)) && pool_names.include?(pool)

      dataset = "#{pool}/#{APP_DATASETS}/#{id}"
      return nil unless zfs_dataset?(dataset)

      snapshot = "#{dataset}@amahi-update-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}"
      run_command([ZFS, 'snapshot', snapshot])
      snapshot
    end

    # Puts the copied folders back and recreates the container on +image+.
    def app_restore(id, manifest, image, shares)
      backup = app_backup_info(id) or raise Failed, "there's no copy of #{id}'s data to go back to"
      run_command([DOCKER, 'rm', '--force', app_container(id), { allow_failure: true }])
      Array(backup['folders']).each do |name|
        raise Failed, "the copy lists a folder #{name.inspect}" unless name.is_a?(String) && name.match?(APP_FOLDER)
        target = "#{APPS_ROOT}/#{id}/#{name}"
        FileUtils.remove_entry_secure(target) if File.exist?(target) || File.symlink?(target)
        run_command(['/usr/bin/cp', '-a', '--', "#{APP_BACKUPS}/#{id}/#{name}", target])
      end
      if (snapshot = app_backup_snapshot(id, backup))
        say("Rolling its storage back to #{snapshot.split('@').last}...")
        run_command([ZFS, 'rollback', '-r', snapshot])
      end
      do_install_app(id, manifest.merge(image: image), shares)
    end

    # The update snapshot a backup names, checked, if it's still there.
    def app_backup_snapshot(id, backup)
      snapshot = backup['snapshot']
      return nil unless snapshot.is_a?(String)
      raise Failed, "the copy names a snapshot #{snapshot.inspect}" unless snapshot.match?(APP_UPDATE_SNAPSHOT) && snapshot.include?("/#{APP_DATASETS}/#{id}@")

      zfs_dataset?(snapshot) ? snapshot : nil
    end

    def app_backup_info(id)
      info = read_json("#{APP_BACKUPS}/#{id}.json")
      info.is_a?(Hash) && File.directory?("#{APP_BACKUPS}/#{id}") ? info : nil
    end

    def app_backup_expired?(info)
      Time.iso8601(info['taken_at'].to_s) < Time.now - (APP_BACKUP_DAYS * 86_400)
    rescue ArgumentError
      true
    end

    def app_forget_backup(id)
      backup = read_json("#{APP_BACKUPS}/#{id}.json")
      if backup.is_a?(Hash) && (snapshot = app_backup_snapshot(id, backup))
        run_command([ZFS, 'destroy', snapshot, { allow_failure: true }])
      end
      FileUtils.rm_f("#{APP_BACKUPS}/#{id}.json")
      data = "#{APP_BACKUPS}/#{id}"
      FileUtils.remove_entry_secure(data) if File.exist?(data) || File.symlink?(data)
    end

    # nil once the app is healthy, else why not: Docker's own health check where the image has
    # one; otherwise its web page answers and it's still running, not restarted, 10 s later.
    def app_health_problem(id, manifest, timeout: APP_HEALTH_TIMEOUT)
      deadline = monotonic_now + timeout
      loop do
        state = app_state(id)
        return 'its container is gone' unless state
        return "it stopped (exit code #{state['ExitCode']})" if %w[exited dead].include?(state['Status'])

        health = state.dig('Health', 'Status')
        return "Docker's health check for it failed" if health == 'unhealthy'
        return nil if health == 'healthy'

        if health.nil? && state['Status'] == 'running' && app_answers?(id, manifest)
          restarts = app_restart_count(id)
          pause(10)
          again = app_state(id)
          return nil if again && again['Status'] == 'running' && app_restart_count(id) == restarts
        end
        return "it didn't come up within #{timeout / 60} minutes" if monotonic_now >= deadline

        pause(5)
      end
    end

    def app_state(id)
      out = docker_output('inspect', '--format', '{{json .State}}', app_container(id))
      out ? JSON.parse(out) : nil
    rescue JSON::ParserError
      nil
    end

    def app_restart_count(id)
      docker_output('inspect', '--format', '{{.RestartCount}}', app_container(id)).to_i
    end

    # The app's web page answers on its port (the one it was given, P4.2), with any HTTP reply;
    # an HTTPS page (web_tls), which doesn't answer plain HTTP, with a TLS handshake (its
    # certificate is its own, so it isn't checked).
    def app_answers?(id, manifest)
      return true unless manifest[:web_port]
      given = Array((read_json(APP_PORTS) || {})[id]).grep(Hash).find { |p| p['preferred'] == manifest[:web_port] }
      port = given ? given['host'] : manifest[:web_port]
      Socket.tcp('127.0.0.1', port, connect_timeout: 3) do |socket|
        next tls_answers?(socket) if manifest[:web_tls]

        socket.write("GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        socket.wait_readable(5) && socket.readpartial(16).start_with?('HTTP/')
      end
    rescue SystemCallError, IOError
      false
    end

    # A TLS handshake completes within 5 seconds.
    def tls_answers?(socket)
      require 'openssl'
      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      tls = OpenSSL::SSL::SSLSocket.new(socket, context)
      tls.hostname = 'localhost'
      deadline = monotonic_now + 5
      loop do
        left = [deadline - monotonic_now, 0].max
        case tls.connect_nonblock(exception: false)
        when :wait_readable then return false unless socket.wait_readable(left)
        when :wait_writable then return false unless socket.wait_writable(left)
        else return true
        end
      end
    rescue OpenSSL::SSL::SSLError
      false
    end

    # Whether version tag +a+ is below +b+, by their numbers in order ("4.0.16-ls253" <
    # "4.0.17-ls254"); false when either has none, or they're the same numbers.
    def version_below?(a, b)
      left = a.to_s.scan(/\d+/).map(&:to_i)
      right = b.to_s.scan(/\d+/).map(&:to_i)
      return false if left.empty? || right.empty?

      (left <=> right) == -1
    end

    # --mount (not --volume, which would make a missing folder) for each share, at /shares/<name>,
    # read only unless chosen otherwise; a folder given of a share at /shares/<name>/<folder>, from
    # the helper's own mount of it (+binds+, app_share_binds_make); a pooled share's copy folders
    # (or that folder in each), read only, at their own paths. An app that writes into a share joins
    # the users group, which shares belong to.
    def app_share_mounts(shares, binds = {})
      mounts = shares.flat_map do |share|
        copies = share[:pooled] ? greyhole_copies(share[:name], *share[:folder]).map { |copy| [copy, copy, true] } : []
        if share[:folder]
          source = binds[[share[:name], share[:folder]]] or raise Failed, "#{share[:name]}/#{share[:folder]} isn't mounted for the app"
          [[source, "#{APP_SHARE_TARGET}/#{share[:name]}/#{share[:folder]}", !share[:write]], *copies]
        else
          [[share[:path], "#{APP_SHARE_TARGET}/#{share[:name]}", !share[:write]], *copies]
        end
      end
      args = mounts.uniq { |_source, target, _ro| target }.flat_map do |source, target, readonly|
        ['--mount', "type=bind,source=#{source},target=#{target}#{',readonly' if readonly}"]
      end
      return args unless shares.any? { |share| share[:write] }

      users = group_id(USERS_GROUP) or raise Failed, "there's no #{USERS_GROUP} group"
      ['--group-add', users.to_s, *args]
    end

    # A share an app writes into gets a default ACL on each of its folders, so what the app makes
    # there is group-writable (the users group, like files made over SMB) whatever its umask:
    # with a default ACL, the umask doesn't apply. find doesn't follow links.
    def app_share_writable(path)
      unless File.executable?(SETFACL)
        say('Installing acl...')
        run_command(['/usr/bin/apt-get', '-y', '--no-install-recommends', '-o', 'DPkg::Lock::Timeout=300',
                     'install', 'acl', { env: APT_ENV, stream: true }])
      end
      share_posix_acls(path)
      say("Letting what it writes in #{path} stay editable over SMB...")
      # setfacl -P takes a physical walk: a folder swapped for a link since find listed it is
      # skipped, never followed.
      run_command(['/usr/bin/find', path, '-xdev', '-type', 'd', '-exec', SETFACL, '-P', '-d', '-m', 'u::rwx,g::rwx,o::rx', '{}', '+'])
    end

    # ZFS on Linux leaves POSIX ACLs off (acltype=off) unless asked, and setfacl then fails with
    # "Operation not supported". Pools made now have them on (pools.create); on an older one of
    # Amahi-kai's, the share's dataset gets them here, with xattr=sa, which keeps them in each
    # file's inode. Nothing there changes but what setfacl then sets.
    def share_posix_acls(path)
      return unless capture([FINDMNT, '-n', '-o', 'FSTYPE', '-T', path]).strip == 'zfs'

      dataset, acltype = capture([ZFS, 'get', '-H', '-o', 'name,value', 'acltype', path]).chomp.split("\t")
      return unless %w[off noacl].include?(acltype) && managed?(dataset.split('/').first)

      say("Turning on POSIX ACLs for #{dataset}...")
      run_command([ZFS, 'set', 'acltype=posixacl', 'xattr=sa', dataset])
    end

    # [{ preferred:, host:, container:, protocol: }]: the host port for each of the manifest's
    # ports. Each keeps the port it had at the last install, or its catalog port, while that's
    # free; otherwise the next free one. Ports with the same number (Transmission's peer port,
    # TCP and UDP) stay together. Another app's ports count as taken even while it's stopped
    # or uninstalled with its data kept.
    def app_assign_ports(id, wanted, address = '0.0.0.0')
      records = read_json(APP_PORTS) || {}
      before = Array(records[id]).select { |p| p.is_a?(Hash) }
      taken = records.reject { |other, _| other == id }.values.flatten.grep(Hash).map { |p| [p['host'], p['protocol']] }
      wanted.group_by { |p| p[:host] }.flat_map do |preferred, group|
        protocols = group.map { |p| p[:protocol] }
        free = ->(port) { port_free?(port, protocols, taken, address) }
        last = before.find { |p| p['preferred'] == preferred && p['protocol'] == protocols.first }&.dig('host')
        host = [last, preferred].compact.uniq.find(&free) ||
               ((preferred + 1)..65_535).find(&free) || (1024...preferred).find(&free) or
          raise Failed, "no free port for #{preferred}"
        taken += protocols.map { |protocol| [host, protocol] }
        group.map { |p| { preferred: preferred, host: host, container: p[:container], protocol: p[:protocol] } }
      end
    end

    def port_free?(port, protocols, taken, address = '0.0.0.0')
      return false unless port.is_a?(Integer) && port.between?(1024, 65_535) && !APP_RESERVED_PORTS.include?(port)
      protocols.all? { |protocol| !taken.include?([port, protocol]) && port_bindable?(port, protocol, address) }
    end

    # Nothing on the NAS listens on +port+ at +address+, the one the app's ports are published on
    # (docker-proxy holds every running app's ports). An app reached through Tailscale is published
    # on 127.0.0.1 and checked there: tailscaled holds its port on the Tailscale addresses while
    # it's served, so 0.0.0.0 would read as taken and move it to another port at each update.
    # SO_REUSEADDR so that connections still closing (TIME_WAIT) don't count; a listener does.
    def port_bindable?(port, protocol, address = '0.0.0.0')
      socket = Socket.new(:INET, protocol == 'udp' ? :DGRAM : :STREAM)
      socket.setsockopt(:SOCKET, :REUSEADDR, true) unless protocol == 'udp'
      socket.bind(Addrinfo.new(Socket.sockaddr_in(port, address)))
      true
    rescue SystemCallError
      false
    ensure
      socket&.close
    end

    def app_record_ports(id, ports)
      with_records_lock do
        records = read_json(APP_PORTS) || {}
        records = records.merge(id => ports.map { |p| p.transform_keys(&:to_s) }).sort.to_h
        do_install(APP_PORTS, "#{JSON.pretty_generate(records)}\n", nil, '0640', APP_USER)
      end
    end

    def app_forget_ports(id)
      with_records_lock do
        records = read_json(APP_PORTS)
        next unless records&.key?(id)

        do_install(APP_PORTS, "#{JSON.pretty_generate(records.except(id))}\n", nil, '0640', APP_USER)
      end
    end

    # Rebuilds APP_CHAIN, jumped to from DOCKER-USER: established connections, traffic not going
    # into a container, and containers' own traffic pass; new connections into a container pass
    # only from Tailscale or the NAS's private subnets.
    # Its rules go in whole, in one iptables-restore (--noflush: the chain named is emptied and
    # filled in one step, the rest left as it is). Run before Docker starts too
    # (amahi-kai-app-firewall-early.service), so the apps' ports are never open in between.
    def do_app_firewall
      subnets = lan_subnets
      run_command([IPTABLES, '-w', '-N', 'DOCKER-USER', { allow_failure: true }])
      run_command([IPTABLES, '-w', '-N', APP_CHAIN, { allow_failure: true }])
      rules = app_chain_rules(subnets).map { |rule| "-A #{APP_CHAIN} #{rule.join(' ')}" }
      run_command([IPTABLES_RESTORE, '-w', '--noflush', { stdin: "*filter\n:#{APP_CHAIN} - [0:0]\n#{rules.join("\n")}\nCOMMIT\n" }])
      unless run_command([IPTABLES, '-w', '-C', 'DOCKER-USER', '-j', APP_CHAIN, { allow_failure: true }]).nil?
        run_command([IPTABLES, '-w', '-I', 'DOCKER-USER', '1', '-j', APP_CHAIN])
      end
      { 'lan' => subnets }
    end

    def app_chain_rules(subnets)
      [%w[-m conntrack --ctstate RELATED,ESTABLISHED -j RETURN],
       ['!', '-o', DOCKER_BRIDGE, '-j', 'RETURN'],
       ['-i', DOCKER_BRIDGE, '-j', 'RETURN'],
       %w[-i tailscale0 -j RETURN],
       *subnets.map { |net| ['-s', net, '-j', 'RETURN'] },
       %w[-j DROP]]
    end

    # APP_CHAIN is in place: DOCKER-USER jumps to it, and it ends by dropping.
    def app_firewall_active?
      return false unless File.executable?(IPTABLES)
      rules = capture([IPTABLES, '-w', '-S', APP_CHAIN])
      rules.lines.last.to_s.strip == "-A #{APP_CHAIN} -j DROP" &&
        run_command([IPTABLES, '-w', '-C', 'DOCKER-USER', '-j', APP_CHAIN, { allow_failure: true }]).nil?
    rescue Failed
      false
    end

    # [uid, gid] of the app's system user (app-<id>), created on its first install.
    def app_account(id)
      name = "app-#{id}"
      unless passwd(name)
        run_command(['/usr/sbin/useradd', '--system', '--user-group', '--no-create-home', '--home-dir', '/nonexistent',
                     '--shell', NOLOGIN, name])
      end
      account = passwd(name) or raise Failed, "couldn't create the user #{name}"
      raise Failed, "#{name} isn't a system account" unless account.uid.positive? && account.uid < UID_MIN
      [account.uid, account.gid]
    end

    # A folder of the app's, owned by its user (0750). A folder from an earlier install is kept,
    # contents and all; anything but a real folder there is refused.
    def app_folder(path, uid, gid)
      Dir.mkdir(path, 0o750) unless File.exist?(path) || File.symlink?(path)
      raise Failed, "#{path} isn't a folder" unless File.lstat(path).directory?
      File.lchown(uid, gid, path)
      File.chmod(0o750, path)
    end

    # The container's mounts for the app's folders: the system disk's (state) and its dataset's,
    # bound with --mount (never --volume, which would make a missing folder: on a pool that isn't
    # mounted, that would be the system disk's, and whose colons split a path that has one). A
    # dataset folder is left out when the app has no pool (an optional one not chosen).
    def app_folder_mounts(manifest, dir, storage)
      manifest[:folders].flat_map do |folder|
        if folder[:kind] == :state
          ['--mount', "type=bind,source=#{dir}/#{folder[:name]},target=#{folder[:path]}"]
        elsif storage
          ['--mount', "type=bind,source=#{storage}/#{folder[:name]},target=#{folder[:path]}"]
        else
          []
        end
      end
    end

    # The pool an app's dataset folders go on, for apps.install: the one they're on already
    # (APP_STORAGE), else the one chosen; nil for an app without them, or with optional ones
    # and no pool chosen. Moving them to another pool is uninstalling with the data, then
    # installing on the other pool.
    def app_pool_choice(id, manifest, value)
      return nil unless manifest[:storage]
      chosen = value.nil? || value == '' ? nil : string(value, 'pool', max: 32)
      if (have = app_storage_pool(id))
        raise Refused, "#{id}'s data is on the pool #{have}: uninstall it with its data to move it to #{chosen}" if chosen && chosen != have
        return have
      end
      return managed_pool(chosen) if chosen
      raise Refused, "#{id} keeps its data on a ZFS pool: choose one (make one on Disks → ZFS Pools first)" if manifest[:storage] == :required

      nil
    end

    # The mounted folder of the app's dataset, <pool>/apps/<id>, made the first time (owned by the
    # app's user, like its folder on the system disk, with a folder for each dataset folder), and
    # recorded in APP_STORAGE; nil without one. +pool+ is apps.install's choice; otherwise (an
    # update, a reinstall over the pool's change) it's the recorded one.
    def app_storage(id, manifest, pool, uid, gid)
      return nil unless manifest[:storage]
      pool ||= app_storage_pool(id)
      # An app installed before its manifest moved folders to a dataset (an update, or the pool
      # changing, would start it on empty folders): it's installed again on a pool instead.
      if pool.nil? && manifest[:storage] == :required
        raise Failed, "#{id} keeps its data on a ZFS pool now, and has none: uninstall it and install it again on a pool " \
                      "(what it kept in #{APPS_ROOT}/#{id} stays there)"
      end
      return nil unless pool

      raise Failed, "#{id}'s data is on the pool #{pool}, which isn't online: bring it online on Disks → ZFS Pools first" unless pool_names.include?(pool)
      dataset = "#{pool}/#{APP_DATASETS}/#{id}"
      unless zfs_dataset?(dataset)
        say("Making its storage on the pool #{pool}...")
        run_command([ZFS, 'create', '-p', dataset])
      end
      run_command([ZFS, 'mount', dataset]) unless capture([ZFS, 'get', '-H', '-o', 'value', 'mounted', dataset]).strip == 'yes'
      root = capture([ZFS, 'get', '-H', '-o', 'value', 'mountpoint', dataset]).strip
      raise Failed, "#{dataset} isn't mounted at #{pool_root}/#{pool}/#{APP_DATASETS}/#{id}" unless dataset_mounted?(dataset, root) && root == "#{pool_root}/#{pool}/#{APP_DATASETS}/#{id}"

      app_folder(root, uid, gid)
      manifest[:folders].each { |folder| app_folder("#{root}/#{folder[:name]}", uid, gid) if folder[:kind] == :dataset }
      app_record_storage(id, pool)
      root
    end

    # Whether ZFS has +dataset+ mounted at +root+, a real folder (no symlink in the way).
    def dataset_mounted?(dataset, root, mounts_file = '/proc/self/mounts')
      return false unless File.realpath(root) == root && File.lstat(root).directory?

      File.readlines(mounts_file).map(&:split).any? { |fields| fields[0] == dataset && fields[1] == root && fields[2] == 'zfs' }
    rescue SystemCallError
      false
    end

    def zfs_dataset?(name)
      _out, _err, status = Open3.capture3(ENV_MIN, ZFS, 'list', '-H', '-o', 'name', name, unsetenv_others: true, chdir: '/')
      status.success?
    rescue SystemCallError
      false
    end

    # { id => pool } from APP_STORAGE, the pool names checked.
    def app_storage_records
      records = read_json(APP_STORAGE)
      records.is_a?(Hash) ? records.select { |id, pool| id.is_a?(String) && id.match?(APP_ID) && pool.is_a?(String) && pool.match?(POOL_NAME) } : {}
    end

    def app_storage_pool(id)
      app_storage_records[id]
    end

    def app_record_storage(id, pool)
      with_records_lock do
        records = app_storage_records
        next if records[id] == pool

        records[id] = pool
        do_install(APP_STORAGE, "#{JSON.pretty_generate(records)}\n", nil, '0640', APP_USER)
      end
    end

    def app_forget_storage(id)
      with_records_lock do
        records = app_storage_records
        next unless records.delete(id)

        do_install(APP_STORAGE, "#{JSON.pretty_generate(records)}\n", nil, '0640', APP_USER)
      end
    end

    # { 'ADMIN_TOKEN' => '...' }: the app's secrets, generated on its first install and kept in
    # APP_SECRETS/<id>.json (root:amahi 0640) so the admin pages can show them.
    def app_secrets(id, names)
      unless File.directory?(APP_SECRETS)
        Dir.mkdir(APP_SECRETS, 0o750)
        File.chown(0, group_id(APP_USER), APP_SECRETS)
      end
      path = "#{APP_SECRETS}/#{id}.json"
      kept = read_json(path) || {}
      secrets = names.to_h { |name| [name, kept[name].is_a?(String) ? kept[name] : SecureRandom.alphanumeric(32)] }
      do_install(path, "#{JSON.pretty_generate(kept.merge(secrets))}\n", nil, '0640', APP_USER) unless secrets.empty?
      secrets
    end

    # The container's environment: the manifest's, its placeholders filled in (+tailscale_url+ is
    # the app's address on the tailnet, for one reached through Tailscale), and its secrets, those
    # it takes hashed (APP_SECRET_HASHES) as hashes.
    def app_environment(manifest, uid, gid, secrets, tailscale_url = nil)
      values = { 'uid' => uid.to_s, 'gid' => gid.to_s, 'timezone' => host_timezone }
      hashed = Array(manifest[:hashed_secrets])
      manifest[:environment].transform_values do |value|
        value.gsub(APP_PLACEHOLDERS) { values.fetch(Regexp.last_match(1)) }
             .gsub(APP_SECRET_PLACEHOLDER) { secrets.fetch(Regexp.last_match(1)) }
             .gsub(APP_TAILSCALE_URL) { tailscale_url || raise(Failed, "#{APP_TAILSCALE_URL} without an address on the tailnet") }
      end.merge(secrets.to_h { |name, value| [name, hashed.include?(name) ? argon2_hash(value) : value] })
    end

    # The group {{gid}} stands for. An image whose init drops to the app's user (run_as: image,
    # PUID and PGID) takes that user's groups from the image's own /etc/group, so Docker's
    # --group-add users is lost there (linuxserver.io's images call gid 1000 users): given a share
    # to write into, it runs with the users group as its own group (PGID) instead, and can write
    # where the users group can. A run_as: app container keeps --group-add, and the app's group.
    def app_env_gid(manifest, gid, shares)
      return gid unless manifest[:run_as] == 'image' && shares.any? { |share| share[:write] }

      group_id(USERS_GROUP) or raise Failed, "there's no #{USERS_GROUP} group"
    end

    def host_timezone
      zone = File.read('/etc/timezone').strip
      zone.match?(%r{\A[A-Za-z0-9_+\-/]{1,64}\z}) ? zone : 'Etc/UTC'
    rescue SystemCallError
      'Etc/UTC'
    end

    # Writes the container's environment to a file only root can read, for docker create's
    # --env-file, so secrets are never on a command line; removed afterwards.
    def with_env_file(environment)
      path = File.join(RUN_DIR, "amahi-app-env-#{SecureRandom.hex(8)}")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
        environment.each { |key, value| f.puts("#{key}=#{value}") }
      end
      yield path
    ensure
      File.unlink(path) if path && File.exist?(path)
    end

    # The container goes (checked: Docker may not have removed it), then its image: the one the
    # container ran, else its definition's. Data kept keeps the definition too, so a reinstall
    # runs the version the data is from.
    def do_uninstall_app(id, delete_data)
      pool = app_storage_pool(id)
      if delete_data && pool && !pool_names.include?(pool)
        raise Failed, "#{id}'s data is on the pool #{pool}, which isn't online: bring it online to delete it"
      end
      definition = app_definition(id)
      image = app_image(id) || definition&.dig(:image)
      container = app_container(id)
      run_command([DOCKER, 'rm', '--force', container, { allow_failure: true }])
      raise Failed, "Docker didn't remove #{container}; nothing else of #{id} was touched" if docker_output('inspect', '--format', '{{.Id}}', container)
      app_share_binds_keep(id, nil, [])
      app_unserve_uninstalled(id, definition)
      run_command([DOCKER, 'image', 'rm', image, { allow_failure: true }]) if image
      FileUtils.rm_rf("#{APP_PINGS}/#{id}") # made again from the image at the next install
      return { 'app' => id, 'data_kept' => true } unless delete_data

      dir = "#{APPS_ROOT}/#{id}"
      raise Failed, "#{dir} isn't a folder" if File.symlink?(dir)
      FileUtils.remove_entry_secure(dir) if File.directory?(dir)
      FileUtils.rm_f("#{APP_SECRETS}/#{id}.json")
      app_forget_ports(id)
      app_forget_backup(id)
      app_forget_definition(id)
      if pool
        dataset = "#{pool}/#{APP_DATASETS}/#{id}"
        run_command([ZFS, 'destroy', '-r', dataset]) if zfs_dataset?(dataset)
        app_forget_storage(id)
      end
      run_command(['/usr/sbin/userdel', "app-#{id}", { allow_failure: true }]) if passwd("app-#{id}")
      { 'app' => id, 'data_kept' => false }
    end

    # { 'docker' => running?, 'apps' => { 'jellyfin' => { 'state' => 'running', ... } } }
    # 'jobs': the apps whose job runs now (their APP_JOB_UNIT): the Apps page leaves their rows
    # to the job.
    def do_apps_status
      out = docker_output('ps', '--all', '--filter', 'label=amahi.app', '--format', '{{json .}}')
      return { 'docker' => false, 'apps' => {}, 'jobs' => app_jobs_running } unless out

      apps = out.lines.filter_map do |line|
        row = JSON.parse(line)
        id = row['Labels'].to_s[/(?:\A|,)amahi\.app=([a-z0-9]+)/, 1] or next
        [id, { 'state' => row['State'], 'status' => row['Status'], 'image' => row['Image'] }]
      rescue JSON::ParserError
        nil
      end
      { 'docker' => true, 'apps' => apps.to_h, 'jobs' => app_jobs_running }
    end

    def app_jobs_running
      out, _err, status = Open3.capture3(ENV_MIN, SYSTEMCTL, 'list-units', '--plain', '--no-legend', '--state=active,activating',
                                         "#{format(APP_JOB_UNIT, '*')}.service", unsetenv_others: true, chdir: '/')
      return [] unless status.success?

      prefix = format(APP_JOB_UNIT, '')
      out.lines.map { |line| line.split.first.to_s.delete_prefix(prefix).delete_suffix('.service') }.grep(APP_ID)
    rescue SystemCallError
      []
    end

    # { 'ports' => ["amahi-jellyfin\t0.0.0.0:8096->8096/tcp", ...], 'limited' => true } for every
    # running container; limited when APP_CHAIN keeps them to the LAN and Tailscale.
    def do_docker_ports
      out = docker_output('ps', '--format', "{{.Names}}\t{{.Ports}}")
      { 'ports' => out.to_s.lines(chomp: true).reject(&:empty?), 'limited' => app_firewall_active? }
    end

    # docker's output, or nil when it isn't installed or isn't running.
    def docker_output(*args)
      return nil unless File.executable?(DOCKER)
      out, _err, status = Open3.capture3(ENV_MIN, [DOCKER, DOCKER], *args, unsetenv_others: true, chdir: '/')
      status.success? ? out : nil
    rescue SystemCallError
      nil
    end

    # --- Apps on the LAN (see AVAHI_SERVICES) ---

    def do_announce_apps
      return 'apps not announced on the LAN: avahi-daemon is not installed' unless File.directory?(AVAHI_SERVICES)

      status = do_apps_status
      return 'apps not announced on the LAN: Docker is not running' unless status['docker']

      wanted = status['apps'].keys.sort.filter_map { |id| app_announcement(id) }.to_h
      changed = false
      Dir[File.join(AVAHI_SERVICES, 'amahi-app-*.service')].each do |path|
        next if wanted.key?(File.basename(path))

        File.unlink(path)
        changed = true
      end
      wanted.each do |file, content|
        path = File.join(AVAHI_SERVICES, file)
        next if File.file?(path) && File.read(path) == content

        do_install(path, content, nil, '0644')
        changed = true
      end
      run_command(['/usr/bin/systemctl', 'try-reload-or-restart', 'avahi-daemon.service', { allow_failure: true }]) if changed
      allow_mdns
      { 'announced' => wanted.keys.map { |file| file.delete_prefix('amahi-app-').delete_suffix('.service') } }
    end

    # [file name, Avahi service file] for an installed app with a web page, on the host port it
    # was given (APP_PORTS), or nil. An app reached only through Tailscale (APP_ACCESS) isn't
    # announced: nothing on the LAN can open it.
    def app_announcement(id)
      return nil unless id.match?(APP_ID) && (path = app_manifest_path(id))

      data = YAML.safe_load(File.read(path))
      web = data['web_port']
      return nil unless data.is_a?(Hash) && web.is_a?(Integer) && data['access'] != 'tailscale'

      given = Array((read_json(APP_PORTS) || {})[id]).grep(Hash).find { |port| port['preferred'] == web }
      port = given && given['host'].is_a?(Integer) ? given['host'] : web
      name = data['name'].is_a?(String) && !data['name'].strip.empty? ? data['name'].strip : id
      scheme = data['web_tls'] == true ? 'https' : 'http'
      ["amahi-app-#{id}.service", <<~XML]
        <?xml version="1.0" standalone="no"?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <!-- Written by Amahi-kai's root helper (apps.announce); replaced when apps change. -->
        <service-group>
          <name replace-wildcards="yes">#{xml_text(name[0, 40])} on %h</name>
          <service>
            <type>_#{scheme}._tcp</type>
            <subtype>_#{id}._sub._#{scheme}._tcp</subtype>
            <port>#{port}</port>
            <txt-record>path=/</txt-record>
            <txt-record>app=#{id}</txt-record>
          </service>
        </service-group>
      XML
    rescue Psych::Exception, SystemCallError
      nil
    end

    def xml_text(text)
      text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub(/[^[:print:]]/, '')
    end

    # Lets mDNS through UFW when the security audit has turned it on.
    def allow_mdns
      return unless File.executable?(UFW)

      out, _err, status = Open3.capture3(ENV_MIN, [UFW, UFW], 'status', unsetenv_others: true, chdir: '/')
      run_command([UFW, 'allow', MDNS_PORT, { allow_failure: true }]) if status.success? && out.match?(/^Status: active/)
    rescue SystemCallError
      nil
    end

    # Whether something is mounted at +path+, a bind of a folder from the same filesystem too,
    # which keeps the folder's device number (mount_point? can't tell): the mount table says.
    def mounted_at?(path, mountinfo = '/proc/self/mountinfo')
      File.foreach(mountinfo).any? { |line| line.split(' ')[4] == path }
    rescue SystemCallError
      false
    end
  end
end
