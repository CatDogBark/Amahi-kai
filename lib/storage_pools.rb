require 'json'
require 'open3'
require 'privileged'

# ZFS pools (docs/plans/storage.md): bitShare's storage, on drives of their own, next to the
# share storage (simple drives and Greyhole) that SMB shares live on. The root helper installs
# ZFS's settings, reads the pools and creates them (zfs.setup, pools.status, pools.create) and
# checks every drive itself; this lists the pools, says what each drive is used for, and
# installs ZFS.
module StoragePools
  PACKAGE = 'zfsutils-linux'.freeze

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
                    :errors, :vdevs, :error, keyword_init: true) do
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

    # Errors worth showing ("No known data errors" isn't).
    def data_errors
      errors unless errors.nil? || errors.start_with?('No known data errors')
    end

    private

    def leaves(rows)
      rows.flat_map { |row| row['children'].blank? ? [row] : leaves(row['children']) }
    end
  end

  class << self
    # { installed: true/false, pools: [Pool], error: nil or why the pools couldn't be read }.
    def status
      reply = Privileged.call('pools.status')
      pools = Array(reply['pools']).map do |pool|
        fields = pool.slice(*(Pool.members.map(&:to_s) - ['vdevs'])).transform_keys(&:to_sym)
        Pool.new(**fields, vdevs: Array(pool['vdevs']))
      end
      { installed: reply['zfs'] == true, pools: pools, error: reply['error'] }
    rescue Privileged::Error => e
      { installed: false, pools: [], error: e.message }
    end

    # Every whole disk, with what it's used for (:role) and whether a new pool may take it
    # (:free). Roles: :os (the system runs from it), :share (mounted as share storage),
    # :in_use (mounted elsewhere, or LVM, RAID or encryption on it), :pool (in an imported
    # pool), :old_zfs (a ZFS label from a pool that isn't imported here; a new pool
    # erases it), :free.
    def drives(pools = [])
      lsblk.select { |d| d['type'] == 'disk' }.map do |disk|
        nodes = subtree(disk)
        mounts = nodes.flat_map { |n| Array(n['mountpoints']).compact }
        label = nodes.find { |n| n['fstype'] == 'zfs_member' }&.dig('label')
        pool = pools.find { |p| p.drives.any? { |d| nodes.any? { |n| n['path'] == d['device'] } } }&.name
        role = if mounts.any? { |m| !m.start_with?('/mnt/') } then :os
               elsif mounts.any? then :share
               elsif nodes.any? { |n| !%w[disk part].include?(n['type']) } then :in_use
               elsif pool then :pool
               elsif label then :old_zfs
               else :free
               end
        { path: disk['path'], model: disk['model'].to_s.strip.presence, serial: disk['serial'], size: disk['size'].to_i,
          ssd: [false, '0', 0].include?(disk['rota']), role: role, pool: pool || label, mounts: mounts,
          free: %i[free old_zfs].include?(role) }
      end
    end

    # Installs ZFS (apt's output passed to +progress+ line by line), then loads it and caps
    # its memory cache.
    def install!(&progress)
      progress ||= ->(_line) {}
      progress.call('Installing ZFS (zfsutils-linux)...')
      privileged('packages.install', packages: [PACKAGE]) { |line| progress.call("  #{line}") }
      progress.call('Loading ZFS and limiting its memory cache...')
      reply = privileged('zfs.setup')
      cache = reply['arc_max'] && ActiveSupport::NumberHelper.number_to_human_size(reply['arc_max'])
      progress.call(cache ? "  ✓ ZFS's cache is limited to #{cache}" : '  ✓ ZFS is loaded')
    end

    # Creates a pool. The helper checks the name, the layout and every drive, and wipes them.
    def create!(name:, layout:, devices:)
      raise Error, 'Choose a layout' unless LAYOUTS.any? { |l| l[:key] == layout }
      raise Error, 'Choose the drives for the pool' if devices.blank?
      privileged('pools.create', name: name.to_s.strip, layout: layout, devices: devices.map(&:to_s))
    end

    private

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      raise Error, e.message
    end

    # lsblk's whole tree, sizes in bytes. Runs as the app (no root needed); [] if it fails.
    def lsblk
      out, _err, status = Open3.capture3('lsblk', '-J', '-b', '-o', 'PATH,TYPE,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS,ROTA')
      status.success? ? JSON.parse(out)['blockdevices'] || [] : []
    rescue SystemCallError, JSON::ParserError
      []
    end

    def subtree(node)
      [node, *Array(node['children']).flat_map { |child| subtree(child) }]
    end
  end
end
