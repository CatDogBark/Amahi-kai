require 'json'
require 'open3'
require 'privileged'

# ZFS pools (docs/plans/storage.md): bitShare's storage, on drives of their own, next to the
# share storage (simple drives and Greyhole) that SMB shares live on. The root helper installs
# ZFS's settings, reads the pools and creates them (zfs.setup, pools.status, pools.create) and
# checks every drive itself; this lists the pools, says what each drive is used for, installs
# and uninstalls ZFS, and takes pools offline and back (pools.export, pools.import).
module StoragePools
  PACKAGE = 'zfsutils-linux'.freeze
  SMART_PACKAGE = 'smartmontools'.freeze
  ZPOOL = '/usr/sbin/zpool'.freeze
  SMARTCTL = '/usr/sbin/smartctl'.freeze
  # Ubuntu's ZFS package scrubs every healthy pool from here, on the second Sunday of each
  # month at 00:24.
  SCRUB_CRON = '/etc/cron.d/zfsutils-linux'.freeze
  LSBLK_COLUMNS = 'NAME,PATH,TYPE,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS,ROTA'.freeze

  class Error < StandardError; end

  # The layouts a new pool may have (the helper's POOL_LAYOUTS). parity: drives that may
  # fail in a RAIDZ group; pairs: striped mirrors take drives two by two.
  LAYOUTS = [
    { key: 'mirror', name: 'Mirror', like: 'RAID 1', min: 2 },
    { key: 'striped_mirrors', name: 'Striped mirrors', like: 'RAID 10', min: 4, pairs: true },
    { key: 'raidz1', name: 'RAIDZ1', like: 'RAID 5', min: 3, parity: 1 },
    { key: 'raidz2', name: 'RAIDZ2', like: 'RAID 6', min: 4, parity: 2 },
    { key: 'raidz3', name: 'RAIDZ3', like: nil, min: 5, parity: 3 }
  ].freeze

  # One pool, as pools.status reports it.
  Pool = Struct.new(:name, :health, :used, :available, :mountpoint, :state, :status, :action, :scan,
                    :errors, :vdevs, :error, :snapshots, :snapshot_policy, :snapshot_space, keyword_init: true) do
    def healthy?
      health == 'ONLINE'
    end

    # "RAIDZ1", "Mirror", "Striped mirrors" (2 mirrors), or "Stripe" (drives on their own).
    def layout
      groups = vdevs.map { |v| v['name'].to_s[/\A(raidz\d|mirror|draid\d?)-\d+\z/, 1] }
      return 'Stripe' if groups.empty? || groups.include?(nil)
      return 'Striped mirrors' if groups.uniq == ['mirror'] && groups.size > 1
      return 'Mirror' if groups.uniq == ['mirror']
      groups.uniq.map(&:upcase).join(' + ')
    end

    # The pool's drives: [{ 'name' =>, 'device' =>, 'state' =>, 'read' =>, ... }].
    def drives
      leaves(vdevs)
    end

    # The kind and size of the pool's groups when they all match (['raidz1', 4]), else nil.
    # Adding drives takes one more group of that shape.
    def group_shape
      shapes = vdevs.map { |v| [v['name'].to_s[/\A(mirror|raidz[123])-\d+\z/, 1], Array(v['children']).size] }.uniq
      shapes.size == 1 && shapes.first.first ? shapes.first : nil
    end

    # The pool's snapshots, oldest first: { 'name', 'kind' (hourly, daily, manual, or nil for
    # ones Amahi-kai didn't take), 'created' (Time), 'used' (bytes) }.
    def snapshot_list
      Array(snapshots).map { |snap| snap.merge('created' => Time.at(snap['created'].to_i)) }
    end

    # How many hourly and daily snapshots the pool keeps.
    def keeps
      { 'hourly' => 24, 'daily' => 30 }.merge(snapshot_policy.to_h)
    end

    # A scrub or resilver is running ("scrub in progress since ...").
    def scanning?
      scan.to_s.match?(/\A(?:scrub|resilver) in progress/)
    end

    # Errors worth showing ("No known data errors" isn't).
    def data_errors
      errors unless errors.nil? || errors.start_with?('No known data errors')
    end

    private

    def leaves(rows)
      rows.flat_map { |row| row['children'].blank? ? [row] : leaves(row['children']) }
    end
  end

  # A pool taken offline here (pools.export): its drives stay its own until it's brought back.
  # state: ZFS's word for it as its drives are found (ONLINE when they all are), or MISSING
  # when none is connected; devices: the partitions of it found.
  OfflinePool = Struct.new(:name, :state, :devices, keyword_init: true) do
    def found?
      state != 'MISSING'
    end
  end

  class << self
    # { installed: true/false, pools: [Pool], offline: [OfflinePool], error: nil or why the
    # pools couldn't be read }.
    def status
      reply = Privileged.call('pools.status')
      offline = Array(reply['offline']).map do |pool|
        OfflinePool.new(name: pool['name'].to_s, state: pool['state'].to_s, devices: Array(pool['devices']))
      end
      { installed: reply['zfs'] == true, pools: Array(reply['pools']).map { |pool| pool(pool) }, offline: offline,
        error: reply['error'] }
    rescue Privileged::Error => e
      { installed: false, pools: [], offline: [], error: e.message }
    end

    # A Pool from one entry of the helper's 'pools' list.
    def pool(data)
      fields = data.slice(*(Pool.members.map(&:to_s) - ['vdevs'])).transform_keys(&:to_sym)
      Pool.new(**fields, vdevs: Array(data['vdevs']))
    end

    def zfs_installed?
      File.executable?(ZPOOL)
    end

    def smart_installed?
      File.executable?(SMARTCTL)
    end

    # When Ubuntu's schedule scrubs next (the second Sunday of the month, at 00:24), or nil
    # if its cron file isn't there.
    # (Cron runs in the server's own time zone, so this does too.)
    def next_scrub(now = Time.now)
      return nil unless File.exist?(SCRUB_CRON)
      [now.to_date.beginning_of_month, now.to_date.next_month.beginning_of_month].each do |month|
        sunday = (month + 7..month + 13).find(&:sunday?)
        at = Time.local(sunday.year, sunday.month, sunday.day, 0, 24)
        return at if at > now
      end
    end

    def scrub!(name)
      privileged('pools.scrub', name: name.to_s)
    end

    # Runs the health check now (it also runs every 15 minutes).
    def check_health!
      privileged('storage.check_health')
    end

    # Every whole disk, with what it's used for (:role) and whether a new pool may take it
    # (:free). Roles: :os (the system runs from it), :share (mounted as share storage),
    # :in_use (mounted elsewhere, or LVM, RAID or encryption on it), :pool (in an imported
    # pool), :offline (in a pool taken offline here), :old_zfs (a ZFS label from a pool that
    # isn't on this server; a new pool erases it), :free.
    def drives(pools = [], offline = [])
      lsblk.select { |d| d['type'] == 'disk' }.map do |disk|
        nodes = subtree(disk)
        mounts = nodes.flat_map { |n| Array(n['mountpoints']).compact }
        label = nodes.find { |n| n['fstype'] == 'zfs_member' }&.dig('label')
        pool = pools.find { |p| p.drives.any? { |d| nodes.any? { |n| n['path'] == d['device'] } } }&.name
        pool ||= (away = offline.find { |p| p.devices.any? { |d| nodes.any? { |n| n['path'] == d } } || p.name == label })&.name
        role = if mounts.any? { |m| !m.start_with?('/mnt/') } then :os
               elsif mounts.any? then :share
               elsif nodes.any? { |n| !%w[disk part].include?(n['type']) } then :in_use
               elsif away then :offline
               elsif pool then :pool
               elsif label then :old_zfs
               else :free
               end
        { path: disk['path'], model: disk['model'].to_s.strip.presence, serial: disk['serial'], size: disk['size'].to_i,
          ssd: [false, '0', 0].include?(disk['rota']), role: role, pool: pool || label, mounts: mounts,
          free: %i[free old_zfs].include?(role) }
      end
    end

    # Installs what's missing of ZFS (then loads it and caps its memory cache) and the drive
    # health tools, passing apt's output to +progress+ line by line, then checks the drives.
    def install!(&progress)
      progress ||= ->(_line) {}
      unless zfs_installed?
        progress.call('Installing ZFS (zfsutils-linux)...')
        privileged('packages.install', packages: [PACKAGE]) { |line| progress.call("  #{line}") }
        progress.call('Loading ZFS and limiting its memory cache...')
        reply = privileged('zfs.setup')
        cache = reply['arc_max'] && ActiveSupport::NumberHelper.number_to_human_size(reply['arc_max'])
        progress.call(cache ? "  ✓ ZFS's cache is limited to #{cache}" : '  ✓ ZFS is loaded')
      end
      unless smart_installed?
        progress.call('Installing the drive health tools (smartmontools)...')
        privileged('packages.install', packages: [SMART_PACKAGE], recommends: false) { |line| progress.call("  #{line}") }
      end
      progress.call('Checking the drives...')
      check_health!
    end

    # Why ZFS can't be uninstalled now, or nil when it can: no pool may be left, online or
    # offline.
    def removal_blocker(status)
      if (pool = Array(status[:pools]).first)
        "Delete the pool #{pool.name} first."
      elsif (pool = Array(status[:offline]).first)
        "The pool #{pool.name} is offline: bring it online and delete it first."
      end
    end

    # Removes ZFS when there's no pool, passing apt's output to +progress+ line by line. The
    # drive health tools stay.
    def uninstall!(&progress)
      progress ||= ->(_line) {}
      progress.call('Removing ZFS (zfsutils-linux)...')
      privileged('zfs.uninstall') { |line| progress.call("  #{line}") }
      progress.call('Checking the drives...')
      check_health!
    end

    # Takes a pool offline: unmounted, and staying offline after a restart, with its drives
    # kept for it.
    def take_offline!(name)
      no_shares_on!(name)
      changed { privileged('pools.export', name: name.to_s) }
    end

    # Brings back a pool taken offline here.
    def bring_online!(name)
      changed { privileged('pools.import', name: name.to_s) }
    end

    # Creates a pool. The helper checks the name, the layout and every drive, and wipes them.
    def create!(name:, layout:, devices:)
      raise Error, 'Choose a layout' unless LAYOUTS.any? { |l| l[:key] == layout }
      raise Error, 'Choose the drives for the pool' if devices.blank?
      changed { privileged('pools.create', name: name.to_s.strip, layout: layout, devices: devices.map(&:to_s)) }
    end

    # Brings back a pool's drive ZFS took out (+drive+: its name in the pool's status) once its
    # disk is connected again; ZFS resilvers it.
    def online_drive!(name:, drive:)
      changed { privileged('pools.online_drive', name: name.to_s, drive: drive.to_s) }
    end

    # Replaces a pool's drive (+old+: its name in the pool's status) with a free disk.
    def replace!(name:, old:, new:)
      raise Error, 'Choose the new drive' if new.blank?
      changed { privileged('pools.replace', name: name.to_s, old: old.to_s, new: new.to_s) }
    end

    # Grows a pool by one group shaped like its others.
    def add_group!(name:, devices:)
      raise Error, 'Choose the drives to add' if devices.blank?
      changed { privileged('pools.add_group', name: name.to_s, devices: devices.map(&:to_s)) }
    end

    def snapshot!(name)
      changed { privileged('pools.snapshot', name: name.to_s) }
    end

    # How many hourly and daily snapshots a pool keeps (0 turns a kind off).
    def set_snapshot_policy!(name:, hourly:, daily:)
      counts = { hourly: hourly, daily: daily }.transform_values do |value|
        Integer(value.to_s, 10)
      rescue ArgumentError
        raise Error, 'Keep a whole number of snapshots'
      end
      changed { privileged('pools.snapshot_policy', name: name.to_s, **counts) }
    end

    def destroy_snapshot!(name:, snapshot:)
      changed { privileged('pools.destroy_snapshot', name: name.to_s, snapshot: snapshot.to_s) }
    end

    # Rolls a pool back to a snapshot; +confirm+ must be its name.
    def rollback!(name:, snapshot:, confirm:)
      changed { privileged('pools.rollback', name: name.to_s, snapshot: snapshot.to_s, confirm: confirm.to_s) }
    end

    # Destroys a pool; +confirm+ must be its name.
    def destroy!(name:, confirm:)
      no_shares_on!(name)
      changed { privileged('pools.destroy', name: name.to_s, confirm: confirm.to_s) }
    end

    # The SMB shares on a pool (Share#zfs_pool): it isn't taken offline or destroyed under them.
    # The root helper refuses too.
    def no_shares_on!(name)
      on = Share.where(zfs_pool: name.to_s).order(:name).pluck(:name)
      return if on.empty?

      raise Error, "#{on.to_sentence} #{on.size == 1 ? 'is' : 'are'} on this pool: delete #{on.size == 1 ? 'that share' : 'those shares'} on Shares first."
    end

    private

    # Runs a change to the pools, then the health check, so the alerts match it at once. A
    # check that fails is left to the timer.
    def changed
      reply = yield
      begin
        check_health!
      rescue Error => e
        Rails.logger.warn("StoragePools: the health check after a change failed: #{e.message}")
      end
      reply
    end

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      raise Error, e.message
    end

    # lsblk's whole tree, sizes in bytes; runs as the app (no root needed). NAME comes first
    # because lsblk only nests partitions and volumes under their disk then (see the helper's
    # block_tree): a flat list would make every disk look free, so it counts as no answer.
    # [] if lsblk fails.
    def lsblk
      out, _err, status = Open3.capture3('lsblk', '-J', '-b', '-o', LSBLK_COLUMNS)
      tree = status.success? ? JSON.parse(out)['blockdevices'] || [] : []
      flat = tree.any? { |node| node['type'] == 'part' || node['type'] == 'lvm' || node['type'].to_s.start_with?('raid', 'crypt') }
      flat ? [] : tree
    rescue SystemCallError, JSON::ParserError
      []
    end

    def subtree(node)
      [node, *Array(node['children']).flat_map { |child| subtree(child) }]
    end
  end
end
