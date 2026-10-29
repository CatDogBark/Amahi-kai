# frozen_string_literal: true

# ZFS pools: making, growing and repairing them, their datasets and snapshots, import and export.
module AmahiHelper
  # ZFS pools (docs/plans/storage.md), on whole disks of their own, mounted under POOL_ROOT, not
  # /mnt. A share on a pool lives in its shares dataset, POOL_ROOT/<pool>/shares (pools.shares_root):
  # share folders are made there, in SHARE_ROOT, or on data drives under /mnt, and nowhere else
  # on a pool. bitShare's data gets a dataset of its own (Phase 4).
  ZPOOL = '/usr/sbin/zpool'

  WIPEFS = '/usr/sbin/wipefs'

  # Words zpool keeps for vdev types, and names that look like Solaris disks (c0...).
  RESERVED_POOL_NAMES = /\A(?:mirror|raidz\d?|draid\d?|spare|log|cache|special|dedup|c\d.*)\z/

  # The layouts a new pool may have: the fewest drives, and whether they go in pairs.
  POOL_LAYOUTS = {
    'mirror' => { min: 2 }, 'striped_mirrors' => { min: 4, pairs: true },
    'raidz1' => { min: 3 }, 'raidz2' => { min: 4 }, 'raidz3' => { min: 5 }
  }.freeze

  POOL_MAX_DRIVES = 24

  # A pool names its drives by these /dev/disk/by-id links (model and serial first, so a
  # failed drive can be found), so it doesn't depend on the order drives appear at boot.
  BY_ID = '/dev/disk/by-id'

  BY_ID_PREFERENCE = %w[ata- nvme- scsi- wwn- virtio-].freeze

  # ZFS's memory cache (ARC): at most 2 GiB, and at most half the memory. ZFS keeps at least a
  # 32nd of the memory cached and ignores a cap that isn't above that (at boot without a word,
  # and a running module refuses it), so on a server with more than 64 GiB the cap is just above
  # it: ARC_MARGIN more.
  ARC_LIMIT = 2 * 1024**3

  MEMINFO = '/proc/meminfo'

  ZFS_MODPROBE = '/etc/modprobe.d/zfs-amahi.conf'

  ZFS_ARC_MAX = '/sys/module/zfs/parameters/zfs_arc_max'

  # The cache's own figures; c_max is the cap ZFS uses.
  ARCSTATS = '/proc/spl/kstat/zfs/arcstats'

  # Snapshots: amahi-kai-snapshots.timer runs pools.run_snapshots every hour. Each pool keeps
  # its newest N hourly and daily snapshots, N in its own ZFS properties (amahi:snapshot-hourly,
  # amahi:snapshot-daily; unset means the default). Only snapshots named like ours are ever
  # destroyed; manual ones are never pruned.
  SNAPSHOT_KINDS = { 'hourly' => 50 * 60, 'daily' => 23 * 3600 }.freeze # kind => seconds before the next is due

  SNAPSHOT_KEEP = { 'hourly' => 24, 'daily' => 30 }.freeze

  SNAPSHOT_LIMITS = { 'hourly' => 0..168, 'daily' => 0..366 }.freeze

  # Named for when they were taken, in UTC (earlier ones in the server's time, whose hour after
  # the clocks go back repeats the one before).
  SNAPSHOT_NAME = /\Aamahi-(hourly|daily|manual)-\d{4}-\d\d-\d\d-\d{4}(?:\d\d)?\z/

  ZFS_PACKAGES = %w[zfsutils-linux zfs-zed].freeze

  # Pools taken offline on Disks → ZFS Pools (pools.export), as { name => GUID }: their drives
  # stay theirs, and only these can be brought back (pools.import), by GUID, so a pool from
  # another server is never mounted here with a click.
  OFFLINE_POOLS = '/var/lib/amahi-kai/offline-pools.json'


  add_operations(
    # Loads ZFS and caps its memory cache (see ARC_LIMIT), now and at every boot, replying with
    # the cap ZFS uses. Run once zfsutils-linux is installed, and at every System Update, so the
    # cap follows memory added since.
    'zfs.setup' => {
      params: [],
      validate: ->(_a) { installed!(ZPOOL) && { arc_max: arc_limit } },
      plan: lambda { |v|
        [['/usr/sbin/modprobe', 'zfs'],
         [:install, ZFS_MODPROBE, "options zfs zfs_arc_max=#{v[:arc_max]}\n", nil],
         [:set_arc_max, v[:arc_max]]]
      }
    },
    # Removes ZFS (Disks → ZFS Pools) when there's no pool, online or offline: its packages,
    # Amahi-kai's setting for its cache, and the module, now.
    'zfs.uninstall' => {
      params: [],
      validate: ->(_a) { installed!(ZPOOL) && zfs_removable! },
      plan: lambda { |_v|
        [['/usr/bin/apt-get', '-y', '-o', 'DPkg::Lock::Timeout=300', 'purge', *ZFS_PACKAGES, { env: APT_ENV, stream: true }],
         [:remove_files, ZFS_MODPROBE, OFFLINE_POOLS],
         ['/usr/sbin/modprobe', '-r', 'zfs', { allow_failure: true }]]
      }
    },
    # The pools, with their drives, health and last scrub (Disks → ZFS Pools). Read-only. With
    # scan (the ZFS Pools page) it also lists the pools on the drives that aren't imported, taken
    # offline here or found there: the scan reads every drive, waking any asleep, so the other
    # pages and the health check leave it out.
    'pools.status' => {
      params: %w[scan],
      validate: ->(a) { { scan: a['scan'] == true } },
      plan: ->(v) { [[:pool_status, v[:scan]]] }
    },
    # A new pool on whole data disks, which are wiped first, in the layout the user chose:
    # ashift=12, lz4 compression, autotrim when every drive is an SSD, autoexpand (replacing
    # every drive with a bigger one grows the pool), POSIX ACLs kept in the inode (an app that
    # writes a share sets a default ACL there; ZFS on Linux has them off unless asked), mounted at
    # POOL_ROOT/<name>. zpool records it in its cache file, so it's imported at every boot.
    'pools.create' => {
      params: %w[name layout devices],
      validate: ->(a) { pool_request(a['name'], a['layout'], a['devices']) },
      plan: lambda { |v|
        [*v[:wipe].map { |device| [WIPEFS, '-a', device] },
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [:make_dir, POOL_ROOT, '0755'],
         [ZPOOL, 'create', '-f', '-o', 'ashift=12', '-o', 'autoexpand=on', *(v[:ssd] ? %w[-o autotrim=on] : []),
          '-O', 'compression=lz4', '-O', 'setuid=off', '-O', 'devices=off', '-O', 'acltype=posixacl', '-O', 'xattr=sa',
          '-O', "mountpoint=#{POOL_ROOT}/#{v[:name]}",
          *SNAPSHOT_KEEP.flat_map { |kind, keep| ['-O', "amahi:snapshot-#{kind}=#{keep}"] }, v[:name], *v[:vdevs]],
         [:pool_status]]
      }
    },
    # Replaces one of a pool's drives (old: its name in `zpool status -P`, a path or, for a
    # missing drive, a number) with a free whole disk, wiped first. ZFS copies the pool's
    # data onto it (a resilver) and keeps using the old drive, if it's there, until done.
    # Brings a pool's drive that ZFS has taken out (REMOVED, OFFLINE, FAULTED or UNAVAIL) back
    # into it (zpool online) once its disk is connected again: a reseated cable, a drive that
    # dropped out for a moment. ZFS then resilvers what changed while it was out. A drive that
    # isn't connected is refused (a dead one is replaced instead).
    'pools.online_drive' => {
      params: %w[name drive],
      validate: ->(a) { online_drive_request(a['name'], a['drive']) },
      plan: ->(v) { [[ZPOOL, 'online', v[:name], v[:drive]], [:pool_status]] }
    },
    'pools.replace' => {
      params: %w[name old new],
      validate: ->(a) { replace_request(a['name'], a['old'], a['new']) },
      plan: lambda { |v|
        [*v[:wipe].map { |device| [WIPEFS, '-a', device] },
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [ZPOOL, 'replace', v[:name], v[:old], v[:new]],
         [:pool_status]]
      }
    },
    # Grows a pool by one group of free whole disks shaped like its groups: the same layout
    # (mirror or RAIDZ level) and the same number of drives, so its redundancy stays even.
    # zpool add checks that too (no -f).
    'pools.add_group' => {
      params: %w[name devices],
      validate: ->(a) { add_group_request(a['name'], a['devices']) },
      plan: lambda { |v|
        [*v[:wipe].map { |device| [WIPEFS, '-a', device] },
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [ZPOOL, 'add', '-o', 'ashift=12', v[:name], *v[:vdevs]],
         [:pool_status]]
      }
    },
    # Destroys a pool and everything on it; confirm must repeat its name. Its drives' ZFS
    # labels are cleared and the drives wiped, so they're free for share storage or a new pool.
    'pools.destroy' => {
      params: %w[name confirm],
      validate: ->(a) { destroy_request(a['name'], a['confirm']) },
      plan: lambda { |v|
        [[:release_pool, v[:name]],
         [ZPOOL, 'destroy', v[:name]],
         *v[:members].map { |part| [ZPOOL, 'labelclear', '-f', part, { allow_failure: true }] },
         *v[:wipe].map { |device| [WIPEFS, '-a', device, { allow_failure: true }] },
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [:remove_pool_dir, v[:name]],
         [:forget_app_storage, v[:kept]],
         [:pool_status]]
      }
    },
    # Erases a free disk's old ZFS label: one a replaced drive keeps once it's left its pool (ZFS
    # leaves a label from no pool on it), or one from a pool on another server. Share storage never
    # takes a disk with a ZFS label, so this frees it for that too. Only a disk a new pool could
    # take: not the system's, nothing on it mounted or in use, not in a pool here, online or offline.
    # A drive of a pool found on the drives (not imported) needs that pool's name in confirm.
    'pools.erase_drive' => {
      params: %w[device confirm],
      validate: ->(a) { erase_drive_request(a['device'], a['confirm']) },
      plan: lambda { |v|
        [*v[:labels].map { |part| [ZPOOL, 'labelclear', '-f', part, { allow_failure: true }] },
         *v[:wipe].map { |device| [WIPEFS, '-a', device] },
         ['/usr/bin/udevadm', 'settle', { allow_failure: true }],
         [:pool_status]]
      }
    },
    # Takes a pool offline: unmounted and out of ZFS's cache file, so it stays offline after a
    # reboot, and recorded in OFFLINE_POOLS so its drives stay its own. Fails while something
    # has files open on it.
    'pools.export' => {
      params: %w[name],
      validate: ->(a) { installed!(ZPOOL) && export_request(a['name']) },
      plan: ->(v) { [[:export_pool, v[:name], v[:guid]], [:pool_status]] }
    },
    # The folder a pool's SMB shares live in: its dataset <pool>/shares, mounted at
    # POOL_ROOT/<pool>/shares and owned by root (the shares are folders in it, made by
    # shares.create_dir). Made the first time a share goes on the pool; it inherits the pool's
    # setuid=off and devices=off, and is in its snapshots.
    'pools.shares_root' => {
      params: %w[name],
      validate: ->(a) { installed!(ZFS) && { name: managed_pool(a['name']) } },
      plan: ->(v) { [[:pool_shares_root, v[:name]]] }
    },
    # Brings back a pool taken offline here, by the GUID recorded then, at its own mount point.
    'pools.import' => {
      params: %w[name],
      validate: ->(a) { installed!(ZPOOL) && import_request(a['name']) },
      plan: ->(v) { [[:make_dir, POOL_ROOT, '0755'], [:import_pool, v[:name], v[:guid]], [:pool_status]] }
    },
    # Imports a pool found on the drives (pools.status's 'found'), by its id: this server's from
    # before it was installed again, or one whose drives came too late at boot. It's imported
    # without mounting anything, then mounted only if it's one of Amahi-kai's (everything of it
    # mounts under POOL_ROOT/<name>); otherwise it's exported again, left as it was. Its folders
    # get setuid=off and devices=off, as pools.create makes them.
    'pools.import_found' => {
      params: %w[id],
      validate: ->(a) { installed!(ZPOOL) && found_import_request(a['id']) },
      plan: ->(v) { [[:make_dir, POOL_ROOT, '0755'], [:import_found_pool, v[:name], v[:id], v[:force]], [:pool_status]] }
    },
    # Takes a snapshot of a pool now (all its datasets), kept until it's deleted.
    'pools.snapshot' => {
      params: %w[name],
      validate: ->(a) { installed!(ZPOOL) && { name: managed_pool(a['name']), stamp: Time.now.utc.strftime('%Y-%m-%d-%H%M%S') } },
      plan: ->(v) { [[ZFS, 'snapshot', '-r', "#{v[:name]}@amahi-manual-#{v[:stamp]}"], [:pool_status]] }
    },
    # How many hourly and daily snapshots a pool keeps (0 turns that kind off and removes them).
    'pools.snapshot_policy' => {
      params: %w[name hourly daily],
      validate: lambda { |a|
        installed!(ZPOOL) && { name: managed_pool(a['name']), hourly: integer(a, 'hourly', SNAPSHOT_LIMITS['hourly']),
                               daily: integer(a, 'daily', SNAPSHOT_LIMITS['daily']) }
      },
      plan: lambda { |v|
        [[ZFS, 'set', "amahi:snapshot-hourly=#{v[:hourly]}", "amahi:snapshot-daily=#{v[:daily]}", v[:name]],
         [:prune_snapshots, v[:name]], [:pool_status]]
      }
    },
    # Deletes one of Amahi-kai's snapshots of a pool (in all its datasets).
    'pools.destroy_snapshot' => {
      params: %w[name snapshot],
      validate: ->(a) { snapshot_request(a['name'], a['snapshot']) },
      plan: ->(v) { [[ZFS, 'destroy', '-r', "#{v[:name]}@#{v[:snapshot]}"], [:pool_status]] }
    },
    # Rolls a pool (every dataset that has the snapshot) back to one of Amahi-kai's snapshots:
    # changes since are lost, and so are the snapshots taken after it. confirm repeats the name.
    'pools.rollback' => {
      params: %w[name snapshot confirm],
      validate: lambda { |a|
        values = snapshot_request(a['name'], a['snapshot'])
        raise Refused, "type the pool's name (#{values[:name]}) to roll it back" unless a['confirm'] == values[:name]
        values
      },
      plan: ->(v) { [[:rollback_pool, v[:name], v[:snapshot]], [:pool_status]] }
    },
    # The hourly job (amahi-kai-snapshots.timer): takes each pool's due snapshots and removes
    # the oldest beyond what it keeps.
    'pools.run_snapshots' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:run_snapshots]] }
    },
    # Starts a scrub of one pool: ZFS reads every block and repairs what it can from the
    # pool's redundancy. Ubuntu's ZFS package also scrubs every healthy pool on the second
    # Sunday of each month (/etc/cron.d/zfsutils-linux).
    'pools.scrub' => {
      params: %w[name],
      validate: ->(a) { installed!(ZPOOL) && { name: managed_pool(a['name']) } },
      plan: ->(v) { [[ZPOOL, 'scrub', v[:name]]] }
    },
  )

  class << self
    # The same for a ZFS pool: ZFS would unmount it here, then refuse to go on ("pool is busy")
    # while a container still has one of its folders mounted (a share given to the app and
    # deleted since, say). Checked before anything is unmounted.
    def pool_not_held!(name, doing)
      holders = pool_mount_holders(name)
      return if holders.empty?

      raise Refused, "#{name} is still in use by #{holder_labels(holders)}, which has folders on it mounted: " \
                     "stop it on Apps, then #{doing}"
    end

    # The same for the datasets of the pool +name+: ["amahi-bitshare"].
    def pool_mount_holders(name)
      holder_names(holding_views do |fields|
        dash = fields.index('-')
        source = dash && fields[dash + 2].to_s
        dash && fields[dash + 1] == 'zfs' && (source == name || source.start_with?("#{name}/"))
      end)
    end

    # --- ZFS pools ---

    def pool_request(name, layout, devices)
      installed!(ZPOOL)
      scan = importable_pools
      name = new_pool_name(name, scan)
      layout = listed(layout, 'layout', POOL_LAYOUTS.keys)
      raise Refused, 'devices must be a list of disks' unless devices.is_a?(Array) && devices.size <= POOL_MAX_DRIVES
      rule = POOL_LAYOUTS.fetch(layout)
      raise Refused, "#{layout} needs at least #{rule[:min]} drives" if devices.size < rule[:min]
      raise Refused, "#{layout} needs an even number of drives" if rule[:pairs] && devices.size.odd?
      tree = block_tree
      pooled = pooled_devices
      offline = offline_devices(scan)
      found = found_devices(scan)
      disks = devices.map { |device| pool_disk(device, tree, pooled, offline, found) }
      paths = disks.map(&:first)
      raise Refused, "#{paths.find { |p| paths.count(p) > 1 }} is listed twice" if paths.uniq.size != paths.size
      { name: name, wipe: disks.flat_map { |_path, node| wipe_targets(node) },
        vdevs: vdev_args(layout, paths.map { |path| stable_path(path) }), ssd: paths.all? { |path| ssd?(path) } }
    end

    # A name no pool here has: not an imported pool's, an offline one's (it would be lost from the
    # page, its drives offered as free), or one's found on the drives (+scan+, importable_pools).
    def new_pool_name(value, scan)
      value = string(value, 'name', max: 32)
      raise Refused, "pool name #{value.inspect} must be 1-32 lowercase letters, digits, _ or -, starting with a letter" unless value.match?(POOL_NAME)
      raise Refused, "#{value} is a word ZFS keeps for itself" if value.match?(RESERVED_POOL_NAMES)
      raise Refused, "a pool named #{value} already exists" if pool_names.include?(value)
      raise Refused, "a pool named #{value} is offline here; bring it online, or delete it, first" if offline_records.key?(value)
      if scan.any? { |pool| pool['name'] == value }
        raise Refused, "a pool named #{value} is on drives connected here, not imported; import it, or erase its drives, first"
      end
      free_pool_dir!(value)
      value
    end

    # The pool's mount point, POOL_ROOT/<name>, is free: missing, or an empty folder.
    def free_pool_dir!(name)
      if File.exist?(POOL_ROOT) || File.symlink?(POOL_ROOT)
        raise Refused, "#{POOL_ROOT} must be a real folder" unless File.realpath(POOL_ROOT) == POOL_ROOT
      end
      target = "#{POOL_ROOT}/#{name}"
      if File.exist?(target) || File.symlink?(target)
        raise Refused, "#{target} is in the way (not an empty folder)" unless File.lstat(target).directory? && Dir.empty?(target) && !mount_point?(target)
      end
    end

    # A whole data disk with nothing on it in use: not the system's, nothing mounted, no
    # LVM, RAID or encryption on it, nothing of it in fstab, and not in a pool: imported, taken
    # offline here, or found on the drives (+found_drives+), unless that pool's name is +confirm+
    # (Erase). Returns [path, its lsblk node].
    def pool_disk(value, tree, pooled, offline_drives, found_drives, confirm: nil)
      value = string(value, 'device', max: 64)
      raise Refused, "#{value.inspect} is not a whole disk" unless value.match?(WHOLE_DISK)
      raise Refused, "#{value} doesn't exist" unless File.blockdev?(value)
      node = tree.find { |disk| disk['path'] == value } or raise Refused, "lsblk doesn't list #{value}"
      mounted = mountpoints(node)
      system_mounts = mounted.reject { |mp| mp.start_with?("#{MNT}/") }
      raise Refused, "#{value} is a disk the system uses (#{system_mounts.first} is mounted from it)" if system_mounts.any?
      raise Refused, "#{value} is mounted at #{mounted.first}; unmount it first" if mounted.any?
      nodes = subtree(node)
      other = nodes.find { |n| !%w[disk part].include?(n['type']) }
      raise Refused, "#{value} holds #{other['path']} (#{other['type']}), which is in use" if other
      pool = nodes.map { |n| pooled[n['path']] }.compact.first
      raise Refused, "#{value} is in the pool #{pool}" if pool
      offline = nodes.map { |n| offline_drives[n['path']] }.compact.first
      raise Refused, "#{value} is in the pool #{offline}, which is offline; bring it online on Disks → ZFS Pools, or delete it there" if offline
      found = nodes.map { |n| found_drives[n['path']] }.compact.first
      if found && confirm.nil?
        raise Refused, "#{value} holds the pool #{found}, which isn't imported; import it on Disks → ZFS Pools, or erase the drive there"
      end
      raise Refused, "type the pool's name (#{found}) to erase #{value}" if found && confirm != found
      sources = fstab_entries.map(&:first)
      nodes.each do |n|
        info = probe(n['path'])
        names = [n['path'], ("UUID=#{info['UUID']}" if info['UUID']), ("PARTUUID=#{info['PART_ENTRY_UUID']}" if info['PART_ENTRY_UUID'])]
        listed = (names.compact & sources).first
        raise Refused, "#{n['path']} is in /etc/fstab (#{listed}); unmount it on Disks → Devices first" if listed
      end
      [value, node]
    end

    def replace_request(name, old, new)
      installed!(ZPOOL)
      name = managed_pool(name)
      old = string(old, 'old', max: 256)
      leaves = pool_leaves(pool_vdevs(name))
      raise Refused, "#{old.inspect} isn't a drive in the pool #{name}" unless leaves.any? { |leaf| leaf['name'] == old }
      scan = importable_pools
      path, node = pool_disk(new, block_tree, pooled_devices, offline_devices(scan), found_devices(scan))
      { name: name, old: old, new: stable_path(path), wipe: wipe_targets(node) }
    end

    # The states ZFS puts a drive in when it's out of its pool.
    OUT_OF_POOL = %w[REMOVED OFFLINE FAULTED UNAVAIL].freeze

    def online_drive_request(name, drive)
      installed!(ZPOOL)
      name = managed_pool(name)
      drive = string(drive, 'drive', max: 256)
      leaf = pool_leaves(pool_vdevs(name)).find { |row| row['name'] == drive }
      raise Refused, "#{drive.inspect} isn't a drive in the pool #{name}" unless leaf
      raise Refused, "#{drive} is #{leaf['state']}, in the pool already" unless OUT_OF_POOL.include?(leaf['state'])
      raise Refused, "#{drive} isn't connected: connect it again, or replace it" unless leaf['device'] && File.exist?(drive)

      { name: name, drive: whole_disk_of(drive) }
    end

    # zpool online grows a drive to fill its disk when the pool has autoexpand on, which needs
    # the disk: given the partition ZFS made on it (<disk>-part1, beside its -part9), it can't
    # read the disk's size ("cannot relabel ... unable to read disk capacity"). zpool finds the
    # drive by its disk just the same. Any other path is passed as it is.
    def whole_disk_of(path)
      disk = path.delete_suffix('-part1')
      return path if disk == path || !File.exist?(disk) || !File.exist?("#{disk}-part9")

      disk
    end

    def add_group_request(name, devices)
      installed!(ZPOOL)
      name = managed_pool(name)
      groups = pool_vdevs(name).map { |vdev| [vdev['name'].to_s[/\A(mirror|raidz[123])-\d+\z/, 1], vdev['children'].size] }
      layout, width = groups.first
      unless layout && groups.uniq.size == 1
        raise Refused, "the pool #{name} isn't made of matching mirror or RAIDZ groups; grow it from the command line"
      end
      raise Refused, 'devices must be a list of disks' unless devices.is_a?(Array)
      raise Refused, "a new #{layout} group in #{name} needs #{width} drives, like the others" unless devices.size == width
      tree = block_tree
      pooled = pooled_devices
      scan = importable_pools
      offline = offline_devices(scan)
      found = found_devices(scan)
      disks = devices.map { |device| pool_disk(device, tree, pooled, offline, found) }
      paths = disks.map(&:first)
      raise Refused, "#{paths.find { |p| paths.count(p) > 1 }} is listed twice" if paths.uniq.size != paths.size
      { name: name, wipe: disks.flat_map { |_path, node| wipe_targets(node) },
        vdevs: [layout, *paths.map { |path| stable_path(path) }] }
    end

    def erase_drive_request(value, confirm)
      installed!(ZPOOL)
      confirm = confirm.nil? || confirm == '' ? nil : string(confirm, 'confirm', max: 32)
      scan = importable_pools
      path, node = pool_disk(value, block_tree, pooled_devices, offline_devices(scan), found_devices(scan), confirm: confirm || '')
      labels = subtree(node).select { |n| n['fstype'] == 'zfs_member' }.map { |n| n['path'] }
      raise Refused, "#{path} has no ZFS label to erase" if labels.empty?

      { labels: labels, wipe: wipe_targets(node) }
    end

    def destroy_request(name, confirm)
      installed!(ZPOOL)
      name = managed_pool(name)
      raise Refused, "type the pool's name (#{name}) to destroy it" unless confirm == name
      no_shares_on!(name)
      no_apps_on!(name, 'deleted')
      pool_not_held!(name, 'delete it')
      members = pool_leaves(pool_vdevs(name)).filter_map { |leaf| leaf['device'] }
      tree = block_tree
      disks = members.filter_map { |part| tree.find { |disk| subtree(disk).any? { |n| n['path'] == part } } }.uniq
      { name: name, members: members, wipe: disks.flat_map { |disk| pool_wipe_targets(disk, members) },
        kept: apps_on_pool(name).map(&:first) }
    end

    # What of +disk+ goes with a deleted pool: the whole disk when all of it was the pool's (its
    # members, and the small partition ZFS keeps beside each, which has no filesystem), else only
    # the members on it, so a disk shared with anything else (a system's boot partition) keeps that.
    def pool_wipe_targets(disk, members)
      others = subtree(disk).drop(1).reject { |n| members.include?(n['path']) }
      return wipe_targets(disk) if others.all? { |n| n['fstype'].nil? && (n['children'] || []).empty? && mountpoints(n).empty? }

      subtree(disk).select { |n| members.include?(n['path']) }.flat_map { |n| wipe_targets(n) }
    end

    # A pool an installed app keeps its data on isn't taken offline or deleted: the app would lose
    # it. Data kept from an uninstalled app doesn't stop it (deleting the pool deletes that too).
    def no_apps_on!(name, what)
      on = apps_on_pool(name).select { |_id, installed| installed }.map(&:first)
      return if on.empty?

      raise Refused, "#{on.join(' and ')} #{on.size == 1 ? 'keeps its' : 'keep their'} data on #{name}, so it can't be #{what}: " \
                     "uninstall #{on.size == 1 ? 'it' : 'them'} on Apps first (the data stays on the pool unless you delete it)"
    end

    def export_request(name)
      name = managed_pool(name)
      no_shares_on!(name)
      no_apps_on!(name, 'taken offline')
      pool_not_held!(name, 'take it offline')
      guid = capture([ZPOOL, 'get', '-H', '-o', 'value', 'guid', name]).strip
      recorded = offline_records[name]
      if recorded && recorded.to_s != guid
        raise Refused, "another pool named #{name} is offline here already; rename one of them from the command line first"
      end
      { name: name, guid: guid }
    end

    # A pool with SMB shares on it isn't taken offline or destroyed: Samba (and any app given
    # them) would lose their folders.
    def no_shares_on!(name)
      on = samba_shares.values.select { |share| share[:path].to_s.start_with?("#{pool_root}/#{name}/") }.map { |share| share[:name] }.sort
      return if on.empty?

      raise Refused, "#{on.size == 1 ? 'the share' : 'the shares'} #{on.join(', ')} #{on.size == 1 ? 'is' : 'are'} on #{name}: " \
                     "delete #{on.size == 1 ? 'it' : 'them'} on Shares first"
    end

    def import_request(value)
      value = string(value, 'name', max: 32)
      guid = offline_records[value]
      raise Refused, "#{value.inspect} isn't a pool taken offline here" unless value.match?(POOL_NAME) && guid
      raise Refused, "a pool named #{value} is already online" if pool_names.include?(value)
      { name: value, guid: guid.to_s }
    end

    # The states `zpool import` gives a pool that can be imported: all its drives found, or
    # enough of them.
    IMPORTABLE_STATES = %w[ONLINE DEGRADED].freeze

    # A pool found on the drives (found_pools), by its id (GUID): imported under its own name,
    # which must be one no pool here has, and only while ZFS finds enough of its drives.
    def found_import_request(value)
      id = string(value, 'id', max: 20)
      raise Refused, "#{id.inspect} isn't a pool's id" unless id.match?(/\A\d{1,20}\z/)
      pool = found_pools.find { |p| p['id'] == id } or raise Refused, "no pool with the id #{id} is on the drives, not imported"
      name = pool['name'].to_s
      unless name.match?(POOL_NAME) && !name.match?(RESERVED_POOL_NAMES)
        raise Refused, "the pool's name #{name.inspect} isn't one Amahi-kai gives pools; import it from the command line"
      end
      raise Refused, "a pool named #{name} is already imported here" if pool_names.include?(name)
      raise Refused, "a pool named #{name} is offline here; bring that one online, or delete it, first" if offline_records.key?(name)
      raise Refused, "ZFS finds #{name} #{pool['state']}: connect its missing drives first" unless IMPORTABLE_STATES.include?(pool['state'])
      free_pool_dir!(name)
      { name: name, id: id, force: pool['force'] == true }
    end

    def zfs_removable!
      pool = pool_names.first
      raise Refused, "the pool #{pool} is still here; delete it on Disks → ZFS Pools first" if pool
      offline = offline_records.keys.first
      raise Refused, "the pool #{offline} is offline; bring it online and delete it first" if offline
      {}
    end

    # { name => GUID } of the pools taken offline here.
    def offline_records
      records = read_json(OFFLINE_POOLS)
      records.is_a?(Hash) ? records.select { |name, guid| name.is_a?(String) && guid.to_s.match?(/\A\d+\z/) } : {}
    end

    # The pools taken offline here and not back yet, as a scan of the drives (+scan+,
    # importable_pools; made only when there's a record) finds them: [{ 'name', 'state' (ZFS's, or
    # 'MISSING' when none of its drives is found), 'devices' => the partitions of it found, by
    # kernel name }].
    def offline_pools(scan = nil)
      records = offline_records
      return [] if records.empty?
      imported = pool_names
      scan ||= importable_pools
      records.reject { |name, _guid| imported.include?(name) }.map do |name, guid|
        pool = scan.find { |p| p['id'] == guid.to_s }
        { 'name' => name, 'state' => pool ? pool['state'] : 'MISSING', 'devices' => pool ? pool['devices'] : [] }
      end
    end

    # The other pools on the drives that aren't imported: this server's from before it was
    # installed again, one whose drives came too late at boot, or another server's. They're
    # offered for import by id (pools.import_found), and their drives are kept for them.
    # [{ 'name', 'id', 'state', 'force', 'status', 'devices' }], as importable_pools has them.
    def found_pools(scan = importable_pools)
      recorded = offline_records.values.map(&:to_s)
      scan.reject { |pool| recorded.include?(pool['id']) }
    end

    # { '/dev/sdc1' => 'test', ... }: every partition of a pool taken offline here.
    def offline_devices(scan = nil)
      offline_pools(scan).each_with_object({}) { |pool, found| pool['devices'].each { |device| found[device] = pool['name'] } }
    end

    # The same for the pools found on the drives.
    def found_devices(scan = importable_pools)
      found_pools(scan).each_with_object({}) { |pool, found| pool['devices'].each { |device| found[device] = pool['name'] } }
    end

    # What `zpool import` finds on the drives: [{ 'name', 'id', 'state', 'force', 'status',
    # 'devices' }]. It lists each pool that could be imported, its config naming the drives as in
    # BY_ID. force: ZFS asks for -f, the pool having been last used by another system (this server
    # before it was installed again, or another one); status: its note on the pool, if any.
    def importable_pools
      out, _err, status = Open3.capture3(ENV_MIN, ZPOOL, 'import', '-d', BY_ID, unsetenv_others: true, chdir: '/')
      return [] unless status.success?
      parse_importable(out)
    rescue SystemCallError
      []
    end

    def parse_importable(text)
      text.split(/^\s*pool: /).drop(1).map do |block|
        name = block.lines.first.strip
        header, config = block.split(/^\s*config:\s*$/, 2)
        config = config.to_s
        devices = config.lines.filter_map do |line|
          token = line.strip.split(/\s+/).first.to_s
          path = token.start_with?('/') ? token : File.join(BY_ID, token)
          File.realpath(path) if !token.empty? && File.exist?(path) && File.dirname(File.realpath(path)) == '/dev'
        rescue SystemCallError
          nil
        end
        { 'name' => name, 'id' => block[/^\s*id: (\d+)/, 1], 'state' => block[/^\s*state: (\S+)/, 1],
          'force' => header.include?("'-f'"), 'status' => parse_pool_status(header)['status'], 'devices' => devices.uniq }
      end
    end

    def snapshot_request(name, snapshot)
      installed!(ZPOOL)
      name = managed_pool(name)
      snapshot = string(snapshot, 'snapshot', max: 128)
      raise Refused, "#{snapshot.inspect} isn't one of Amahi-kai's snapshots" unless snapshot.match?(SNAPSHOT_NAME)
      raise Refused, "the pool #{name} has no snapshot #{snapshot}" unless pool_snapshots(name).any? { |snap| snap['name'] == snapshot }
      { name: name, snapshot: snapshot }
    end

    # The pool's own snapshots (its root dataset's), oldest first:
    # [{ 'name' => 'amahi-daily-2026-10-05-0012', 'kind' => 'daily', 'created' => epoch, 'used' => bytes }].
    # 'kind' is nil for snapshots Amahi-kai didn't take.
    def pool_snapshots(name)
      capture([ZFS, 'list', '-H', '-p', '-t', 'snapshot', '-d', '1', '-s', 'creation', '-o', 'name,creation,used', name])
        .lines(chomp: true).filter_map do |line|
          full, created, used = line.split("\t")
          snap = full.to_s.split('@', 2)[1] or next
          { 'name' => snap, 'kind' => snap[SNAPSHOT_NAME, 1], 'created' => created.to_i, 'used' => used.to_i }
        end
    end

    # { 'hourly' => 24, 'daily' => 30 } from the pool's properties; unset or broken: the default.
    def snapshot_policy(name)
      values = capture([ZFS, 'get', '-H', '-p', '-o', 'property,value', 'amahi:snapshot-hourly,amahi:snapshot-daily', name])
               .lines(chomp: true).to_h { |line| line.split("\t", 2) }
      SNAPSHOT_KEEP.to_h do |kind, default|
        value = values["amahi:snapshot-#{kind}"].to_s
        [kind, value.match?(/\A\d+\z/) ? value.to_i.clamp(SNAPSHOT_LIMITS[kind]) : default]
      end
    end

    def pool_vdevs(name)
      parse_pool_status(capture([ZPOOL, 'status', '-P', name]))['vdevs']
    end

    # Every drive in a pool's vdev tree, missing ones (no 'device') included.
    def pool_leaves(rows)
      rows.flat_map { |row| row['children'].empty? ? [row] : pool_leaves(row['children']) }
    end

    def existing_pool(value)
      value = string(value, 'name', max: 32)
      raise Refused, "there's no pool named #{value.inspect}" unless value.match?(POOL_NAME) && pool_names.include?(value)
      value
    end

    # One of Amahi-kai's own pools, the only ones it changes: one it made or imported, mounted at
    # POOL_ROOT/<name>. Others are only shown (a system that runs from ZFS has bpool and rpool).
    def managed_pool(value)
      name = existing_pool(value)
      mountpoint = pool_mountpoint(name)
      unless managed?(name, mountpoint)
        where = mountpoint ? "it mounts at #{mountpoint}" : "ZFS can't say where it mounts"
        raise Refused, "#{name} isn't one of Amahi-kai's pools (#{where}); manage it from the command line"
      end
      name
    end

    # When ZFS can't read the mount point (a pool whose drives are failing), the pool's folder in
    # POOL_ROOT says it's Amahi-kai's: one it made or imported was mounted there.
    def managed?(name, mountpoint = pool_mountpoint(name))
      mountpoint ? mountpoint == "#{POOL_ROOT}/#{name}" : File.directory?("#{POOL_ROOT}/#{name}")
    end

    # The mountpoint property of a pool's root dataset ('none' or 'legacy' when ZFS doesn't mount
    # it), or nil when ZFS can't read it.
    def pool_mountpoint(name)
      capture([ZFS, 'get', '-H', '-o', 'value', 'mountpoint', name]).strip
    rescue Failed
      nil
    end

    def subtree(node)
      [node, *(node['children'] || []).flat_map { |child| subtree(child) }]
    end

    # Partitions before the disk they're on, so no old filesystem signature is left behind.
    def wipe_targets(node)
      [*(node['children'] || []).flat_map { |child| wipe_targets(child) }, node['path']]
    end

    def vdev_args(layout, paths)
      case layout
      when 'mirror' then ['mirror', *paths]
      when 'striped_mirrors' then paths.each_slice(2).flat_map { |pair| ['mirror', *pair] }
      else [layout, *paths]
      end
    end

    def stable_path(disk)
      links = Dir.children(BY_ID).reject { |name| name.include?('-part') }
                 .select { |name| File.realpath(File.join(BY_ID, name)) == disk }
      best = links.min_by { |name| [BY_ID_PREFERENCE.index { |prefix| name.start_with?(prefix) } || BY_ID_PREFERENCE.size, name] }
      best ? File.join(BY_ID, best) : disk
    rescue SystemCallError
      disk
    end

    def ssd?(disk)
      File.read("/sys/block/#{File.basename(disk)}/queue/rotational").strip == '0'
    rescue SystemCallError
      false
    end

    def arc_limit
      memory = File.read(MEMINFO)[/^MemTotal:\s+(\d+) kB/, 1].to_i * 1024
      raise Failed, "couldn't read the memory size from #{MEMINFO}" unless memory.positive?
      [[ARC_LIMIT, memory / 32 + ARC_MARGIN].max, memory / 2].min
    end

    def pool_names
      return [] unless File.executable?(ZPOOL)
      capture([ZPOOL, 'list', '-H', '-o', 'name']).lines(chomp: true).reject(&:empty?)
    end

    # { '/dev/sdb1' => 'tank', ... }: every device in an imported pool, by its kernel name.
    def pooled_devices
      return {} unless File.executable?(ZPOOL)
      pool_names.each_with_object({}) do |pool, found|
        each_leaf(parse_pool_status(capture([ZPOOL, 'status', '-P', pool]))['vdevs']) { |leaf| found[leaf['device']] = pool }
      end
    end

    def each_leaf(rows, &block)
      rows.each do |row|
        row['children'].empty? ? (yield row if row['device']) : each_leaf(row['children'], &block)
      end
    end

    def pool_shares_root(pool)
      "#{pool_root}/#{pool}/shares"
    end

    # Whether +root+ (POOL_ROOT/<pool>/shares) is the dataset <pool>/shares, mounted there.
    def pool_shares_mounted?(root, mounts_file = '/proc/self/mounts')
      pool = root.delete_prefix("#{pool_root}/").delete_suffix('/shares')
      return false unless pool.match?(POOL_NAME) && root == pool_shares_root(pool)

      File.readlines(mounts_file).map(&:split).any? { |fields| fields[0] == "#{pool}/shares" && fields[1] == root && fields[2] == 'zfs' }
    rescue SystemCallError
      false
    end

    def pool_root
      POOL_ROOT
    end

    # --- ZFS pools ---

    # Takes each of Amahi-kai's pools' due hourly and daily snapshots, then prunes; other pools
    # are left alone. A pool that fails doesn't stop the others; the step fails at the end, so the
    # timer shows it.
    def do_run_snapshots(now = Time.now)
      return { 'pools' => [] } unless File.executable?(ZPOOL)
      results = pool_names.filter_map do |pool|
        next unless managed?(pool)

        policy = snapshot_policy(pool)
        snaps = pool_snapshots(pool)
        taken = SNAPSHOT_KINDS.filter_map do |kind, interval|
          next unless policy[kind].positive?
          last = snaps.select { |snap| snap['kind'] == kind }.map { |snap| snap['created'] }.max
          next if last && now.to_i - last < interval
          name = "amahi-#{kind}-#{now.utc.strftime('%Y-%m-%d-%H%M')}"
          run_command([ZFS, 'snapshot', '-r', "#{pool}@#{name}"])
          name
        end
        { 'pool' => pool, 'taken' => taken, 'pruned' => do_prune_snapshots(pool)['pruned'] }
      rescue Failed => e
        { 'pool' => pool, 'error' => e.message }
      end
      failed = results.select { |r| r['error'] }
      raise Failed, failed.map { |r| "#{r['pool']}: #{r['error']}" }.join('; ') if failed.any?
      { 'pools' => results }
    end

    # Destroys a pool's oldest hourly and daily snapshots beyond what it keeps. Only Amahi-kai's
    # hourly and daily snapshots are counted or touched.
    def do_prune_snapshots(pool)
      policy = snapshot_policy(pool)
      snaps = pool_snapshots(pool)
      pruned = policy.flat_map do |kind, keep|
        ours = snaps.select { |snap| snap['kind'] == kind }.sort_by { |snap| snap['created'] }
        ours.first([ours.size - keep, 0].max).map { |snap| snap['name'] }
      end
      pruned.each { |snap| run_command([ZFS, 'destroy', '-r', "#{pool}@#{snap}"]) }
      { 'pruned' => pruned }
    end

    # Rolls back every dataset in the pool that has the snapshot (snapshots are taken with -r). The
    # apps keeping their data on it are stopped first (ZFS won't roll back a dataset a container
    # holds open, and a roll-back comes first: CatDogBark, 2026-10-11), and the ones that were running
    # start again afterwards, rolled back or not.
    def do_rollback_pool(pool, snapshot)
      running = apps_on_pool(pool).select { |id, installed| installed && app_running?(id) }.map(&:first)
      running.each do |id|
        say("Stopping #{id} while the pool rolls back...")
        run_command([DOCKER, 'stop', '--time', '30', app_container(id)])
      end
      datasets = capture([ZFS, 'list', '-H', '-o', 'name', '-r', '-t', 'filesystem,volume', pool]).lines(chomp: true)
      snaps = capture([ZFS, 'list', '-H', '-o', 'name', '-r', '-t', 'snapshot', pool]).lines(chomp: true)
      rolled = datasets.select { |ds| snaps.include?("#{ds}@#{snapshot}") }
      rolled.each { |ds| run_command([ZFS, 'rollback', '-r', "#{ds}@#{snapshot}"]) }
      { 'rolled_back' => rolled, 'apps_stopped' => running }
    ensure
      Array(running).each { |id| run_command([DOCKER, 'start', app_container(id), { allow_failure: true }]) }
    end

    def do_forget_app_storage(ids)
      Array(ids).each { |id| app_forget_storage(id) }
      nil
    end

    # A pool taken offline or destroyed is unmounted, which ZFS refuses while anything has a folder
    # or file open on it ("pool or dataset is busy"). The Samba sessions holding it (a computer
    # connected to a share whose folder is, or was, on the pool) are ended: asked to stop, then
    # made to after USER_STOP_SECONDS; those computers reconnect to the other shares by themselves.
    # Anything else holding it is named, and nothing is taken offline.
    def do_release_pool(name)
      root = "#{pool_root}/#{name}"
      sessions = pool_holders(root).select { |holder| samba_session?(holder) }
      sessions.each { |holder| signal_process(holder[:pid], 'TERM') }
      deadline = monotonic_now + USER_STOP_SECONDS
      pause(0.2) while sessions.any? { |holder| process_alive?(holder[:pid]) } && monotonic_now < deadline
      sessions.each { |holder| signal_process(holder[:pid], 'KILL') if process_alive?(holder[:pid]) }
      others = pool_holders(root).reject { |holder| samba_session?(holder) }
      return nil if others.empty?

      named = others.map { |holder| "#{holder[:comm]} (process #{holder[:pid]})" }.uniq
      raise Failed, "#{name} is in use by #{named.join(', ')}: stop #{named.size == 1 ? 'it' : 'them'} first"
    end

    # The processes with a folder or file open on +root+, as their working folder, their root or an
    # open file: [{ pid:, comm:, ppid: }].
    def pool_holders(root)
      Dir.glob('/proc/[0-9]*').filter_map do |dir|
        links = ["#{dir}/cwd", "#{dir}/root", *Dir.glob("#{dir}/fd/*")]
        next unless links.any? { |link| on_path?(read_link(link), root) }

        stat = File.read("#{dir}/stat") # pid (comm) state ppid ...: comm may hold ") "
        { pid: File.basename(dir).to_i, comm: File.read("#{dir}/comm").strip, ppid: stat[(stat.rindex(')') + 2)..].split[1].to_i }
      rescue SystemCallError
        nil # gone meanwhile
      end
    end

    def read_link(link)
      File.readlink(link)
    rescue SystemCallError
      nil
    end

    def on_path?(target, root)
      !target.nil? && (target == root || target.start_with?("#{root}/"))
    end

    def signal_process(pid, signal)
      Process.kill(signal, pid)
    rescue SystemCallError
      nil # gone meanwhile
    end

    def process_alive?(pid)
      File.exist?("/proc/#{pid}")
    end

    # Makes the pool's shares dataset if it has none (it mounts at POOL_ROOT/<pool>/shares, the
    # pool's own mount point inherited), and checks it's mounted there before the share folders
    # go in it.
    def do_pool_shares_root(name)
      dataset = "#{name}/shares"
      begin
        capture([ZFS, 'list', '-H', '-o', 'name', dataset])
      rescue Failed
        run_command([ZFS, 'create', dataset])
      end
      root = pool_shares_root(name)
      raise Failed, "#{dataset} isn't mounted at #{root}" unless pool_shares_mounted?(root)

      do_own_dir(root, 'root', 'root', '0755')
      { 'root' => root }
    end

    # The pool's empty mount point, once the pool is gone.
    def do_remove_pool_dir(name)
      dir = "#{POOL_ROOT}/#{name}"
      Dir.rmdir(dir) if File.directory?(dir) && !File.symlink?(dir) && Dir.empty?(dir) && !mount_point?(dir)
      nil
    rescue SystemCallError
      nil
    end

    def do_export_pool(name, guid)
      do_release_pool(name)
      capture([ZPOOL, 'export', name])
      records = offline_records.merge(name => guid)
      do_make_dir(File.dirname(OFFLINE_POOLS), '0755')
      do_install(OFFLINE_POOLS, "#{JSON.pretty_generate(records)}\n", nil, '0640', APP_USER)
      nil
    end

    def do_import_pool(name, guid)
      capture([ZPOOL, 'import', '-d', BY_ID, guid])
      records = offline_records.except(name)
      do_install(OFFLINE_POOLS, "#{JSON.pretty_generate(records)}\n", nil, '0640', APP_USER)
      nil
    end

    # -N imports it with nothing mounted, so a pool that isn't Amahi-kai's never covers a folder of
    # the system: its datasets' mount points are checked first. (force: ZFS asks for -f, the pool
    # last used by another system, such as this one before it was installed again.)
    def do_import_found_pool(name, id, force)
      capture([ZPOOL, 'import', '-N', *(force ? ['-f'] : []), '-d', BY_ID, id])
      root = "#{POOL_ROOT}/#{name}"
      datasets = capture([ZFS, 'list', '-H', '-o', 'name,mountpoint,canmount,setuid,devices', '-r', '-t', 'filesystem', name])
                 .lines(chomp: true).map { |line| line.split("\t") }
      # The pool's own folder at POOL_ROOT/<name> (managed?), and everything that can mount inside it
      stray = datasets.find do |dataset, mountpoint, canmount|
        if dataset == name then mountpoint != root
        else canmount != 'off' && !%w[none legacy].include?(mountpoint) && !on_path?(mountpoint, root)
        end
      end
      if stray || datasets.empty?
        run_command([ZPOOL, 'export', name, { allow_failure: true }])
        where = stray ? "#{stray[0]} mounts at #{stray[1]}" : 'ZFS lists nothing in it'
        raise Failed, "#{name} isn't one of Amahi-kai's pools (#{where}), so it's left on its drives, not imported: import it from the command line"
      end
      datasets.each do |dataset, _mountpoint, _canmount, setuid, devices|
        run_command([ZFS, 'set', 'setuid=off', 'devices=off', dataset]) if setuid == 'on' || devices == 'on'
      end
      run_command([ZFS, 'mount', '-a'])
      nil
    end

    # Sets the running module's cap, and replies with the one ZFS uses (its c_max), or the cap
    # asked for when the module doesn't say.
    def do_set_arc_max(bytes)
      File.write(ZFS_ARC_MAX, bytes.to_s) if File.exist?(ZFS_ARC_MAX)
      { 'arc_max' => arc_in_use || bytes }
    rescue SystemCallError => e
      raise Failed, "couldn't set ZFS's cache size: #{e.message}"
    end

    def arc_in_use
      File.read(ARCSTATS)[/^c_max\s+\d+\s+(\d+)$/, 1]&.to_i
    rescue SystemCallError
      nil
    end

    # { 'zfs' => installed?, 'pools' => [...] }, each pool with its health, its raw size
    # (zpool's, parity included), the space its files use and have left (zfs's, after
    # parity), its mount point, whether it's one of Amahi-kai's ('managed', managed?) and what
    # `zpool status` says (see parse_pool_status). A pool that can't be read comes with an
    # 'error' instead. With +scan+, the pools on the drives that aren't imported too: 'offline'
    # and 'found' (offline_pools, found_pools).
    def do_pool_status(scan = true)
      return { 'zfs' => false, 'pools' => [] } unless File.executable?(ZPOOL)

      rows = capture([ZPOOL, 'list', '-H', '-p', '-o', 'name,size,allocated,free,health']).lines(chomp: true)
      pools = rows.filter_map do |line|
        name, size, allocated, free, health = line.split("\t")
        next if name.to_s.empty?
        pool = { 'name' => name, 'size' => size.to_i, 'allocated' => allocated.to_i, 'free' => free.to_i, 'health' => health }
        begin
          used, available, mountpoint, snapshot_space = capture([ZFS, 'list', '-H', '-p', '-o', 'used,available,mountpoint,usedbysnapshots', name]).chomp.split("\t")
          pool.merge!('used' => used.to_i, 'available' => available.to_i, 'mountpoint' => mountpoint,
                      'managed' => managed?(name, mountpoint), 'snapshot_space' => snapshot_space.to_i,
                      'snapshots' => pool_snapshots(name), 'snapshot_policy' => snapshot_policy(name))
          pool.merge(parse_pool_status(capture([ZPOOL, 'status', '-P', name])))
        rescue Failed => e
          pool.merge('error' => e.message, 'managed' => managed?(name, pool['mountpoint']))
        end
      end
      return { 'zfs' => true, 'pools' => pools } unless scan

      found = importable_pools
      { 'zfs' => true, 'pools' => pools, 'offline' => offline_pools(found), 'found' => found_pools(found) }
    rescue Failed => e
      { 'zfs' => true, 'pools' => [], 'offline' => [], 'found' => [], 'error' => e.message } # e.g. the ZFS module isn't loaded
    end

    # One pool's `zpool status -P`: its state, the status and action notes (shown when
    # something is wrong), the last scrub or resilver, the errors line, and its vdevs as a
    # tree: [{ 'name' => 'raidz1-0', 'state' => 'ONLINE', 'children' => [{ 'name' =>
    # '/dev/disk/by-id/ata-...-part1', 'device' => '/dev/sdb1', 'read' => '0', ... }] }].
    def parse_pool_status(text)
      fields = {}
      config = []
      key = nil
      text.each_line(chomp: true) do |line|
        if key == 'config'
          if line.start_with?('errors:')
            fields['errors'] = line.delete_prefix('errors:').strip
            key = 'errors'
          else
            config << line
          end
        elsif (match = line.match(/\A {0,8}([a-z]+):(?: (.*))?\z/))
          key = match[1]
          fields[key] = match[2].to_s.strip unless key == 'config'
        elsif key && line.match?(/\A\s+\S/)
          fields[key] = "#{fields[key]} #{line.strip}".strip # a note continued on the next line
        end
      end
      pool = pool_tree(config).first
      { 'state' => fields['state'], 'status' => fields['status'], 'action' => fields['action'], 'scan' => fields['scan'],
        'errors' => fields['errors'], 'vdevs' => pool ? pool['children'] : [] }
    end

    # The config section's rows, nested by their indent (two spaces a level, after a tab).
    def pool_tree(lines)
      root = { 'children' => [] }
      parents = [root]
      lines.each do |line|
        match = line.match(/\A\t( *)(\S+)(?:\s+([A-Z]+)(?:\s+(\S+)\s+(\S+)\s+(\S+))?)?\s*(.*)\z/) or next
        next if match[2] == 'NAME' && match[3] == 'STATE'
        depth = match[1].size / 2
        parent = parents[depth] or next
        row = { 'name' => match[2], 'state' => match[3], 'read' => match[4], 'write' => match[5], 'cksum' => match[6],
                'note' => (match[7].empty? ? nil : match[7]), 'children' => [] }
        row['device'] = device_name(row['name']) if row['name'].start_with?('/dev/')
        parent['children'] << row
        parents = parents.first(depth + 1) << row
      end
      root['children']
    end

    # The apps whose storage is on the pool +name+: [[id, installed?]] (installed: it has a
    # container; else only its data was kept at uninstall).
    def apps_on_pool(name)
      app_storage_records.select { |_id, pool| pool == name }.keys.sort.map { |id| [id, !app_image(id).nil?] }
    end
  end
end
