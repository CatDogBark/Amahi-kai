# frozen_string_literal: true

# The helper's core: the operation table, the entry points, commands run as argument lists
# with a minimal environment, the helper's own file actions, the checks every area uses, and the log.
module AmahiHelper
  ENV_MIN = { 'PATH' => '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG' => 'C.UTF-8' }.freeze

  LOG_DIR = '/var/log/amahi-kai'

  LOG_FILE = "#{LOG_DIR}/helper.log".freeze

  MAX_INPUT = 2 * 1024 * 1024

  APP_USER = 'amahi'

  USERS_GROUP = 'users' # primary group of the accounts the app creates

  NOLOGIN = '/usr/sbin/nologin'

  UID_MIN = 1000

  SHARE_ROOT = '/var/lib/amahi-kai/files'

  DRIVES_ROOT = '/mnt' # data drives are mounted at /mnt/<name>

  DNSMASQ_CONF = '/etc/dnsmasq.d/amahi.conf'

  # Ubuntu's unbound.conf includes every unbound.conf.d/*.conf: Amahi-kai's, and the names of
  # the devices dnsmasq gave addresses to (do_sync_leases).
  UNBOUND_CONF = '/etc/unbound/unbound.conf.d/amahi-kai.conf'

  # While dnsmasq hands out addresses, systemd runs dns.sync_leases each time its lease file
  # changes, so the devices' names answer in DNS. PathModified, not PathChanged: dnsmasq keeps
  # the file open and rewrites it in place, so it's never closed after a write.
  DHCP_NAMES_PATH = '/etc/systemd/system/amahi-kai-dhcp-names.path'

  # DNS blocklists (Network → DNS, DHCP and Internet). BLOCKLISTS are the lists the NAS may download, by
  # key; the app names and describes the same keys (DnsService::BLOCKLISTS, a spec checks they
  # match). Each is a domain a line, "#" comments, and a domain covers its subdomains (HaGeZi's
  # and OISD's wildcard formats without "*."), as Unbound's local-zone does. Checked against
  # the projects' own pages 2026-10-22; both GPL-3.0, refreshed daily.
  HAGEZI = 'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard'

  BLOCKLISTS = {
    'hagezi-light' => { url: "#{HAGEZI}/light-onlydomains.txt" },
    'hagezi-normal' => { url: "#{HAGEZI}/multi-onlydomains.txt" },
    'hagezi-pro' => { url: "#{HAGEZI}/pro-onlydomains.txt" },
    'hagezi-tif-mini' => { url: "#{HAGEZI}/tif.mini-onlydomains.txt" },
    'hagezi-tif-medium' => { url: "#{HAGEZI}/tif.medium-onlydomains.txt" },
    'oisd-small' => { url: 'https://small.oisd.nl/domainswild2' },
    'oisd-big' => { url: 'https://big.oisd.nl/domainswild2' },
    # The known encrypted-DNS (DoH) providers, so a device can't go around the NAS's DNS by name.
    'hagezi-doh' => { url: "#{HAGEZI}/doh-onlydomains.txt" },
    # Vendors' own telemetry hosts, with the hosts their devices need left out.
    'hagezi-native-samsung' => { url: "#{HAGEZI}/native.samsung-onlydomains.txt" },
    'hagezi-native-lgwebos' => { url: "#{HAGEZI}/native.lgwebos-onlydomains.txt" },
    'hagezi-native-roku' => { url: "#{HAGEZI}/native.roku-onlydomains.txt" },
    'hagezi-native-amazon' => { url: "#{HAGEZI}/native.amazon-onlydomains.txt" },
    'hagezi-native-apple' => { url: "#{HAGEZI}/native.apple-onlydomains.txt" },
    'hagezi-native-winoffice' => { url: "#{HAGEZI}/native.winoffice-onlydomains.txt" },
    'hagezi-native-tiktok' => { url: "#{HAGEZI}/native.tiktok-onlydomains.txt" },
    'hagezi-native-xiaomi' => { url: "#{HAGEZI}/native.xiaomi-onlydomains.txt" }
  }.freeze

  # Root's own folder: the lists chosen and the allowlist, the copies downloaded, the blocklist
  # while blocking is paused, and the status the app reads. Not the app's: what's here becomes
  # Unbound's config.
  BLOCKLIST_DIR = '/var/lib/amahi-kai-dns'

  ULA_UNIT = '/etc/systemd/system/amahi-kai-ula.service'

  NETPLAN_DIR = '/etc/netplan'

  WAN_NETPLAN = "#{NETPLAN_DIR}/70-amahi-kai-wan.yaml".freeze

  ROUTER_STATE = "#{BLOCKLIST_DIR}/router.json".freeze

  ROUTER_BEGIN = '# BEGIN amahi-kai router'

  ROUTER_END = '# END amahi-kai router'

  ADDRESS_BACKUP_SUFFIX = '.amahi-kai-before-address'

  ADDRESS_APPLY_WAIT = 2

  ADDRESS_KEEP_WAIT = 90

  # The DNS and network operations that change what's in place run one at a time, the next
  # waiting its turn for up to NETWORK_LOCK_WAIT seconds: a keep and a revert of the NAS's
  # address, or two saves rewriting the router's rules, would otherwise interleave their steps.
  NETWORK_LOCK = '/run/amahi-kai-network.lock'

  NETWORK_LOCK_WAIT = 120

  NETWORK_LOCKED = %w[
    dns.write_config dns.remove_config dns.sync_leases dns.names_setup dns.set_blocklists dns.blocking_off dns.write_radvd_config
    dns.remove_radvd_config dns.set_own_address dns.remove_own_address network.write_dnsmasq_config network.router_on
    network.router_off network.set_address network.apply_address network.keep_address network.revert_address
  ].freeze

  # Checking for updates: bin/amahi-update holds UPDATE_LOCK while it runs, and the check
  # takes it too, so a fetch never races the update's pull. The check writes what it found
  # to UPDATE_STATUS (the app reads it). REPAIR_FLAG tells the next update to run every
  # step even with nothing new (bin/amahi-update reads and removes it).
  APP_DIR = '/opt/amahi-kai'

  UPDATE_LOCK = '/run/amahi-kai-update.lock'

  UPDATE_STATUS = '/var/lib/amahi-kai/update-status.json'

  UPDATE_CHANNELS = %w[releases candidates development].freeze

  FSTAB = '/etc/fstab'

  # Data drives: whole disks or partitions on SATA/SAS/virtio/Xen and NVMe devices,
  # mounted at /mnt/<name>. The fstab options are the ones PR #13 settled on: nofail and
  # a short timeout, so a missing drive can't stop the NAS booting.
  MNT = '/mnt'

  # How long a deleted user's sessions get to end before they're made to.
  USER_STOP_SECONDS = 5

  WHOLE_DISK = %r{\A/dev/(?:[svx]d[a-z]{1,2}|nvme\d{1,3}n\d{1,3})\z}

  # Data drives mount nosuid,nodev: nothing on a drive (one brought from elsewhere, or written
  # by an app) can run with privileges or stand in for a device. The share root, on the OS
  # disk, gets the same by a bind mount of itself (SHARE_ROOT_FSTAB). disks.secure_mounts
  # brings fstab lines written before (FSTAB_OPTIONS_BEFORE) and the live mounts up to this.
  MOUNT_OPTIONS = %w[nosuid nodev].freeze

  FSTAB_OPTIONS_BEFORE = 'defaults,nofail,x-systemd.device-timeout=10s'

  SHARE_ROOT_FSTAB = "#{SHARE_ROOT} #{SHARE_ROOT} none bind,#{MOUNT_OPTIONS.join(',')} 0 0".freeze

  # Where the helper makes its temporary folders (preview mounts, downloaded keys):
  # writable only by root.
  RUN_DIR = '/run'

  ZFS = '/usr/sbin/zfs'

  POOL_ROOT = '/srv/pools'

  POOL_NAME = /\A[a-z][a-z0-9_-]{0,31}\z/

  ARC_MARGIN = 64 * 1024**2

  GREYHOLE_CONF = '/etc/greyhole.conf'

  # Greyhole's trash folder on each pool drive, and the root-only folder beside it where a file
  # being restored is staged.
  GREYHOLE_TRASH = '.gh_trash'

  # greyhole.conf without its database lines, for amahi-dfree: anyone may read it.
  GREYHOLE_POOL_CONF = '/etc/amahi-kai/greyhole-pool.conf'

  # apt repositories the helper may add. The signing key is downloaded over HTTPS and
  # accepted only if the fingerprints in it (the key and its subkeys, as `gpg --show-keys`
  # lists them) are exactly the ones pinned here, so a key added to the file is refused.
  # A .gpg keyring is stored binary (dearmored), a .asc one armored. %<codename>s and
  # %<arch>s are filled from /etc/os-release and dpkg. The keyring and list paths are the
  # ones earlier installs used, so a repository that is already set up is rewritten in
  # place rather than added twice.
  APT_REPOSITORIES = {
    'greyhole' => {
      key_url: 'https://www.greyhole.net/releases/deb/greyhole-debsig.asc',
      # Checked against the published key on the NAS, 2026-10-04.
      fingerprints: %w[6ADB83262FA757410B33E13978B31B49B8D12778 8DD897BA66D40E90A47CE092AF19B5B28FADF99F].freeze,
      keyring: '/usr/share/keyrings/greyhole-archive-keyring.asc',
      list: '/etc/apt/sources.list.d/greyhole.list',
      source: 'deb [signed-by=/usr/share/keyrings/greyhole-archive-keyring.asc] https://www.greyhole.net/releases/deb stable main'
    }.freeze,
    'cloudflared' => {
      key_url: 'https://pkg.cloudflare.com/cloudflare-main.gpg',
      # Checked against the published key on the NAS, 2026-10-04.
      fingerprints: %w[CC94B39C77AE7342A68B89628A682D308D4E5E73 06C89DB3B80A8F4349697C76029E1444B7D9F50F].freeze,
      keyring: '/usr/share/keyrings/cloudflare-archive-keyring.gpg',
      list: '/etc/apt/sources.list.d/cloudflared.list',
      source: 'deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main'
    }.freeze,
    'tailscale' => {
      key_url: 'https://pkgs.tailscale.com/stable/ubuntu/%<codename>s.noarmor.gpg',
      # Checked against the published key on the NAS, 2026-10-04.
      fingerprints: %w[2596A99EAAB33821893C0A79458CA832957F5868 2F625B3A774B946822EDDBEEB1547A3DDAAF03C6].freeze,
      keyring: '/usr/share/keyrings/tailscale-archive-keyring.gpg',
      list: '/etc/apt/sources.list.d/tailscale.list',
      source: 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu %<codename>s main'
    }.freeze,
    'docker' => {
      key_url: 'https://download.docker.com/linux/ubuntu/gpg',
      # Checked against the published key here and on the NAS, 2026-10-04.
      fingerprints: %w[9DC858229FC7DD38854AE2D88D81803C0EBFCD88 D3306A018370199E527AE7997EA0A9C3F273FCD8].freeze,
      keyring: '/usr/share/keyrings/docker-archive-keyring.gpg',
      list: '/etc/apt/sources.list.d/docker.list',
      source: 'deb [arch=%<arch>s signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ' \
              'https://download.docker.com/linux/ubuntu %<codename>s stable'
    }.freeze
  }.freeze

  APT_ENV = ENV_MIN.merge('DEBIAN_FRONTEND' => 'noninteractive').freeze

  # apt runs as a unit of its own (run_command), outside whichever unit called the helper.
  APT_GET = '/usr/bin/apt-get'

  APT_UNIT = 'amahi-kai-apt'

  SYSTEMD_RUN = '/usr/bin/systemd-run'

  TAILSCALE = '/usr/bin/tailscale'

  # Apps (docs/plans/apps.md, P4.1). The helper is the only way the web app reaches Docker. It
  # installs, starts, stops and removes the catalog's apps, each built from its manifest in the
  # root-owned code (APP_MANIFESTS), never from anything the web app sends: the web app only
  # names an app. Each app gets a system user (app-<id>, a uid below UID_MIN, so the users.*
  # operations can't touch it) owning its folders under APPS_ROOT, and secrets generated at
  # install in APP_SECRETS (root:amahi 0640, shown to admins).
  DOCKER = '/usr/bin/docker'
  JOURNALCTL = '/usr/bin/journalctl'
  # A log line handed to the app (system.journal, apps.logs) is cut at this many characters.
  LOG_LINE_MAX = 2000

  APP_MANIFESTS = "#{APP_DIR}/config/apps".freeze

  APPS_ROOT = '/var/lib/amahi-kai/apps'

  APP_SECRETS = '/var/lib/amahi-kai/app-secrets'

  APP_ID = /\A[a-z][a-z0-9]{1,23}\z/

  # Format 4: an environment name as the app spells its setting (PiGallery2's Media-folder), and a
  # generated secret inside a value ({{secret:NAME}}, NAME one of the manifest's secrets).
  APP_ENV_NAME_SPELLED = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/

  # The apps' jobs that can run for minutes (an image's download, an update's wait for health)
  # each run as a unit of their own, APP_JOB_UNIT with the app's id (relay_app_job): the helper
  # runs inside the unit that called it, the web app's, and a restart of the web app took a job
  # down partway. The unit's name also keeps one job at a time for an app.
  APP_JOBS = %w[apps.install apps.update apps.undo_update apps.uninstall].freeze

  APP_JOB_UNIT = 'amahi-kai-appjob-%s'

  HELPER_PATH = '/usr/local/sbin/amahi-helper'

  SYSTEMCTL = '/usr/bin/systemctl'

  # The catalog has a repo of its own (docs/plans/apps.md), so app versions don't wait for an
  # Amahi-kai update. The update check (system.check_update, every 6 hours and on Check now)
  # fetches its main branch too, over https only, into CATALOG_SRC (a bare repo, root's), and keeps
  # the manifests that pass every check below in APP_CATALOG/apps, which comes first;
  # APP_MANIFESTS, the copy in the code, is the fallback (before the first fetch, and for an app
  # the catalog no longer lists). A manifest's `requires` is the catalog format it needs: one
  # above CATALOG_FORMAT is listed but can't be installed until System Update brings an
  # Amahi-kai that knows it. Format 2 adds `web_tls` (the app's page is HTTPS, its certificate its
  # own), format 3 folders' `kind` and `required`, format 4 environment names as the app spells
  # them and secrets inside values (APP_ENV_NAME_SPELLED), format 5 apps reached only through
  # Tailscale (APP_ACCESS) and secrets the container gets hashed (APP_SECRET_HASHES).
  CATALOG_REPO = 'https://github.com/CatDogBark/amahi-kai-apps.git'

  CATALOG_SRC = '/var/lib/amahi-kai/catalog-src'

  APP_CATALOG = '/var/lib/amahi-kai/catalog'

  CATALOG_FORMAT = 5

  # Who reaches an app (format 5, P4.7): the LAN and Tailscale (lan, the default), or only
  # devices on the NAS's tailnet, over HTTPS (tailscale): its ports are published on the NAS
  # itself only, and its web page is served on the tailnet by `tailscale serve`, with Tailscale's
  # certificate for the NAS's name, at the same port number. Browsers keep some apps' pages
  # from working over plain HTTP (Vaultwarden's web vault encrypts in the page), and the
  # Bitwarden apps refuse it. {{tailscale_url}} in its environment is that address.
  APP_ACCESS = %w[lan tailscale].freeze

  # A secret's `hash` (format 5): the container gets an Argon2id hash of it, in the PHC form
  # (Vaultwarden's ADMIN_TOKEN takes one), while the admin pages show the secret itself to sign
  # in with. OWASP's settings; argon2 (Ubuntu's package) is installed the first time it's needed.
  APP_SECRET_HASHES = %w[argon2].freeze

  # The host ports each app was given (P4.2): its catalog ports when they're free, others when
  # not, kept for its next install. root:amahi 0640, so the Apps page can show them.
  APP_PORTS = '/var/lib/amahi-kai/app-ports.json'

  # Apps' storage on a ZFS pool (P4.6). A manifest's folders are kept on the system disk
  # (kind: state, the default: what the app needs to run), or on a dataset of the app's own,
  # <pool>/apps/<id>, on the pool chosen at install (kind: dataset: the data that grows), in the
  # pool's snapshots. Each app's pool is recorded here, { id => pool }, root:amahi 0640, so its
  # container is made again on the same pool (an update, a reinstall, the pool changing), and
  # the Apps and ZFS Pools pages can say where it is. Uninstall keeps the dataset unless asked.
  APP_STORAGE = '/var/lib/amahi-kai/app-storage.json'

  # Who can reach the apps' ports (P4.2). Docker's rules for published ports come before UFW's,
  # so the helper adds its own chain to Docker's DOCKER-USER: connections to a container from
  # anywhere but the NAS's own private subnets and Tailscale are dropped. That covers a port
  # forward on the router, and a future internet-facing port (router mode). Traffic from the
  # NAS itself (cloudflared) doesn't pass through it. Apps are published on IPv4 only.
  IPTABLES = '/usr/sbin/iptables'

  IP = '/usr/sbin/ip'

  APP_CHAIN = 'AMAHI-APPS'

  APP_SHARE_BINDS = '/var/lib/amahi-kai/app-share-binds.json'

  APP_BACKUP_DAYS = 30

  APP_HEALTH_TIMEOUT = 300

  # The security audit's fixes. UFW lets in SSH, the web UI, HTTPS, Samba and mDNS (apps
  # announced on the LAN). DNS gets in to Unbound's addresses only, and DHCP on dnsmasq's
  # interface only, by the rules dns.write_config and network.write_dnsmasq_config add (UFW
  # keeps them while it's off).
  UFW = '/usr/sbin/ufw'

  LOGIN = /\A[a-z][a-z0-9]{2,31}\z/

  RESERVED_LOGINS = %w[root amahi nobody].freeze

  # Refused: the request is invalid and nothing was changed. Failed: a step failed.
  class Refused < StandardError; end

  class Failed < StandardError; end

  # A network interface's name, as the checks below take it: at most 15 characters, starting
  # with a letter or digit, so neither . nor .. (both are folders in /sys/class/net) passes,
  # nor a name a command would read as an option.
  IFNAME = '[A-Za-z0-9][A-Za-z0-9_.-]{0,14}'

  # --- dnsmasq config checks ---------------------------------------------------------

  # dnsmasq can run scripts as root and read any file from its config, and the app
  # writes these files whole, so every line must be one the app generates.
  IPV4 = '(?:(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)'

  DOMAIN = '[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?'

  # A device's name on a dhcp-host line: one label, and not a word dnsmasq reads there as an
  # order (ignore: no address for it; infinite: a lease that never ends).
  DHCP_NAME = '(?!(?:ignore|infinite)\\b(?!-))[a-z][a-z0-9-]{0,62}'

  DNSMASQ_LINES = [
    /\Adhcp-range=#{IPV4},#{IPV4},\d{1,7}s\z/,
    /\Adhcp-option=option:router,#{IPV4}\z/,
    /\Adhcp-authoritative\z/,
    /\Adhcp-host=(?:[0-9a-f]{2}:){5}[0-9a-f]{2},#{IPV4},#{DHCP_NAME}\z/o,
    # A device named without a fixed address: its name, wherever it is (Network → Devices)
    /\Adhcp-host=(?:[0-9a-f]{2}:){5}[0-9a-f]{2},#{DHCP_NAME}\z/o,
    %r{\Alocal=/#{DOMAIN}/\z}i,
    /\Aexpand-hosts\z/,
    /\Adomain=#{DOMAIN}\z/i,
    /\Abind-interfaces\z/,
    /\Aexcept-interface=lo\z/,
    /\Aport=0\z/,
    /\Adhcp-option=option:dns-server,#{IPV4}\z/,
    /\Ainterface=#{IFNAME}\z/
  ].freeze

  # A name with its final dot ("nas.home.arpa."), and a TLS name ("dns.quad9.net").
  UNBOUND_NAME = '(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+'


  # Each operation lists its arguments, checks them (validate returns the clean values)
  # and plans its steps. A step is an argument list: a command starts with its absolute
  # path; the helper's own file actions start with a symbol. An optional last Hash holds
  # :stdin and :allow_failure.
  # Each part adds its operations with add_operations; the entry freezes the table once every part
  # has. An operation named in two parts is refused as the helper loads.
  OPERATIONS = {}

  def self.add_operations(table)
    table.each do |name, operation|
      raise ArgumentError, "the operation #{name} is in two parts of the helper" if OPERATIONS.key?(name)

      OPERATIONS[name] = operation
    end
  end

  class << self
    # --- Entry points --------------------------------------------------------------

    # The checking modes (--dry-run, --check-catalog) are for a person at a root shell and the
    # catalog's CI: through the app's sudo rule they're refused, so the app can only run
    # operations, which are logged.
    def main(argv, input: $stdin, output: $stdout)
      case argv
      in ['--self-test'] then self_test(output)
      in ['--list'] then output.puts(OPERATIONS.keys) || 0
      in ['--dry-run' | '--check-catalog', String] if ENV.key?('SUDO_USER')
        warn 'amahi-helper: --dry-run and --check-catalog are not available through sudo'
        1
      in ['--dry-run', String => op] then respond(output) { dry_run(op, read_args(input)) }
      in ['--check-catalog', String => dir] then check_catalog(dir, output)
      in [String => op] if APP_JOBS.include?(op) && !ENV.key?('AMAHI_APP_JOB') then relay_app_job(op, input, output)
      in [String => op] unless op.start_with?('-') then respond(output) { execute(op, input) }
      else
        warn 'usage: amahi-helper OPERATION < args.json | --dry-run OPERATION | --check-catalog DIR | --list | --self-test'
        2
      end
    end

    # Reads the arguments (from +input+, or a Hash), validates them and runs the
    # operation's steps; returns the reply Hash. Logs the call whatever happens.
    def execute(op, input)
      started = Time.now
      result = 'ok'
      args = input.respond_to?(:read) ? read_args(input) : input
      check_environment!
      raise Refused, 'the helper must run as root' unless Process.euid.zero?
      values = validate(op, args)
      results = one_at_a_time(op) { plan(op, values).filter_map { |step| perform(step) } }
      reply = { 'ok' => true }
      results.grep(Hash).each { |data| reply.merge!(data) }
      notes = results.grep(String)
      notes.empty? ? reply : reply.merge('notes' => notes)
    rescue StandardError => e
      result = e.is_a?(Refused) ? 'refused' : 'failed'
      error = e.message
      raise
    ensure
      log(op, args, result, error, started)
    end

    # The operation's steps, holding NETWORK_LOCK when it's one of NETWORK_LOCKED.
    def one_at_a_time(op)
      return yield unless NETWORK_LOCKED.include?(op)

      File.open(NETWORK_LOCK, File::RDWR | File::CREAT, 0o600) do |lock|
        deadline = monotonic_now + NETWORK_LOCK_WAIT
        until lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise Refused, 'another network change is still being made; try again in a minute' if monotonic_now > deadline
          pause(0.5)
        end
        yield
      end
    end

    # A job that can run for minutes (APP_JOBS) runs again as a unit of its own, APP_JOB_UNIT with
    # the app's id, on the same arguments: the helper runs inside the unit that called it, the
    # web app's, and a restart of the web app took the job down partway, leaving the app half
    # installed. systemd-run --pipe passes the job's progress and reply through, --wait its exit
    # status; while one job of an app runs, another is refused. Arguments that name no app are
    # refused here, as they would be there.
    def relay_app_job(op, input, output)
      raw = input.read(MAX_INPUT + 1).to_s
      return respond(output) { raise Refused, 'arguments are too large' } if raw.bytesize > MAX_INPUT

      args = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      id = args.is_a?(Hash) ? args['app'] : nil
      return respond(output) { execute(op, args) } unless id.is_a?(String) && id.match?(APP_ID)
      return respond(output) { not_in_a_job!(id) } if app_job_running?(id)

      job_input = File.open(File.join(RUN_DIR, "amahi-app-job-#{SecureRandom.hex(8)}"), File::RDWR | File::CREAT | File::EXCL, 0o600)
      job_input.write(raw)
      job_input.rewind
      File.unlink(job_input.path)
      replace_process(ENV_MIN, [SYSTEMD_RUN, "--unit=#{format(APP_JOB_UNIT, id)}", '--wait', '--pipe', '--collect', '--quiet',
                                "--setenv=AMAHI_APP_JOB=#{id}", "--setenv=AMAHI_APP_CALLER=#{ENV.fetch('SUDO_USER', '')}",
                                HELPER_PATH, op], in: job_input)
    rescue SystemCallError => e
      respond(output) { raise Failed, "#{id}'s job couldn't be started (#{e.message})" }
    end

    # exec, as a method a spec can stand in for.
    def replace_process(env, argv, **options)
      exec(env, [argv[0], argv[0]], *argv.drop(1), unsetenv_others: true, chdir: '/', **options)
    end

    def dry_run(op, args)
      { 'ok' => true, 'steps' => plan(op, validate(op, args)).map { |step| describe(step) } }
    end

    def validate(op, args)
      spec = OPERATIONS[op] or raise Refused, "unknown operation #{op.inspect}"
      raise Refused, 'arguments must be a JSON object' unless args.is_a?(Hash)
      extra = args.keys - spec[:params]
      raise Refused, "unexpected argument #{extra.first}" if extra.any?
      spec[:validate].call(args)
    end

    def plan(op, values)
      OPERATIONS.fetch(op)[:plan].call(values)
    end

    def self_test(output)
      problems = OPERATIONS.flat_map do |name, spec|
        list = []
        list << "#{name}: bad name" unless name.match?(/\A[a-z]+\.[a-z_]+\z/)
        list << "#{name}: params must be a list of names" unless spec[:params].is_a?(Array) && spec[:params].all?(String)
        list << "#{name}: validate and plan must be lambdas" unless spec[:validate].lambda? && spec[:plan].lambda?
        list
      end
      problems << 'gems are loaded; run with --disable-gems' if defined?(::Gem)
      if problems.empty?
        output.puts "ok: #{OPERATIONS.size} operations"
        0
      else
        output.puts problems
        1
      end
    end

    # --- Argument checks -------------------------------------------------------------

    def string(value, what, max:)
      raise Refused, "#{what} is missing" if value.nil? || value == ''
      raise Refused, "#{what} must be a string" unless value.is_a?(String)
      raise Refused, "#{what} is not valid UTF-8" unless value.dup.force_encoding('UTF-8').valid_encoding?
      raise Refused, "#{what} is too long (at most #{max} characters)" if value.length > max
      raise Refused, "#{what} contains a NUL byte" if value.include?("\0")
      value
    end

    # The last +count+ lines of +text+, each cut to LOG_LINE_MAX characters and made valid UTF-8.
    def log_lines(text, count)
      text.to_s.dup.force_encoding('UTF-8').scrub('?').lines(chomp: true).last(count).map { |line| line[0, LOG_LINE_MAX] }
    end

    def integer(args, key, range)
      value = args[key]
      raise Refused, "#{key} must be a whole number from #{range.min} to #{range.max}" unless value.is_a?(Integer) && range.cover?(value)
      value
    end

    def boolean(args, key)
      value = args[key]
      raise Refused, "#{key} must be true or false" unless [true, false].include?(value)
      value
    end

    def login(value)
      value = string(value, 'login', max: 32)
      raise Refused, "login #{value.inspect} must be 3-32 lowercase letters or digits, starting with a letter" unless value.match?(LOGIN)
      raise Refused, "login #{value} is reserved" if RESERVED_LOGINS.include?(value)
      value
    end

    # Refused while a job of the app's runs (APP_JOBS): an install, update, undo or uninstall.
    def not_in_a_job!(id)
      raise Refused, "#{id} is being changed (an install, update or uninstall runs): try again when it's done" if app_job_running?(id)
    end

    # Whether the app's job unit runs now; never the job itself, which runs inside it.
    def app_job_running?(id)
      return false if ENV['AMAHI_APP_JOB'] == id

      _out, _err, status = Open3.capture3(ENV_MIN, SYSTEMCTL, 'is-active', '--quiet', "#{format(APP_JOB_UNIT, id)}.service",
                                         unsetenv_others: true, chdir: '/')
      status.success?
    rescue SystemCallError
      false
    end

    def listed(value, what, allowed)
      value = string(value, what, max: 64)
      raise Refused, "#{what} #{value.inspect} isn't one Amahi-kai uses" unless allowed.include?(value)
      value
    end

    def installed!(program)
      raise Refused, "#{File.basename(program)} isn't installed" unless File.executable?(program)
      true
    end

    def password(value)
      value = string(value, 'password', max: 256)
      raise Refused, 'password contains a line break' if value.match?(/[\r\n]/)
      value
    end

    def normalized_path?(path)
      path.start_with?('/') && path.length > 1 && !path.end_with?('/') &&
        path.split('/').drop(1).none? { |part| part.empty? || part == '.' || part == '..' }
    end

    # --- Steps ------------------------------------------------------------------------

    # Runs one step; returns a note for the reply (String), data for it (Hash), or nil.
    def perform(step)
      return run_command(step) unless step.first.is_a?(Symbol)
      action, *rest = step
      send(:"do_#{action}", *rest)
    end

    # Options in the step's last Hash: :stdin, :allow_failure, :env (replaces ENV_MIN),
    # and :stream, which copies the command's output to stderr line by line as it runs
    # (Privileged.call passes it on, so long installs show progress).
    def run_command(step)
      argv = step.dup
      opts = argv.last.is_a?(Hash) ? argv.pop : {}
      env = opts[:env] || ENV_MIN
      name = File.basename(argv[0])
      argv, env = in_own_unit(argv, env) if argv[0] == APT_GET
      if opts[:stream]
        err, status = stream_command(env, argv)
      else
        _out, err, status = Open3.capture3(env, [argv[0], argv[0]], *argv.drop(1),
                                           stdin_data: opts[:stdin].to_s, unsetenv_others: true, chdir: '/')
      end
      return nil if status.success?
      message = "#{name} exited #{status.exitstatus}: #{last_lines(err, 3)}"
      return "ignored: #{message}" if opts[:allow_failure]
      raise Failed, message
    rescue SystemCallError => e
      return "ignored: #{argv[0]}: #{e.message}" if opts&.dig(:allow_failure)
      raise Failed, "#{argv[0]}: #{e.message}"
    end

    # apt, as a unit of its own: the helper runs inside the unit that called it (the web app's,
    # for System Dependencies), and a MariaDB update stops MariaDB, which stops the app, and
    # needrestart can restart the app; neither may take dpkg down with it partway. --pipe
    # streams apt's output here, --wait hands back its exit status, and the one unit name keeps
    # package jobs one at a time (a second is refused while the first runs).
    def in_own_unit(argv, env)
      [[SYSTEMD_RUN, "--unit=#{APT_UNIT}", '--wait', '--pipe', '--collect', '--quiet',
        *env.map { |key, value| "--setenv=#{key}=#{value}" }, *argv], ENV_MIN]
    end

    def stream_command(env, argv)
      tail = []
      status = Open3.popen2e(env, [argv[0], argv[0]], *argv.drop(1), unsetenv_others: true, chdir: '/') do |stdin, out, wait|
        stdin.close
        forwarding = true
        out.each_line do |line|
          tail = (tail << line).last(3)
          next unless forwarding
          begin
            $stderr.puts(line.chomp)
            $stderr.flush
          rescue IOError, SystemCallError
            forwarding = false # the caller stopped listening; let the command finish
          end
        end
        wait.value
      end
      [tail.join, status]
    end

    # A command's standard output; raises Failed if it fails.
    def capture(argv)
      out, err, status = Open3.capture3(ENV_MIN, [argv[0], argv[0]], *argv.drop(1), unsetenv_others: true, chdir: '/')
      raise Failed, "#{File.basename(argv[0])} exited #{status.exitstatus}: #{last_lines(err, 3)}" unless status.success?
      out
    rescue SystemCallError => e
      raise Failed, "#{argv[0]}: #{e.message}"
    end

    # Makes the folders from the share root down, each through a handle on the folder above
    # (its /proc/self/fd path), never through the path: a part swapped for a link while this
    # runs can't send the new folder elsewhere. A link anywhere on the way is refused.
    def do_mkdir_p(path)
      root = share_root_of(path) or raise Failed, "#{path} is no longer inside a share root"
      dir = open_dir(root)
      current = root
      path.delete_prefix("#{root}/").split('/').each do |part|
        current = "#{current}/#{part}"
        child = "/proc/self/fd/#{dir.fileno}/#{part}"
        begin
          Dir.mkdir(child, 0o755)
        rescue Errno::EEXIST
          nil # checked by the open below: a folder, not a link or a file
        end
        dir = open_dir(child, dir, current)
      end
      raise Failed, "#{path} moved while it was being made" unless File.readlink("/proc/self/fd/#{dir.fileno}") == path
      nil
    ensure
      dir&.close
    end

    # A handle on the folder at +path+, not following a link there; +parent+ is closed once
    # the child is open. +shown+ is the path for messages (a /proc path says nothing).
    def open_dir(path, parent = nil, shown = path)
      dir = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
      unless dir.stat.directory?
        dir.close
        raise Failed, "#{shown} is not a folder"
      end
      dir
    rescue Errno::ELOOP
      raise Failed, "#{shown} is a symbolic link"
    rescue Errno::ENOENT
      raise Failed, "#{shown} doesn't exist"
    ensure
      parent&.close
    end

    def do_own_dir(path, user, group, mode)
      with_dir(path) do |dir|
        dir.chown(Etc.getpwnam(user).uid, group_id(group))
        dir.chmod(Integer(mode, 8))
      end
      nil
    end

    # Opens the folder at +path+ without following a symlink and checks that what it
    # opened really is +path+, so a folder swapped for a symlink can't redirect the change.
    # The change is then made through the open file, to the folder that was checked.
    def with_dir(path)
      raise Failed, "#{path} is not a folder" unless File.lstat(path).directory?
      File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |dir|
        raise Failed, "#{path} is not a folder" unless dir.stat.directory?
        raise Failed, "#{path} moved while it was being changed" unless File.readlink("/proc/self/fd/#{dir.fileno}") == path
        yield dir
      end
    rescue Errno::ENOENT
      raise Failed, "#{path} doesn't exist"
    rescue Errno::ELOOP
      raise Failed, "#{path} is a symbolic link"
    end

    # Writes +content+ to a new file next to +target+, checks it, then renames it into
    # place, so readers see the old file or the new one, never half of one. dnsmasq's
    # folder is created if dnsmasq isn't installed yet, so its config is ready when it is.
    # (dnsmasq and Samba skip the temporary file: its name starts with a dot.)
    def do_install(target, content, check, mode = '0644', group = nil)
      Dir.mkdir(File.dirname(target), 0o755) if check == :dnsmasq && !File.directory?(File.dirname(target))
      tmp = File.join(File.dirname(target), ".#{File.basename(target)}.amahi-#{SecureRandom.hex(6)}")
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |f|
        f.binmode # keyrings are binary; nothing is transcoded
        f.write(content)
        f.fsync
        f.chown(0, group_id(group) || 0) if group
        f.chmod(Integer(mode, 8))
      end
      check_smb_conf(tmp) if check == :smb_conf
      check_dnsmasq_conf(tmp) if check == :dnsmasq
      check_unbound_conf(tmp) if check == :unbound
      check_radvd_conf(tmp) if check == :radvd
      File.rename(tmp, target)
      nil
    rescue SystemCallError => e
      raise Failed, "couldn't write #{target}: #{e.message}"
    ensure
      File.unlink(tmp) if tmp && File.exist?(tmp)
    end

    # Files a plan names (never a path from the request).
    def do_remove_files(*paths)
      paths.each { |path| File.unlink(path) if File.exist?(path) || File.symlink?(path) }
      nil
    rescue SystemCallError => e
      raise Failed, "couldn't remove #{e.message}"
    end

    def read_json(path)
      JSON.parse(File.read(path))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # --- Apps ---

    # A progress line for the caller (Privileged.call's block), like a streamed command's.
    def say(line)
      $stderr.puts(line)
      $stderr.flush
    rescue IOError, SystemCallError
      nil
    end

    def free_space(path)
      capture(['/usr/bin/df', '--output=avail', '-B1', '--', path]).lines.last.to_i
    end

    def gigabytes(bytes)
      format('%.1f', bytes / 1024.0**3)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def pause(seconds)
      sleep(seconds)
    end

    def do_make_dir(path, mode)
      Dir.mkdir(path, Integer(mode, 8)) unless File.directory?(path)
      nil
    end

    # --- Plumbing -------------------------------------------------------------------

    # sudo clears these; refuse if they reached a root process some other way.
    def check_environment!
      bad = %w[RUBYOPT RUBYLIB].select { |name| ENV.key?(name) }
      raise Refused, "refusing to run with #{bad.join(' and ')} set" if bad.any?
    end

    def read_args(input)
      data = input.read(MAX_INPUT + 1).to_s
      raise Refused, 'arguments are too large' if data.bytesize > MAX_INPUT
      data.strip.empty? ? {} : JSON.parse(data)
    rescue JSON::ParserError
      raise Refused, 'arguments are not valid JSON'
    end

    def respond(output)
      output.puts JSON.generate(yield)
      0
    rescue Refused => e
      output.puts JSON.generate('ok' => false, 'error' => e.message)
      1
    rescue StandardError => e
      message = e.is_a?(Failed) ? e.message : "internal error: #{e.class}: #{e.message}"
      output.puts JSON.generate('ok' => false, 'error' => message)
      2
    end

    def last_lines(text, count)
      text.lines.map(&:strip).reject(&:empty?).last(count).join(' ')
    end

    def passwd(login)
      Etc.getpwnam(login)
    rescue ArgumentError
      nil
    end

    def group_id(name)
      Etc.getgrnam(name).gid
    rescue ArgumentError
      nil
    end

    # One JSON line per call. A log that can't be written doesn't stop the operation.
    def log(op, args, result, error, started)
      entry = {
        'time' => Time.now.utc.iso8601(3), 'op' => op, 'args' => filtered(args),
        'caller' => ENV['SUDO_USER'] || app_job_caller || Etc.getpwuid(Process.uid)&.name,
        'result' => result, 'error' => error, 'ms' => ((Time.now - started) * 1000).round
      }.compact
      write_log(JSON.generate(entry))
    rescue StandardError => e
      warn "amahi-helper: couldn't write #{LOG_FILE}: #{e.message}"
    end

    # Who asked for the app job this runs (relay_app_job), or nil.
    def app_job_caller
      caller = ENV['AMAHI_APP_CALLER'].to_s
      caller.empty? ? nil : caller
    end

    # The log is root:amahi 0640 in a root:amahi 0750 folder, so the app can show it.
    def write_log(line)
      gid = group_id(APP_USER)
      unless File.directory?(LOG_DIR)
        Dir.mkdir(LOG_DIR, 0o750)
        File.chown(0, gid, LOG_DIR) if gid
      end
      File.open(LOG_FILE, File::WRONLY | File::APPEND | File::CREAT | File::NOFOLLOW, 0o640) do |f|
        f.chown(0, gid) if gid && f.stat.gid != gid
        f.puts(line)
      end
    end

    def filtered(args)
      return '(not a JSON object)' unless args.is_a?(Hash)
      args.to_h do |key, value|
        if key.to_s.match?(/pass|secret|token|key/i)
          [key, '[FILTERED]']
        elsif key == 'content' && value.is_a?(String)
          [key, { 'bytes' => value.bytesize, 'sha256' => Digest::SHA256.hexdigest(value) }]
        elsif value.is_a?(String) && value.length > 256
          [key, "#{value[0, 256]}..."]
        else
          [key, value]
        end
      end
    end
  end
end
