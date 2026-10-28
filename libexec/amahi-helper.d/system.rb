# frozen_string_literal: true

# The system: System Update, packages, services, swap, reboot and power off, and the security
# audit's fixes.
module AmahiHelper
  # The services Settings → Servers may control: the entries in lib/system_services.rb
  # that list actions (spec/lib/amahi_helper_spec.rb checks the two lists match).
  SERVICES = {
    'smbd' => 'smbd.service', 'nmbd' => 'nmbd.service', 'dnsmasq' => 'dnsmasq.service', 'unbound' => 'unbound.service',
    'radvd' => 'radvd.service',
    'greyhole' => 'greyhole.service', 'docker' => 'docker.service', 'avahi-daemon' => 'avahi-daemon.service'
  }.freeze

  UPDATE_UNIT = '/etc/systemd/system/amahi-kai-update.service'

  GIT = '/usr/bin/git'

  GIT_OPTIONS = ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-C', APP_DIR].freeze

  UPDATE_REPAIR_FLAG = '/run/amahi-kai-update.repair'

  UPDATE_LIST_LIMIT = 50

  # Where System Update gets new versions: AMAHI_UPDATE_CHANNEL in ENV_FILE (root's), one of
  # UPDATE_CHANNELS. releases, the default, installs the newest release published on GitHub;
  # candidates also its pre-releases (release candidates); development the dev branch's newest
  # commit, for testing. A release is a tag vX.Y.Z (a candidate vX.Y.ZrcN) whose commit's VERSION
  # file names that version. Nothing newer than what runs is never a reason to go back.
  ENV_FILE = '/etc/amahi-kai/amahi.env'

  RELEASES_URL = 'https://api.github.com/repos/CatDogBark/Amahi-kai/releases?per_page=30'

  RELEASE_TAG = /\Av(\d{1,4})\.(\d{1,4})\.(\d{1,4})(?:rc(\d{1,4}))?\z/

  RELEASE_VERSION = /\A\d{1,4}\.\d{1,4}\.\d{1,4}(?:rc\d{1,4})?\z/

  SWAPFILE = '/swapfile'

  OS_RELEASE = '/etc/os-release'

  # Packages the helper may install.
  PACKAGES = %w[
    greyhole php8.3-mbstring php8.3-mysql cloudflared tailscale docker-ce docker-ce-cli containerd.io
    dnsmasq unbound dns-root-data radvd fail2ban unattended-upgrades zfsutils-linux smartmontools avahi-daemon
  ].freeze

  CATALOG_PROTOCOLS = %w[https].freeze

  CATALOG_STATUS = '/var/lib/amahi-kai/catalog-status.json'

  CATALOG_LOCK = '/run/amahi-kai-catalog.lock'

  CATALOG_MAX_APPS = 200

  CATALOG_MAX_BYTES = 64 * 1024

  FIREWALL_PORTS = %w[22/tcp 3000/tcp 443/tcp 445/tcp 139/tcp 137:138/udp 5353/udp].freeze

  # sshd uses the first value it reads for a setting, and sshd_config includes
  # sshd_config.d/*.conf first, in name order: 10-amahi-kai.conf comes before Ubuntu's
  # 50-cloud-init.conf.
  SSHD = '/usr/sbin/sshd'

  SSHD_DROPIN = '/etc/ssh/sshd_config.d/10-amahi-kai.conf'

  SSH_HARDENING = {
    'root_login' => { 'PermitRootLogin' => 'no' },
    'password_login' => { 'PasswordAuthentication' => 'no', 'KbdInteractiveAuthentication' => 'no' }
  }.freeze

  SSH_REPORTED = %w[permitrootlogin passwordauthentication kbdinteractiveauthentication].freeze

  AUTO_UPGRADES = '/etc/apt/apt.conf.d/20auto-upgrades'

  # The security updates waiting, and since when each was first seen, for the dashboard's
  # notice (Settings → System Dependencies installs them; nothing installs them by itself
  # unless automatic updates are on).
  SECURITY_UPDATES = '/var/lib/amahi-kai/security-updates.json'

  PACKAGE_NAME = /\A[a-z0-9][a-z0-9+.\-]{0,99}(?::[a-z0-9]+)?\z/

  # Updates run with needrestart only listing what to restart (it would otherwise restart
  # services, Amahi-kai's own among them, in the middle of the update's window).
  UPGRADE_ENV = APT_ENV.merge('NEEDRESTART_MODE' => 'l').freeze

  # --no-remove: apt stops rather than remove a package to make an update fit (the page offers
  # updates, nothing else).
  UPGRADE_OPTIONS = ['-o', 'Dpkg::Options::=--force-confold', '-o', 'DPkg::Lock::Timeout=300', '--no-remove'].freeze

  # services.<verb>: systemctl <verb> <unit>, for a service in SERVICES.
  def self.service_operation(verb)
    {
      params: %w[service],
      validate: ->(a) { { unit: service_unit(a['service']) } },
      plan: ->(v) { [['/usr/bin/systemctl', verb, v[:unit]]] }
    }
  end

  # services.enable and services.disable: for the next boot, then now. Two steps, not
  # `enable --now`: a service with only an init script (Greyhole's package ships just
  # /etc/init.d/greyhole) is enabled through systemd-sysv-install, and --now then starts nothing.
  def self.service_switch(verb, now)
    {
      params: %w[service],
      validate: ->(a) { { unit: service_unit(a['service']) } },
      plan: ->(v) { [['/usr/bin/systemctl', verb, v[:unit]], ['/usr/bin/systemctl', now, v[:unit]]] }
    }
  end


  add_operations(
    # Settings → Servers. enable/disable also start/stop the service now (--now).
    'services.start' => service_operation('start'),
    'services.stop' => service_operation('stop'),
    'services.restart' => service_operation('restart'),
    'services.enable' => service_switch('enable', 'start'),
    'services.disable' => service_switch('disable', 'stop'),
    'system.reboot' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [%w[/usr/bin/systemctl reboot]] }
    },
    'system.poweroff' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [%w[/usr/bin/systemctl poweroff]] }
    },
    # A swap file at /swapfile, on now and at boot. Only when there is none yet.
    # System Update: starts its job (bin/amahi-update, as amahi-kai-update.service), which
    # outlives the app's restart and writes /var/log/amahi-kai/update.log. Already running:
    # nothing changes.
    # With repair: true it runs every step even when there's nothing new (to fix an install).
    'system.update' => {
      params: %w[repair],
      validate: lambda do |a|
        raise Refused, "System Update's job isn't installed yet" unless File.exist?(UPDATE_UNIT)
        { repair: a.key?('repair') ? boolean(a, 'repair') : false }
      end,
      plan: lambda do |v|
        steps = []
        steps << [:install, UPDATE_REPAIR_FLAG, "repair\n", nil, '0600'] if v[:repair]
        steps << %w[/usr/bin/systemctl start amahi-kai-update.service]
      end
    },
    # Whether an update is waiting, for Amahi-kai and its apps: fetches the update channel's
    # newest version (update_target: a release tag, or the dev branch), the one System Update
    # would install, and writes what's new (the merged changes and the changelog entries added) to
    # UPDATE_STATUS (skipped while an update runs); then fetches the app catalog's repo, keeping
    # the manifests that pass every check (see CATALOG_REPO). It never installs anything.
    # amahi-kai-update-check.timer runs it every 6 hours; System Update's and the Apps page's
    # Check now too.
    # What System Update installs: the update channel's newest version, fetched into the checkout,
    # as { 'target' => { 'channel', 'commit', 'version', 'tag', 'error' } }; its commit is the one
    # running when there's nothing newer. bin/amahi-update calls it holding the update lock, so
    # it takes none itself.
    'system.update_target' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:update_target]] }
    },
    'system.check_update' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:check_update], [:refresh_catalog], [:check_security_updates]] }
    },
    # The channel System Update follows (Settings → System Status), then a check on it, so the page
    # shows what the new channel offers. Only that line of ENV_FILE changes.
    'system.set_update_channel' => {
      params: %w[channel],
      validate: ->(a) { { channel: listed(a['channel'], 'channel', UPDATE_CHANNELS) } },
      plan: ->(v) { [[:set_update_channel, v[:channel]], [:check_update]] }
    },
    'system.create_swap' => {
      params: %w[size_gb],
      validate: ->(a) { { size_gb: integer(a, 'size_gb', 1..8) } },
      plan: ->(v) { [[:create_swapfile, SWAPFILE, v[:size_gb]]] }
    },
    'packages.add_repository' => {
      params: %w[repository],
      validate: ->(a) { { repository: listed(a['repository'], 'repository', APT_REPOSITORIES.keys) } },
      plan: ->(v) { [[:add_apt_repository, v[:repository]]] }
    },
    # Refreshes apt's package lists (Settings → System Dependencies' Check now), with its
    # output streamed. Installs nothing.
    'packages.refresh' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [['/usr/bin/apt-get', 'update', { env: APT_ENV, stream: true }], [:check_security_updates]] }
    },
    # Updates installed packages that apt has an update for (Settings → System Dependencies),
    # nothing else: no new package, no removal; a held one is refused.
    'packages.upgrade' => {
      params: %w[packages],
      validate: ->(a) { upgrade_request(a['packages']) },
      plan: lambda { |v|
        [['/usr/bin/apt-get', '-y', *UPGRADE_OPTIONS, 'install', '--only-upgrade', *v[:packages], { env: UPGRADE_ENV, stream: true }],
         [:check_security_updates]]
      }
    },
    # Every update apt has, except held packages: new packages an update needs (a new
    # kernel) are installed, none removed.
    'packages.upgrade_all' => {
      params: [],
      validate: ->(_a) { {} },
      plan: lambda { |_v|
        [['/usr/bin/apt-get', '-y', *UPGRADE_OPTIONS, '--with-new-pkgs', 'upgrade', { env: UPGRADE_ENV, stream: true }],
         [:check_security_updates]]
      }
    },
    # Holds installed packages at their version (apt-mark hold), so no update changes them
    # until released, or releases them.
    'packages.hold' => {
      params: %w[packages held],
      validate: lambda { |a|
        packages = installed_packages!(a['packages'])
        { packages: packages, held: boolean(a, 'held') }
      },
      plan: ->(v) { [['/usr/bin/apt-mark', v[:held] ? 'hold' : 'unhold', *v[:packages]]] }
    },
    # Ubuntu's automatic updates (unattended-upgrades) on or off. apt keeps refreshing its
    # package lists daily either way: that's what shows the updates waiting.
    'updates.set_automatic' => {
      params: %w[enabled],
      validate: lambda { |a|
        enabled = boolean(a, 'enabled')
        raise Refused, 'unattended-upgrades is not installed' if enabled && !File.exist?('/usr/bin/unattended-upgrade')
        { enabled: enabled }
      },
      plan: ->(v) { [[:install, AUTO_UPGRADES, auto_upgrades_content(v[:enabled]), nil]] }
    },
    # Installs packages from PACKAGES, with apt's output streamed as it runs. recommends:
    # false leaves out the packages they only recommend (smartmontools' would bring a mail
    # server).
    'packages.install' => {
      params: %w[packages recommends],
      validate: lambda { |a|
        { packages: package_list(a['packages']), recommends: a.key?('recommends') ? boolean(a, 'recommends') : true }
      },
      plan: lambda { |v|
        [['/usr/bin/apt-get', 'update', { env: APT_ENV, stream: true }],
         ['/usr/bin/apt-get', '-y', *(v[:recommends] ? [] : ['--no-install-recommends']),
          '-o', 'Dpkg::Options::=--force-confold', '-o', 'DPkg::Lock::Timeout=300',
          'install', *v[:packages], { env: APT_ENV, stream: true }]]
      }
    },
    # What the security audit can't read without root: UFW's state and sshd's effective
    # settings (`sshd -T`, so drop-ins count).
    'security.report' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:security_report]] }
    },
    # SSH is let in on the ports sshd listens on too (sshd -T), so one moved off 22 isn't shut out.
    'security.enable_firewall' => {
      params: [],
      validate: ->(_a) { installed!(UFW) && { ssh_ports: ssh_ports } },
      plan: lambda { |v|
        ports = (FIREWALL_PORTS + v[:ssh_ports].map { |port| "#{port}/tcp" }).uniq
        [[UFW, 'default', 'deny', 'incoming'], *ports.map { |port| [UFW, 'allow', port] }, [UFW, '--force', 'enable']]
      }
    },
    # Turns off SSH root login (only while another account can log in over SSH), or password
    # login (only while an account that can log in has an SSH key), so nobody is locked out.
    'security.harden_ssh' => {
      params: %w[setting],
      validate: ->(a) { ssh_hardening(a['setting']) },
      plan: ->(v) { [[:harden_ssh, v[:settings]]] }
    },
  )

  class << self
    def service_unit(value)
      value = string(value, 'service', max: 32)
      SERVICES.fetch(value) { raise Refused, "service #{value.inspect} isn't one Amahi-kai manages" }
    end

    # Packages given by name, each installed now.
    def installed_packages!(value)
      raise Refused, 'packages must be a list of package names' unless value.is_a?(Array) && value.size.between?(1, 200)
      names = value.map { |name| string(name, 'package', max: 110) }
      bad = names.find { |name| !name.match?(PACKAGE_NAME) }
      raise Refused, "#{bad.inspect} isn't a package name" if bad
      installed = installed_package_names(names)
      missing = names.find { |name| !installed.include?(name) }
      raise Refused, "#{missing} isn't installed" if missing
      names.uniq
    end

    def upgrade_request(value)
      names = installed_packages!(value)
      waiting = upgradable_packages
      none = names.find { |name| !waiting.key?(name) }
      raise Refused, "#{none} has no update waiting" if none
      held = (names & held_packages).first
      raise Refused, "#{held} is held at its version; release it first" if held
      { packages: names }
    end

    def installed_package_names(names)
      out, _err, _status = Open3.capture3(ENV_MIN, '/usr/bin/dpkg-query', '-W', '-f=${Package}\t${db:Status-Abbrev}\n', *names,
                                          unsetenv_others: true, chdir: '/')
      out.lines.filter_map { |line| name, state = line.chomp.split("\t"); name if state.to_s.start_with?('ii') }
    rescue SystemCallError
      []
    end

    def held_packages
      capture(['/usr/bin/apt-mark', 'showhold']).lines(chomp: true).reject(&:empty?)
    rescue Failed
      []
    end

    # { name => { 'installed', 'available', 'security' } }: apt's updates for installed packages.
    def upgradable_packages
      out, _err, status = Open3.capture3(ENV_MIN, '/usr/bin/apt', 'list', '--upgradable', unsetenv_others: true, chdir: '/')
      return {} unless status.success?
      out.lines.each_with_object({}) do |line, found|
        match = line.match(%r{\A([^/\s]+)/(\S+)\s+(\S+)\s+\S+\s+\[upgradable from: ([^\]]+)\]})
        next unless match
        found[match[1]] = { 'installed' => match[4], 'available' => match[3],
                            'security' => match[2].split(',').any? { |pocket| pocket.end_with?('-security') } }
      end
    rescue SystemCallError
      {}
    end

    def auto_upgrades_content(enabled)
      "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"#{enabled ? 1 : 0}\";\n"
    end

    # What the Apps pages show besides: a name, a description and a category, each one line,
    # and a logo and release notes on https, or none.
    def check_listing(id, data)
      bad = ->(why) { raise Failed, "#{id}'s manifest: #{why}" }
      %w[name description category].each do |field|
        value = data[field]
        ok = value.is_a?(String) && !value.strip.empty? && value.length <= 300 && !value.match?(/[\r\n\0]/)
        bad.call("#{field} must be one line of text") unless ok
      end
      # How to sign in the first time, said under the installed app (the catalog's CI wants one for
      # every app; an Amahi-kai that doesn't know the field ignores it)
      sign_in = data['sign_in']
      unless sign_in.nil? || (sign_in.is_a?(String) && !sign_in.strip.empty? && sign_in.length <= 300 && !sign_in.match?(/[\r\n\0]/))
        bad.call('sign_in must be one line of text')
      end
      # Whether the app works with files in shares, so Install asks which to give it (writes_shares
      # says so too); an Amahi-kai that doesn't know the field asks every app, as it did
      bad.call('shares must be true or false') unless data['shares'].nil? || [true, false].include?(data['shares'])
      %w[logo releases].each do |field|
        value = data[field]
        bad.call("#{field} must be an https link") unless value.nil? || (value.is_a?(String) && value.match?(%r{\Ahttps://[^\s"'<>]{1,500}\z}))
      end
    end

    # nil when a catalog manifest passes every check, else why not. One that needs a newer
    # catalog format only has its listing checked: this Amahi-kai doesn't know its other fields.
    def catalog_entry_problem(id, content)
      return 'not an app id (lowercase letters and digits)' unless id.match?(APP_ID)
      return "over #{CATALOG_MAX_BYTES} bytes" if content.bytesize > CATALOG_MAX_BYTES
      data = YAML.safe_load(content)
      return 'not an app manifest' unless data.is_a?(Hash)
      check_listing(id, data)
      check_manifest(id, data) if manifest_requires(id, data) <= CATALOG_FORMAT
      nil
    rescue Failed => e
      e.message.delete_prefix("#{id}'s manifest: ")
    rescue Psych::Exception => e
      "can't be read: #{e.message.lines.first.to_s.strip}"
    end

    # --check-catalog DIR: every DIR/<id>.yml checked as the update check's catalog fetch would, and no host
    # port listed by two apps. Prints a line per app; 0 when they all pass.
    def check_catalog(dir, output)
      paths = Dir[File.join(dir, '*.yml')].sort
      return output.puts("no app manifests in #{dir}") || 1 if paths.empty?

      ports = Hash.new { |h, k| h[k] = [] }
      failed = false
      paths.each do |path|
        id = File.basename(path, '.yml')
        content = File.read(path)
        problem = catalog_entry_problem(id, content)
        output.puts(problem ? "#{id}: #{problem}" : "#{id}: ok")
        failed ||= !problem.nil?
        next if problem

        Array(YAML.safe_load(content)['ports']).each { |port| ports[[port['host'], port['protocol'] || 'tcp']] << id }
      end
      ports.each do |(host, protocol), ids|
        next if ids.size < 2

        output.puts("#{ids.join(' and ')}: both list host port #{host}/#{protocol}")
        failed = true
      end
      failed ? 1 : 0
    end

    def ssh_hardening(value)
      setting = listed(value, 'setting', SSH_HARDENING.keys)
      if setting == 'password_login' && ssh_key_holders.empty?
        raise Refused, 'no account that can log in has an SSH key (~/.ssh/authorized_keys); ' \
                       'turning off password login would lock everyone out of SSH'
      end
      if setting == 'root_login' && ssh_login_accounts.empty?
        raise Refused, 'no account but root can log in over SSH (with a key, or a password while SSH takes them); ' \
                       "turning off root's login would lock everyone out of SSH"
      end
      { settings: SSH_HARDENING.fetch(setting) }
    end

    # The ports sshd listens on, from its effective settings; none when it isn't there or can't say.
    def ssh_ports
      return [] unless File.executable?(SSHD)

      Dir.mkdir('/run/sshd', 0o755) unless File.directory?('/run/sshd')
      capture([SSHD, '-T']).lines.filter_map { |line| line[/\Aport (\d{1,5})\s*\z/, 1] }.uniq
    rescue Failed, SystemCallError
      []
    end

    # Accounts with a login shell (root aside) whose authorized_keys holds a key.
    def ssh_key_holders
      shells = login_shells
      holders = []
      Etc.passwd do |pw|
        next unless login_account?(pw, shells)
        keys = File.join(pw.dir, '.ssh', 'authorized_keys')
        next unless File.file?(keys)
        holders << pw.name if File.foreach(keys).any? { |line| line.match?(/\A[^#]*\b(?:ssh-|ecdsa-|sk-)\S+ \S/) }
      rescue SystemCallError
        next
      end
      holders
    end

    # Accounts besides root that can log in over SSH: those with a key, and, while SSH takes
    # passwords, those with a password that isn't locked.
    def ssh_login_accounts
      holders = ssh_key_holders
      ssh_passwords_on? ? holders | password_accounts : holders
    end

    # Whether sshd takes passwords; no when it can't say, so a doubt never counts toward a login.
    def ssh_passwords_on?
      Dir.mkdir('/run/sshd', 0o755) unless File.directory?('/run/sshd')
      capture([SSHD, '-T']).lines.any? { |line| line.strip == 'passwordauthentication yes' }
    rescue Failed, SystemCallError
      false
    end

    # Accounts with a login shell (root aside) and a password that isn't locked.
    def password_accounts
      shells = login_shells
      File.foreach('/etc/shadow').filter_map do |line|
        name, hash = line.split(':', 3)
        next if hash.to_s.empty? || hash.start_with?('!', '*')
        pw = begin
          Etc.getpwnam(name)
        rescue ArgumentError
          nil
        end
        name if pw && login_account?(pw, shells)
      end
    rescue SystemCallError
      []
    end

    def login_shells
      File.readlines('/etc/shells', chomp: true).reject { |s| s.empty? || s.start_with?('#') }
    end

    def login_account?(pw, shells)
      pw.uid >= UID_MIN && shells.include?(pw.shell) && !pw.shell.end_with?('nologin', 'false')
    end

    def package_list(value)
      raise Refused, 'packages must be a list' unless value.is_a?(Array) && !value.empty? && value.size <= 10
      value.map { |name| listed(name, 'package', PACKAGES) }.uniq
    end

    # Creates the swap file, turns it on and adds it to fstab. Refuses if the file exists
    # (it may be in use); removes it again if a step fails before swap is on.
    def do_create_swapfile(path, size_gb)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600).close
      begin
        begin
          run_command(['/usr/bin/fallocate', '-l', "#{size_gb}G", path])
        rescue Failed
          # Some filesystems can't fallocate a swap file; writing zeros always works.
          run_command(['/usr/bin/dd', 'if=/dev/zero', "of=#{path}", 'bs=1M', "count=#{size_gb * 1024}", 'status=none'])
        end
        run_command(['/usr/sbin/mkswap', path])
        run_command(['/usr/sbin/swapon', path])
      rescue Failed
        File.unlink(path)
        raise
      end
      add_swap_to_fstab(path)
      nil
    rescue Errno::EEXIST
      raise Refused, "#{path} already exists"
    end

    def add_swap_to_fstab(path)
      return if File.foreach(FSTAB).any? { |line| line.split.first == path }
      add_fstab_line("#{path} none swap sw 0 0")
    end

    def add_fstab_line(line)
      replace_fstab(*fstab_with(line))
    end

    # The security updates waiting, each with when it was first seen (kept from the last check
    # while it's still the same version), for the dashboard's notice.
    def do_check_security_updates(now = Time.now)
      previous = read_json(SECURITY_UPDATES)
      seen = previous.is_a?(Hash) && previous['updates'].is_a?(Hash) ? previous['updates'] : {}
      updates = upgradable_packages.select { |_name, update| update['security'] }.to_h do |name, update|
        before = seen[name]
        first = before.is_a?(Hash) && before['available'] == update['available'] ? before['first_seen'] : now.utc.iso8601
        [name, { 'available' => update['available'], 'first_seen' => first }]
      end
      do_install(SECURITY_UPDATES, "#{JSON.pretty_generate('checked_at' => now.utc.iso8601, 'updates' => updates)}\n", nil, '0640', APP_USER)
      nil
    end

    # Enables and starts +unit+, or disables and stops it and forgets its failure: two commands,
    # not enable --now, which only starts and stops native units (Greyhole's is an init script).
    def switch_unit(unit, on, allow_failure: false)
      opts = allow_failure ? [{ allow_failure: true }] : []
      run_command([SYSTEMCTL, on ? 'enable' : 'disable', unit, *opts])
      run_command([SYSTEMCTL, on ? 'start' : 'stop', unit, *opts])
      run_command([SYSTEMCTL, 'reset-failed', unit, { allow_failure: true }]) unless on
    end

    # What systemctl is-enabled or is-active says of +unit+ ('enabled', 'failed', ...): its last
    # line on stdout (for an init script it says where it's looking on stderr).
    def unit_state(question, unit)
      out, _err, _status = Open3.capture3(ENV_MIN, [SYSTEMCTL, SYSTEMCTL], question, unit, unsetenv_others: true, chdir: '/')
      out.lines.last.to_s.strip
    rescue SystemCallError
      ''
    end

    # --- The app catalog's repo (see CATALOG_REPO) ---

    def do_refresh_catalog
      status = with_lock(CATALOG_LOCK) { refresh_catalog }
      return { 'catalog' => read_json(CATALOG_STATUS), 'skipped' => 'the catalog is being fetched already' } unless status

      do_install(CATALOG_STATUS, "#{JSON.pretty_generate(status)}\n", nil, '0640', APP_USER)
      { 'catalog' => status }
    end

    # The new status: what was fetched and kept, or, when the fetch failed or nothing in it
    # passed, the last status with the error (the catalog there was stays).
    def refresh_catalog
      checked = Time.now.utc.iso8601
      error = fetch_catalog
      fetched = error ? nil : read_fetched_catalog
      error ||= fetched[:error]
      return (read_json(CATALOG_STATUS) || {}).merge('checked_at' => checked, 'error' => error) if error

      install_catalog(fetched[:files])
      { 'checked_at' => checked, 'commit' => fetched[:commit], 'apps' => fetched[:files].keys.sort,
        'problems' => fetched[:problems], 'error' => nil }
    end

    # nil when main was fetched (it's then FETCH_HEAD in CATALOG_SRC), else why not.
    def fetch_catalog
      unless File.file?(File.join(CATALOG_SRC, 'HEAD'))
        _out, err, status = catalog_git('init', '--quiet', '--bare', CATALOG_SRC, repo: false)
        return "couldn't set up #{CATALOG_SRC}: #{last_lines(err, 1)}" unless status.success?
      end
      _out, err, status = catalog_git('fetch', '--quiet', '--depth', '1', '--no-tags', CATALOG_REPO, 'main', timeout: 60)
      return nil if status.success?

      reason = err.lines.map(&:strip).find { |line| line.start_with?('fatal:') } || last_lines(err, 1)
      "couldn't fetch the catalog from GitHub: #{reason.delete_prefix('fatal: ')}"
    rescue SystemCallError => e
      "couldn't run git: #{e.message}"
    end

    # git with hooks off and only CATALOG_PROTOCOLS allowed, in CATALOG_SRC (unless +repo+ is
    # false). [stdout, stderr, status].
    def catalog_git(*args, repo: true, timeout: nil)
      argv = [GIT, '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-c', 'protocol.allow=never',
              *CATALOG_PROTOCOLS.flat_map { |name| ['-c', "protocol.#{name}.allow=always"] },
              *(repo ? ['-C', CATALOG_SRC] : []), *args]
      argv = ['/usr/bin/timeout', timeout.to_s, *argv] if timeout
      Open3.capture3(ENV_MIN.merge('GIT_TERMINAL_PROMPT' => '0'), [argv[0], argv[0]], *argv.drop(1),
                     unsetenv_others: true, chdir: '/')
    end

    # { commit:, files: { id => manifest }, problems: [{ 'app' =>, 'problem' => }] } for the
    # apps/ of what was fetched, or { error: } when none of them passes.
    def read_fetched_catalog
      out, _err, status = catalog_git('rev-parse', '--verify', '--quiet', 'FETCH_HEAD^{commit}')
      return { error: 'the fetched catalog has no commit' } unless status.success?

      commit = out.strip
      listing, _err, status = catalog_git('ls-tree', '-l', commit, 'apps/')
      return { error: "the fetched catalog can't be read" } unless status.success?

      files = {}
      problems = []
      listing.lines(chomp: true).first(CATALOG_MAX_APPS).each do |line|
        meta, path = line.split("\t", 2)
        _mode, type, object, size = meta.to_s.split
        next unless type == 'blob' && path.to_s.end_with?('.yml')

        id = File.basename(path, '.yml')
        problem = "over #{CATALOG_MAX_BYTES} bytes" if size.to_i > CATALOG_MAX_BYTES
        unless problem
          content, _err, status = catalog_git('cat-file', 'blob', object)
          content = content.dup.force_encoding('UTF-8')
          problem = status.success? && content.valid_encoding? ? catalog_entry_problem(id, content) : "can't be read"
        end
        problem ? problems << { 'app' => id, 'problem' => problem } : files[id] = content
      end
      return { error: 'no app in the fetched catalog passes the checks', problems: problems } if files.empty?

      { commit: commit, files: files, problems: problems }
    end

    # The checked manifests become APP_CATALOG/apps: written beside it, then swapped in.
    def install_catalog(files)
      fresh = "#{APP_CATALOG}.new"
      old = "#{APP_CATALOG}.old"
      FileUtils.rm_rf([fresh, old])
      FileUtils.mkdir_p(File.join(fresh, 'apps'), mode: 0o755)
      File.chmod(0o755, fresh)
      files.each do |id, content|
        File.open(File.join(fresh, 'apps', "#{id}.yml"), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o644) do |f|
          f.write(content)
        end
      end
      File.rename(APP_CATALOG, old) if File.exist?(APP_CATALOG)
      File.rename(fresh, APP_CATALOG)
      FileUtils.rm_rf(old)
    rescue SystemCallError => e
      raise Failed, "couldn't write the catalog to #{APP_CATALOG}: #{e.message}"
    end

    # --- Checking for updates ---

    def do_check_update
      status = with_update_lock { update_status }
      return { 'update' => read_update_status, 'skipped' => 'System Update is running' } unless status

      do_install(UPDATE_STATUS, "#{JSON.pretty_generate(status)}\n", nil, '0640', APP_USER)
      { 'update' => status }
    end

    # Runs the block holding the update lock, or returns nil if an update holds it.
    def with_update_lock(&block)
      with_lock(UPDATE_LOCK, &block)
    end

    def with_lock(path)
      File.open(path, File::RDWR | File::CREAT, 0o644) do |lock|
        return nil unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      end
    end

    # A target System Update can trust: a lookup that failed (GitHub unreachable, no release yet)
    # is an error, never "nothing new".
    def do_update_target
      target = update_target
      raise Failed, target['error'] if target['error']
      raise Failed, "couldn't read the running commit" unless target['commit']

      { 'target' => target }
    end

    def update_status
      target = update_target
      current = git_output('rev-parse', 'HEAD')
      latest = target['commit'] || current
      behind = current && latest && latest != current ? git_output('rev-list', '--count', "#{current}..#{latest}").to_i : 0
      { 'checked_at' => Time.now.utc.iso8601, 'channel' => target['channel'],
        'current' => current, 'current_version' => version_at(current),
        'latest' => latest, 'latest_version' => target['version'], 'tag' => target['tag'],
        'available' => behind.positive?, 'behind' => behind,
        'commits' => behind.positive? ? update_commits("#{current}..#{latest}") : [],
        'changelog' => behind.positive? ? update_changelog(current, latest) : [],
        'error' => target['error'] }
    end

    # The channel's newest version, fetched: { 'channel', 'commit', 'version', 'tag', 'error' }.
    # 'commit' is the running one when nothing is newer, and nil only when what runs is unknown.
    def update_target
      channel = update_channel
      current = git_output('rev-parse', 'HEAD')
      found = channel == 'development' ? development_target : release_target(channel == 'candidates', current)
      newer = found[:commit] && found[:commit] != current && found[:newer]
      { 'channel' => channel, 'commit' => newer ? found[:commit] : current,
        'version' => newer ? found[:version] : version_at(current), 'tag' => newer ? found[:tag] : nil,
        'error' => found[:error] }
    end

    # Writes AMAHI_UPDATE_CHANNEL into ENV_FILE (that line replaced, or added at the end), keeping
    # every other line and the file's mode and group. The file holds the app's secrets: nothing of
    # it is logged or returned.
    def do_set_update_channel(channel)
      stat = File.stat(ENV_FILE)
      lines = File.readlines(ENV_FILE)
      setting = "AMAHI_UPDATE_CHANNEL=#{channel}\n"
      if (index = lines.index { |l| l.start_with?('AMAHI_UPDATE_CHANNEL=') })
        lines[index] = setting
      else
        lines[-1] = "#{lines[-1]}\n" unless lines.empty? || lines[-1].end_with?("\n")
        lines << setting
      end
      group = stat.gid.zero? ? nil : Etc.getgrgid(stat.gid).name
      do_install(ENV_FILE, lines.join, nil, format('%o', stat.mode & 0o777), group)
      nil
    rescue SystemCallError, ArgumentError => e
      raise Failed, "couldn't change #{ENV_FILE}: #{e.message}"
    end

    def update_channel
      line = File.foreach(ENV_FILE).find { |l| l.start_with?('AMAHI_UPDATE_CHANNEL=') }
      value = line.to_s.split('=', 2)[1].to_s.strip.delete('"\'').downcase
      UPDATE_CHANNELS.include?(value) ? value : 'releases'
    rescue SystemCallError
      'releases'
    end

    # The dev branch's newest commit; newer unless it's already in what runs (just after a
    # release, main's merge commit holds it).
    def development_target
      error = git_fetch('origin', 'dev')
      latest = git_output('rev-parse', '--verify', '--quiet', 'origin/dev^{commit}')
      current = git_output('rev-parse', 'HEAD')
      { commit: latest, version: latest && version_at(latest), tag: nil, error: error,
        newer: latest && current && !git_ancestor?(latest, current) }
    end

    # The newest release published on GitHub (with pre-releases, for candidates), its tag fetched;
    # newer when its version is above the running one's (or, with no VERSION running, when it
    # isn't already in what runs).
    def release_target(prereleases, current)
      release, error = newest_release(prereleases)
      return { error: error || 'no release is published yet' } unless release

      tag = release[:tag]
      fetch_error = git_fetch('origin', "refs/tags/#{tag}:refs/tags/#{tag}")
      commit = git_output('rev-parse', '--verify', '--quiet', "refs/tags/#{tag}^{commit}")
      return { error: fetch_error || "couldn't fetch #{tag}" } unless commit
      return { error: "#{tag}'s VERSION file says #{version_at(commit).inspect}, not #{release[:version]}" } unless version_at(commit) == release[:version]

      running = version_at(current)
      newer = running ? (release_key(release[:version]) <=> release_key(running)).positive? : current && !git_ancestor?(commit, current)
      { commit: commit, version: release[:version], tag: tag, error: nil, newer: newer }
    end

    # [{ tag:, version: }, error]: the highest version among the releases GitHub lists (drafts never;
    # pre-releases when asked), or nil and why.
    def newest_release(prereleases)
      out, err, status = Open3.capture3(ENV_MIN, ['/usr/bin/timeout', '/usr/bin/timeout'], '30', '/usr/bin/curl', '-fsSL',
                                        '--proto', '=https', '--tlsv1.2', '--max-time', '25',
                                        '-H', 'Accept: application/vnd.github+json', RELEASES_URL,
                                        unsetenv_others: true, chdir: '/')
      return newest_tag(prereleases, "couldn't read the releases from GitHub: #{last_lines(err, 1)}") unless status.success?

      releases = JSON.parse(out)
      return [nil, "GitHub's releases list wasn't a list"] unless releases.is_a?(Array)

      picks = releases.filter_map do |r|
        next unless r.is_a?(Hash) && !r['draft'] && (prereleases || !r['prerelease'])
        tag = r['tag_name'].to_s
        { tag: tag, version: tag.delete_prefix('v') } if tag.match?(RELEASE_TAG)
      end
      [picks.max_by { |r| release_key(r[:version]) }, nil]
    rescue JSON::ParserError
      newest_tag(prereleases, "GitHub's releases list wasn't JSON")
    rescue SystemCallError => e
      newest_tag(prereleases, "couldn't run curl: #{e.message}")
    end

    # When GitHub's releases list doesn't answer (it allows 60 lookups an hour from one address,
    # which other homes behind a provider's shared address use too): the repository's tags. A
    # release is published from its tag, and release candidates are the ones with rc. [pick, nil],
    # or [nil, why the list didn't answer].
    def newest_tag(prereleases, why)
      out, _err, status = Open3.capture3(ENV_MIN.merge('GIT_TERMINAL_PROMPT' => '0'), ['/usr/bin/timeout', '/usr/bin/timeout'],
                                         '60', GIT, *GIT_OPTIONS, 'ls-remote', '--tags', '--refs', 'origin', 'v*',
                                         unsetenv_others: true, chdir: '/')
      return [nil, why] unless status.success?

      picks = out.lines(chomp: true).filter_map do |line|
        tag = line.split("\t", 2)[1].to_s.delete_prefix('refs/tags/')
        match = tag.match(RELEASE_TAG) or next
        { tag: tag, version: tag.delete_prefix('v') } if prereleases || match[4].nil?
      end
      best = picks.max_by { |r| release_key(r[:version]) }
      best ? [best, nil] : [nil, why]
    rescue SystemCallError
      [nil, why]
    end

    # Orders versions: 1.0.0rc1 < 1.0.0rc2 < 1.0.0 < 1.0.1.
    def release_key(version)
      major, minor, patch, rc = RELEASE_TAG.match("v#{version}")&.captures
      return [-1] unless major

      [major.to_i, minor.to_i, patch.to_i, rc ? 0 : 1, rc.to_i]
    end

    # The version a commit's VERSION file names, or nil (none, or not a version).
    def version_at(commit)
      return nil unless commit

      value = git_output('show', "#{commit}:VERSION").to_s.strip
      value.match?(RELEASE_VERSION) ? value : nil
    end

    # nil when the fetch worked, else why not. The comparison then uses what was fetched last.
    def git_fetch(*refs)
      _out, err, status = Open3.capture3(ENV_MIN.merge('GIT_TERMINAL_PROMPT' => '0'), ['/usr/bin/timeout', '/usr/bin/timeout'],
                                         '60', GIT, *GIT_OPTIONS, 'fetch', '--quiet', '--no-tags', *refs,
                                         unsetenv_others: true, chdir: '/')
      status.success? ? nil : "couldn't fetch from GitHub: #{last_lines(err, 1)}"
    rescue SystemCallError => e
      "couldn't run git: #{e.message}"
    end

    def git_ancestor?(commit, of)
      _out, _err, status = Open3.capture3(ENV_MIN, [GIT, GIT], *GIT_OPTIONS, 'merge-base', '--is-ancestor', commit, of,
                                          unsetenv_others: true, chdir: '/')
      status.success?
    rescue SystemCallError
      false
    end

    # The merged changes, newest first: [{ 'sha' => 'abc1234', 'subject' => 'Title (#37)' }].
    def update_commits(range)
      git_lines('log', '--first-parent', '--format=%h%x09%s', "-#{UPDATE_LIST_LIMIT}", range).map do |line|
        sha, subject = line.split("\t", 2)
        { 'sha' => sha, 'subject' => subject.to_s[0, 300] }
      end
    end

    # The changelog entries (bullet lines, without the bullet) added between the two commits.
    def update_changelog(current, latest)
      git_lines('diff', '--no-color', '--unified=0', current, latest, '--', 'CHANGELOG.md')
        .filter_map { |line| line.delete_prefix('+- ')[0, 2000] if line.start_with?('+- ') }
        .first(UPDATE_LIST_LIMIT)
    end

    def read_update_status
      JSON.parse(File.read(UPDATE_STATUS))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # git's output in the app's checkout, or nil if git failed.
    def git_output(*args)
      out, _err, status = Open3.capture3(ENV_MIN, [GIT, GIT], *GIT_OPTIONS, *args, unsetenv_others: true, chdir: '/')
      status.success? ? out.dup.force_encoding('UTF-8').scrub('?').strip : nil
    rescue SystemCallError
      nil
    end

    def git_lines(*args)
      git_output(*args).to_s.lines(chomp: true)
    end

    def do_add_apt_repository(name)
      repo = APT_REPOSITORIES.fetch(name)
      raise Failed, "#{name}'s signing key fingerprint isn't pinned in the helper yet" if repo[:fingerprints].empty?
      vars = repository_vars
      Dir.mktmpdir('amahi-apt-', RUN_DIR) do |dir|
        key = File.join(dir, 'key')
        run_command(['/usr/bin/curl', '-fsSL', '--proto', '=https', '--tlsv1.2', '--max-time', '60', '-o', key,
                     format(repo[:key_url], **vars)])
        listed = capture(['/usr/bin/gpg', '--homedir', dir, '--batch', '--show-keys', '--with-colons', key])
        found = listed.lines.grep(/\Afpr:/).map { |line| line.split(':')[9] }
        unless found.sort == repo[:fingerprints].sort
          raise Failed, "#{name}'s signing key has fingerprints #{found.join(', ')}, not the pinned ones"
        end
        do_install(repo[:keyring], keyring_data(dir, key, repo[:keyring]), nil)
      end
      do_install(repo[:list], "#{format(repo[:source], **vars)}\n", nil)
    end

    # The checked key as the keyring's name says: binary for .gpg, armored for .asc.
    def keyring_data(dir, key, keyring)
      armored = File.binread(key, 10) == '-----BEGIN'
      return File.binread(key) if armored == keyring.end_with?('.asc')
      raise Failed, "#{File.basename(keyring)} must be an armored key" unless armored
      binary = File.join(dir, 'key.gpg')
      run_command(['/usr/bin/gpg', '--homedir', dir, '--batch', '--yes', '--output', binary, '--dearmor', key])
      File.binread(binary)
    end

    # The Ubuntu codename and dpkg architecture apt sources are written for.
    def repository_vars
      codename = File.read(OS_RELEASE)[/^VERSION_CODENAME="?([a-z]{2,20})"?$/, 1]
      raise Failed, "couldn't read the release codename from #{OS_RELEASE}" unless codename
      arch = capture(['/usr/bin/dpkg', '--print-architecture']).strip
      raise Failed, "unexpected architecture #{arch.inspect}" unless arch.match?(/\A[a-z0-9]{2,16}\z/)
      { codename: codename, arch: arch }
    end

    def do_security_report
      firewall = if File.executable?(UFW)
                   capture([UFW, 'status'])[/^Status: (\w+)/, 1] || 'unknown'
                 else
                   'not installed'
                 end
      { 'firewall' => firewall, 'ssh' => File.executable?(SSHD) ? sshd_settings : {} }
    end

    # sshd's effective settings for SSH_REPORTED. sshd needs its privilege separation
    # folder, which Ubuntu's socket-activated ssh only creates on the first connection.
    def sshd_settings
      Dir.mkdir('/run/sshd', 0o755) unless File.directory?('/run/sshd')
      capture([SSHD, '-T']).lines.to_h { |line| line.split(' ', 2).map(&:strip) }.slice(*SSH_REPORTED)
    end

    # Writes the settings into Amahi-kai's sshd drop-in (keeping ones set earlier), checks
    # the whole config with `sshd -t` (putting the old drop-in back if it fails), and
    # reloads ssh. Replies with the effective settings.
    def do_harden_ssh(settings)
      old = File.exist?(SSHD_DROPIN) ? File.read(SSHD_DROPIN) : nil
      kept = old.to_s.lines.filter_map { |line| line.strip.split(' ', 2) if line.match?(/\A[A-Za-z]+ (?:yes|no)\s*\z/) }.to_h
      lines = kept.merge(settings).map { |key, value| "#{key} #{value}" }
      do_install(SSHD_DROPIN, "# Written by Amahi-kai's security audit (Network → Security).\n#{lines.join("\n")}\n", nil)
      begin
        Dir.mkdir('/run/sshd', 0o755) unless File.directory?('/run/sshd')
        capture([SSHD, '-t'])
      rescue Failed
        old ? do_install(SSHD_DROPIN, old, nil) : File.unlink(SSHD_DROPIN)
        raise
      end
      run_command(['/usr/bin/systemctl', 'try-reload-or-restart', 'ssh.service'])
      { 'ssh' => sshd_settings }
    end

    # A step as shown by --dry-run and in errors: secrets and file contents left out.
    def describe(step)
      step = step.dup.tap { |s| s[2] = "[#{s[2].bytesize} bytes]" } if step.first == :install
      step.map do |part|
        case part
        when Hash then part.key?(:stdin) ? { 'stdin' => '[withheld]' }.merge(part.except(:stdin).transform_keys(&:to_s)) : part.transform_keys(&:to_s)
        when Symbol then part.to_s
        when String then part.length > 200 ? "[#{part.bytesize} bytes]" : part
        else part
        end
      end
    end
  end
end
