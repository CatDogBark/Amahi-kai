# SystemServices — the NAS's system services, read live from systemd and dpkg.
#
# One catalog for the dashboard, Settings → System Status and Settings → Servers.
# Reading needs no root: `systemctl show` and `dpkg-query` work as any user.
# Commands run as argument lists, never through a shell. Start, stop and restart go
# through the root helper (services.* operations), which has the same list of services.

require 'open3'

class SystemServices
  # key       — id used in URLs
  # unit      — systemd unit (without .service)
  # package   — Debian package(s) whose version is shown; the first installed one wins
  # check     — optional services are listed only when this binary exists
  # process   — for daemons systemd can't track (Greyhole's LSB script forks),
  #             find the process with `pgrep -f` instead
  # actions   — what Settings → Servers may do; the helper's SERVICES list
  #             (libexec/amahi-helper) must name the same services
  # note      — shown instead of buttons for services managed elsewhere
  # idle      — when the service isn't running for this reason, it's "Idle" rather than stopped
  CATALOG = [
    { key: 'amahi-kai', name: 'Amahi-kai', unit: 'amahi-kai',
      note: 'Restarted by System Update' },
    { key: 'smbd', name: 'Samba', unit: 'smbd', package: 'samba',
      actions: %w[start stop restart] },
    { key: 'nmbd', name: 'Samba (nmbd)', unit: 'nmbd', package: 'samba',
      actions: %w[start stop restart] },
    { key: 'mariadb', name: 'MariaDB', unit: 'mariadb', package: 'mariadb-server',
      note: 'Amahi-kai needs it running' },
    { key: 'dnsmasq', name: 'dnsmasq', unit: 'dnsmasq', package: 'dnsmasq', check: '/usr/sbin/dnsmasq',
      actions: %w[start stop restart] },
    { key: 'greyhole', name: 'Greyhole', unit: 'greyhole', package: 'greyhole', check: '/usr/bin/greyhole',
      process: 'greyhole --daemon', actions: %w[start stop restart] },
    { key: 'docker', name: 'Docker', unit: 'docker', package: %w[docker-ce docker.io], check: '/usr/bin/docker',
      actions: %w[start stop restart] },
    { key: 'cloudflared', name: 'Cloudflare Tunnel', unit: 'cloudflared', package: 'cloudflared',
      check: '/usr/bin/cloudflared', note: 'Managed on Remote Access' },
    { key: 'tailscaled', name: 'Tailscale VPN', unit: 'tailscaled', package: 'tailscale',
      check: '/usr/bin/tailscale', note: 'Managed on Remote Access' },
    { key: 'zfs-zed', name: 'ZFS event daemon', unit: 'zfs-zed', package: 'zfs-zed', check: '/usr/sbin/zed',
      note: 'Comes with ZFS (Disks → ZFS Pools)' },
    { key: 'smartd', name: 'SMART monitoring', unit: 'smartmontools', package: 'smartmontools', check: '/usr/sbin/smartd',
      note: 'Comes with smartmontools (Disks → ZFS Pools)', idle: :no_smart_drives },
    { key: 'fail2ban', name: 'Fail2ban', unit: 'fail2ban', package: 'fail2ban', check: '/usr/bin/fail2ban-server',
      note: 'Set up by the security audit' },
    { key: 'qemu-guest-agent', name: 'VM guest agent', unit: 'qemu-guest-agent', package: 'qemu-guest-agent',
      check: '/usr/sbin/qemu-ga', note: 'Lets Proxmox see and shut down the VM' }
  ].freeze

  # The helper operation for each action.
  ACTION_OPERATIONS = {
    'start' => 'services.start', 'stop' => 'services.stop', 'restart' => 'services.restart'
  }.freeze

  # smartd exits when no drive has SMART to watch (virtual disks have none), and systemd then
  # counts it as failed; it starts with the server once a real drive is connected.
  IDLE_REASONS = {
    no_smart_drives: 'Nothing to watch: no drive here has SMART (virtual disks have none). ' \
                     'It starts with the server once a drive with SMART is connected.'
  }.freeze

  PROPERTIES = %w[Description LoadState ActiveState SubState ActiveEnterTimestamp
                  MainPID MemoryCurrent UnitFileState].freeze

  class Service
    attr_reader :key, :name, :unit, :description, :state, :sub_state, :since,
                :pid, :memory, :boot, :version, :version_detail, :actions, :note, :idle_reason

    def initialize(entry, props, version: nil, version_detail: nil)
      @key = entry[:key]
      @name = entry[:name]
      @unit = entry[:unit]
      @actions = entry[:actions] || []
      @note = entry[:note]
      @loaded = props['LoadState'] != 'not-found'
      # systemd's fallback description is just the unit file name
      @description = props['Description'].presence unless props['Description'] == "#{@unit}.service"
      @state = props['ActiveState'].presence || 'unknown'
      @sub_state = props['SubState'].presence
      @since = SystemServices.parse_timestamp(props['ActiveEnterTimestamp'])
      @pid = props['MainPID'].to_i.positive? ? props['MainPID'].to_i : nil
      @memory = props['MemoryCurrent'].to_s.match?(/\A\d+\z/) ? props['MemoryCurrent'].to_i : nil
      @boot = props['UnitFileState'].presence
      @version = version
      @version_detail = version_detail
    end

    def running?
      state == 'active'
    end

    # Not running, but because there's nothing for it to do (IDLE_REASONS).
    def idle?
      !idle_reason.nil?
    end

    def idle!(reason)
      @idle_reason = reason
    end

    def installed?
      @loaded
    end

    def failed?
      state == 'failed'
    end

    # Seconds since the service last started, or nil when it isn't running.
    def uptime
      return nil unless running? && since
      [(Time.now - since).to_i, 0].max
    end

    def starts_at_boot?
      %w[enabled enabled-runtime alias].include?(boot)
    end

    # Starts, stops or restarts the service through the root helper. Returns true on
    # success; a failure is logged with the helper's reason.
    def perform(verb)
      raise ArgumentError, "#{name} can't #{verb}" unless actions.include?(verb)
      Privileged.call(ACTION_OPERATIONS.fetch(verb), service: key)
      true
    rescue Privileged::Error => e
      Rails.logger.error("SystemServices: #{name} #{verb} failed: #{e.message}")
      false
    end

    # Status for a process systemd can't track (see CATALOG :process).
    def apply_process(pid, elapsed, rss_kb)
      @state = pid ? 'active' : 'inactive'
      @sub_state = pid ? 'running' : 'dead'
      @pid = pid
      @since = pid && elapsed ? Time.now - elapsed : nil
      @memory = rss_kb ? rss_kb * 1024 : nil
    end
  end

  class << self
    # Every installed service. +versions+ also looks up package versions
    # (one dpkg-query call), which only Settings → Servers shows.
    def all(versions: false)
      entries = CATALOG.select { |e| e[:check].nil? || File.exist?(e[:check]) }
      props = unit_properties(entries.map { |e| e[:unit] })
      packages = versions ? package_versions(entries.flat_map { |e| Array(e[:package]) }.uniq) : {}

      entries.each_with_index.map do |entry, i|
        version, detail = versions ? version_for(entry, packages) : nil
        service = Service.new(entry, props[i] || {}, version: version, version_detail: detail)
        apply_process_status(service, entry[:process]) if entry[:process]
        service.idle!(IDLE_REASONS.fetch(entry[:idle])) if entry[:idle] && !service.running? && idle?(entry[:idle])
        service
      end
    end

    def idle?(reason)
      case reason
      when :no_smart_drives
        health = StorageHealth.load
        health.checked? && health.drives.empty? # the last check found no drive with SMART data
      end
    end

    def find(key, versions: false)
      all(versions: versions).find { |s| s.key == key.to_s }
    end

    # systemctl prints timestamps as "@<epoch>" with --timestamp=unix.
    def parse_timestamp(value)
      value.to_s =~ /\A@(\d+)\z/ ? Time.at(Regexp.last_match(1).to_i) : nil
    end

    # "2:4.19.5+dfsg-4ubuntu9.7" → "4.19.5": drop the epoch and the Debian revision.
    def upstream_version(package_version)
      package_version.to_s.sub(/\A\d+:/, '').sub(/[-+~].*\z/, '')
    end

    private

    # One `systemctl show` for all units; it prints one block per unit, in order.
    def unit_properties(units)
      return [] if units.empty?
      stdout, _stderr, _status = Open3.capture3(
        'systemctl', 'show', '--timestamp=unix', "--property=#{PROPERTIES.join(',')}",
        *units.map { |u| "#{u}.service" }
      )
      stdout.split(/\n\n/).map do |block|
        block.lines.each_with_object({}) do |line, h|
          k, v = line.chomp.split('=', 2)
          h[k] = v if k
        end
      end
    rescue SystemCallError
      []
    end

    # { "samba" => "2:4.19.5+dfsg-4ubuntu9.7", ... } for installed packages only.
    def package_versions(packages)
      return {} if packages.empty?
      # Exits non-zero when some packages aren't installed; the rest still print.
      stdout, _stderr, _status = Open3.capture3(
        'dpkg-query', '-W', '-f=${Package}\t${Version}\t${db:Status-Abbrev}\n', *packages
      )
      stdout.lines.each_with_object({}) do |line, h|
        name, version, status = line.chomp.split("\t")
        h[name] = version if status.to_s.start_with?('ii')
      end
    rescue SystemCallError
      {}
    end

    def version_for(entry, packages)
      return app_version if entry[:key] == 'amahi-kai'
      full = Array(entry[:package]).filter_map { |p| packages[p] }.first
      full ? [upstream_version(full), full] : nil
    end

    # Amahi-kai isn't a package: show the deployed commit, read from .git
    # directly so it works whoever owns the checkout.
    def app_version
      [app_commit, "Rails #{Rails::VERSION::STRING}, Ruby #{RUBY_VERSION}"]
    end

    public

    # The deployed commit (7 characters), read from .git directly so it works whoever owns
    # the checkout; nil if there's no checkout. Settings → Servers and System Status show it.
    def app_commit
      git = Rails.root.join('.git')
      head = File.read(git.join('HEAD')).strip
      sha = head.start_with?('ref: ') ? ref_sha(git, head.delete_prefix('ref: ')) : head
      sha&.slice(0, 7)
    rescue SystemCallError
      nil
    end

    private

    # A branch's commit: its loose ref file, or its line in packed-refs.
    def ref_sha(git, ref)
      loose = git.join(ref)
      return File.read(loose).strip if File.exist?(loose)
      File.foreach(git.join('packed-refs')).map(&:split).find { |_, r| r == ref }&.first
    end

    def apply_process_status(service, pattern)
      stdout, _stderr, status = Open3.capture3('pgrep', '-o', '-f', pattern)
      pid = status.success? ? stdout.to_i : 0
      return service.apply_process(nil, nil, nil) unless pid.positive?

      ps, _stderr, _status = Open3.capture3('ps', '-o', 'etimes=,rss=', '-p', pid.to_s)
      elapsed, rss = ps.split.map(&:to_i)
      service.apply_process(pid, elapsed, rss)
    rescue SystemCallError
      service.apply_process(nil, nil, nil)
    end
  end
end
