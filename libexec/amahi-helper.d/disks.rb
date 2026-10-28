# frozen_string_literal: true

# Disks: data drives (format, mount, unmount, fstab), what holds a drive, and drive health.
module AmahiHelper
  # Makes a data drive's empty mount point immutable while nothing is mounted on it (see
  # protect_mount_point).
  CHATTR = '/usr/bin/chattr'

  # The folder Greyhole keeps its metadata backups in, on each pool drive.
  GREYHOLE_METASTORE_BACKUP = '.gh_metastore_backup'

  DISK_DEVICE = %r{\A/dev/(?:[svx]d[a-z]{1,2}\d{0,3}|nvme\d{1,3}n\d{1,3}(?:p\d{1,3})?)\z}

  MOUNT_NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/

  SMARTCTL = '/usr/sbin/smartctl'

  # Where `smartctl -A` reports the temperature, in °C. ATA drives: the raw value of attribute
  # 194 (Temperature_Celsius) or 190 (Airflow_Temperature_Cel), the tenth column. NVMe and
  # SAS drives print a line of their own.
  TEMPERATURE_PATTERNS = [
    /^\s*194\s+\S+(?:\s+\S+){7}\s+(\d+)/,
    /^\s*190\s+\S+(?:\s+\S+){7}\s+(\d+)/,
    /^Temperature:\s+(\d+) Celsius/,
    /^Current Drive Temperature:\s+(\d+)/
  ].freeze

  MOUNTABLE_FS = %w[ext2 ext3 ext4 xfs btrfs ntfs vfat exfat].freeze

  # FAT and exFAT keep no owners or permissions: everything on a drive like that belongs to the
  # mount, root's by default, so only root could write there. They're mounted for the users group
  # (the share folders' group), which may write: folders 0775, files 0664. (ntfs-3g lets everyone
  # write unless told otherwise.)
  OWNERLESS_FS = %w[vfat exfat].freeze

  OWNERLESS_MASKS = %w[dmask=0002 fmask=0113].freeze

  FSTAB_OPTIONS = "defaults,nofail,#{MOUNT_OPTIONS.join(',')},x-systemd.device-timeout=10s".freeze

  FINDMNT = '/usr/bin/findmnt'

  PREVIEW_LIMIT = { entries: 1_000_000, seconds: 30 }.freeze

  # Ubuntu's smartmontools unit has ConditionVirtualization=no, so smartd never starts in a
  # virtual machine, even one given real drives (a drive controller passed through to it; the
  # unit's own comment says to override it then). An empty assignment resets the unit's
  # conditions, and that's its only one. With only virtual disks, smartd finds nothing with SMART
  # and stops itself, which System Status shows as idle.
  SMARTD_DROPIN = '/etc/systemd/system/smartmontools.service.d/amahi-kai.conf'

  SMARTD_DROPIN_CONTENT = <<~UNIT
    # Amahi-kai: start in a virtual machine too, which can be given real drives.
    [Unit]
    ConditionVirtualization=
  UNIT

  # The health check (storage.check_health) writes the pools and every drive's SMART data
  # here for the app's alerts. It keeps these ATA attributes: reallocated (5), pending (197)
  # and uncorrectable (198) sectors, reported uncorrectable errors (187), power-on hours (9),
  # and SSD wear (177 Samsung, 202 Micron, 231 and 233 others).
  STORAGE_HEALTH = '/var/lib/amahi-kai/storage-health.json'

  SMART_ATTRIBUTES = [5, 9, 177, 187, 197, 198, 202, 231, 233].freeze

  SMART_ASLEEP = 9 # smartctl's exit status for a spun-down drive, which it doesn't wake (-n standby,9)

  SMARTD_UNIT = 'smartmontools.service'


  add_operations(
    # ext4 on a data drive that isn't mounted. Never a drive the system runs from.
    'disks.format' => {
      params: %w[device],
      validate: ->(a) { { device: unmounted_data_device(a['device']).first.tap { |device| not_held!(device, 'format it') } } },
      plan: ->(v) { [['/usr/sbin/mkfs.ext4', '-F', v[:device]], ['/usr/bin/udevadm', 'settle', { allow_failure: true }]] }
    },
    # Mounts a data drive at /mnt/<name> and adds it to fstab (by UUID) if it isn't
    # there yet. Replies with the mount point.
    'disks.mount' => {
      params: %w[device mount_point],
      validate: ->(a) { mount_request(a['device'], a['mount_point']) },
      plan: ->(v) { [[:mount_drive, v[:device], v[:mount_point], v[:fstype], v[:uuid]]] }
    },
    # Unmounts a data drive and removes its fstab line; an empty /mnt/storage-N goes too.
    'disks.unmount' => {
      params: %w[device],
      validate: ->(a) { unmount_request(a['device']) },
      plan: ->(v) { [[:unmount_drive, v[:mount_points], v[:uuid]]] }
    },
    # Data drives and the share root mounted nosuid,nodev (see MOUNT_OPTIONS): the fstab lines
    # Amahi-kai wrote before get the options (the new file is checked first, and the old one
    # kept as /etc/fstab.amahi-backup), and what's mounted now is remounted with them; the share
    # root is made root's (do_secure_share_root). System Update runs it every time, and the
    # installer once; it changes nothing that's in place.
    'disks.secure_mounts' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:secure_fstab], [:secure_mounts], [:secure_share_root]] }
    },
    # Lists the top level of an unmounted data drive, mounted read-only for the moment.
    'disks.preview' => {
      params: %w[device],
      validate: ->(a) { preview_request(a['device']) },
      plan: ->(v) { [[:preview_drive, v[:device], v[:fstype]]] }
    },
    # Each whole disk's temperature, from its SMART data (the Disks page). Read-only; a disk
    # without SMART, such as a virtual disk, reports nil.
    'disks.temperatures' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:drive_temperatures]] }
    },
    # Lets smartd start in a virtual machine (SMARTD_DROPIN), and runs it, now and at boot, while
    # a drive has SMART to watch (follow_need): without one it would fail at every start. Run by
    # the installer and at every System Update; the storage check follows the drives after that.
    'smart.setup' => {
      params: [],
      validate: ->(_a) { {} },
      plan: lambda { |_v|
        [[:make_dir, File.dirname(SMARTD_DROPIN), '0755'],
         [:install, SMARTD_DROPIN, SMARTD_DROPIN_CONTENT, nil],
         %w[/usr/bin/systemctl daemon-reload],
         [:smartd_follow_need]]
      }
    },
    # The pools and every whole disk's SMART health, written to STORAGE_HEALTH for the
    # dashboard's and the Disks pages' alerts: amahi-kai-storage-check.timer runs it every
    # 15 minutes, and Disks → ZFS Pools has Check now. Spun-down drives aren't woken.
    'storage.check_health' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:check_health]] }
    },
  )

  class << self
    # --- Data drives ---

    # A whole disk or partition that is a data drive: everything mounted from its disk
    # (partitions, LVM or RAID volumes, swap) is under /mnt. A drive with anything
    # mounted elsewhere is the one the system runs from, or was set up by hand.
    # Returns [device, its lsblk node].
    def data_device(value)
      value = string(value, 'device', max: 64)
      raise Refused, "#{value.inspect} is not a disk or partition Amahi-kai manages" unless value.match?(DISK_DEVICE)
      raise Refused, "#{value} doesn't exist" unless File.blockdev?(value)
      disk, node = locate_device(block_tree, value)
      raise Refused, "lsblk doesn't list #{value}" unless node
      system_mounts = mountpoints(disk).reject { |mp| mp.start_with?("#{MNT}/") }
      raise Refused, "#{value} is on a disk the system uses (#{system_mounts.first} is mounted from it)" if system_mounts.any?
      raise Refused, "#{value} is on a disk that holds a ZFS pool (Disks → ZFS Pools)" if zfs_disk?(disk)
      [value, node]
    end

    # Anything on the disk carries a ZFS label: it's in a pool, or was. Drives like that are
    # never formatted or mounted as share storage.
    def zfs_disk?(node)
      node['fstype'] == 'zfs_member' || (node['children'] || []).any? { |child| zfs_disk?(child) }
    end

    def unmounted_data_device(value)
      device, node = data_device(value)
      mounted = mountpoints(node)
      raise Refused, "#{device} is mounted at #{mounted.first}; unmount it first" if mounted.any?
      [device, node]
    end

    def mount_request(device, mount_point)
      device, = unmounted_data_device(device)
      info = probe(device)
      fstype = mountable_fstype(device, info)
      mount_point = new_mount_point(mount_point)
      owner = fstab_entries.find { |fields| fields[1] == mount_point && fields[0] != "UUID=#{info['UUID']}" }
      raise Refused, "#{mount_point} belongs to another drive in /etc/fstab (#{owner[0]})" if owner
      # A drive that comes back goes where its fstab line says: Greyhole and the shares on it
      # look for it there, and the line would mount it there at the next boot anyway.
      home = info['UUID'] && fstab_entries.find { |fields| fields[0] == "UUID=#{info['UUID']}" && fields[1] != mount_point }
      raise Refused, "#{device} belongs at #{home[1]} (its line in /etc/fstab); mount it there" if home
      { device: device, mount_point: mount_point, fstype: fstype, uuid: info['UUID'] }
    end

    def unmount_request(device)
      device, node = data_device(device)
      mounted = mountpoints(node)
      raise Refused, "#{device} isn't mounted" if mounted.empty?
      # Greyhole keeps files there: out from under it, its copies would be missing, and a
      # drive formatted and mounted back is a stranger to it.
      pooled = (mounted & greyhole_drives).first
      raise Refused, "#{pooled} is one of Greyhole's drives; remove it from the pool on Disks → Greyhole Pool first" if pooled
      no_shares_on_drive!(mounted)
      not_held!(device, 'unmount it')
      { device: device, mount_points: mounted, uuid: probe(device)['UUID'] }
    end

    # A drive with a share's folder on it isn't unmounted: Samba would serve the empty folder
    # left on the system disk, and the next drive mounted there would take the share's place.
    def no_shares_on_drive!(mount_points)
      on = samba_shares.values.select do |share|
        mount_points.any? { |mp| share[:path] == mp || share[:path].to_s.start_with?("#{mp}/") }
      end.map { |share| share[:name] }.sort
      return if on.empty?

      raise Refused, "#{on.size == 1 ? 'the share' : 'the shares'} #{on.join(', ')} #{on.size == 1 ? 'is' : 'are'} on this drive: " \
                     "delete #{on.size == 1 ? 'it' : 'them'} on Shares first"
    end

    def preview_request(device)
      device, = unmounted_data_device(device)
      not_held!(device, 'preview it')
      { device: device, fstype: mountable_fstype(device, probe(device)) }
    end

    # An app's container keeps the mounts it was made with, in its own view of them: a drive
    # unmounted here is still in use there, and can't be previewed or formatted. Says which app.
    def not_held!(device, doing)
      holders = drive_holders(device)
      return if holders.empty?

      raise Refused, "#{device} is still in use by #{holder_labels(holders)}, which has folders on it mounted: " \
                     "restart or stop it on Apps, then #{doing}"
    end

    def holder_labels(holders)
      holders.map { |name| name.start_with?('amahi-') ? "the app #{name.delete_prefix('amahi-')}" : name }.join(' and ')
    end

    # The containers (or other programs) that have the filesystem on +device+ mounted in a view
    # of the mounts other than this one's: ["amahi-bittube"].
    def drive_holders(device)
      stat = File.stat(device)
      return [] unless stat.blockdev?

      id = "#{stat.rdev_major}:#{stat.rdev_minor}"
      holder_names(holding_views { |fields| fields[2] == id })
    rescue SystemCallError
      []
    end

    # The other views of the mounts with a mount the block picks (from its mountinfo fields)
    # that is their own. Services systemd sandboxes (logind, mariadb, udevd...) see copies of
    # this view's mounts that follow them (master:<the peer group>), so an unmount here takes
    # their copies along and they hold nothing; an app container's bind mounts are its own.
    def holding_views(&pick)
      groups = system_peer_groups
      other_mount_views.select do |view|
        view[:mountinfo].each_line.any? do |line|
          fields = line.split
          pick.call(fields) && !follows_system?(fields, groups)
        end
      end
    end

    # Whether a mountinfo line's propagation tags (shared:N, master:N, between its options and
    # the "-") name one of the system's peer groups.
    def follows_system?(fields, groups)
      tags = fields[6...(fields.index('-') || fields.size)] || []
      tags.any? { |tag| (group = tag[/\A(?:shared|master):(\d+)\z/, 1]) && groups.include?(group) }
    end

    # The peer groups of the system's own mounts (shared:N in pid 1's mountinfo): ["45", ...].
    def system_peer_groups
      File.read('/proc/1/mountinfo').scan(/ shared:(\d+)/).flatten.uniq
    rescue SystemCallError
      []
    end

    # Each view's container ("amahi-bittube"), or its program when it isn't one.
    def holder_names(views)
      return [] if views.empty?

      names = container_names
      views.map { |view| names[view[:cgroup][%r{docker[-/]([0-9a-f]{64})}, 1]] || view[:comm] }.uniq
    end

    # One process's view of the mounts per mount namespace other than the system's (pid 1's):
    # [{ mountinfo:, cgroup:, comm: }].
    def other_mount_views
      host = File.readlink('/proc/1/ns/mnt')
      seen = {}
      Dir.glob('/proc/[0-9]*').filter_map do |dir|
        namespace = File.readlink("#{dir}/ns/mnt")
        next if namespace == host || seen[namespace]

        seen[namespace] = true
        { mountinfo: File.read("#{dir}/mountinfo"), cgroup: File.read("#{dir}/cgroup"), comm: File.read("#{dir}/comm").strip }
      rescue SystemCallError
        nil # gone meanwhile
      end
    end

    # { full id => name } for the running containers; {} without Docker.
    def container_names
      return {} unless File.executable?(DOCKER)

      capture([DOCKER, 'ps', '--no-trunc', '--format', '{{.ID}} {{.Names}}']).lines.to_h { |line| line.split(' ', 2).map(&:strip) }
    rescue Failed
      {}
    end

    def mountable_fstype(device, info)
      fstype = info['TYPE'] or raise Refused, "#{device} has no filesystem; format it first"
      raise Refused, "#{device} holds #{fstype}, which Amahi-kai doesn't mount" unless MOUNTABLE_FS.include?(fstype)
      fstype
    end

    # /mnt/<name>: a real, empty folder that isn't a mount point yet, or a new one.
    def new_mount_point(value)
      value = string(value, 'mount_point', max: 128)
      name = value[%r{\A#{MNT}/([^/]+)\z}, 1]
      raise Refused, "mount point #{value.inspect} must be #{MNT}/<name> (letters, digits, . _ -)" unless name&.match?(MOUNT_NAME)
      raise Refused, "#{MNT} must be a real folder" unless File.realpath(MNT) == MNT
      return value unless File.exist?(value) || File.symlink?(value)
      raise Refused, "#{value} is not a folder" unless File.lstat(value).directory?
      raise Refused, "#{value} is already a mount point" if mount_point?(value)
      raise Refused, "#{value} isn't empty" unless Dir.empty?(value)
      value
    end

    def drives_root
      DRIVES_ROOT
    end

    # [old, new]: fstab with +line+ after its last one, even when the file doesn't end in a line
    # break. The new file is checked as the others are (fstab_check!).
    def fstab_with(line)
      old = File.read(FSTAB)
      new = old.empty? || old.end_with?("\n") ? "#{old}#{line}\n" : "#{old}\n#{line}\n"
      fstab_check!(old, new)
      [old, new]
    end

    # Mounts the drive, then adds its fstab line, which is checked before anything is mounted.
    def do_mount_drive(device, mount_point, fstype, uuid)
      created = !File.exist?(mount_point)
      Dir.mkdir(mount_point, 0o755) if created
      protect_mount_point(mount_point)
      begin
        ownerless = OWNERLESS_FS.include?(fstype) ? ownerless_options : []
        if uuid && fstab_entries.none? { |fields| fields[0] == "UUID=#{uuid}" }
          type = fstype == 'ntfs' ? 'ntfs-3g' : fstype
          fstab = fstab_with("UUID=#{uuid} #{mount_point} #{type} #{[FSTAB_OPTIONS, *ownerless].join(',')} 0 2")
        end
        run_command(['/usr/bin/mount', *(fstype == 'ntfs' ? %w[-t ntfs-3g] : []), '-o', (MOUNT_OPTIONS + ownerless).join(','),
                     device, mount_point])
        raise Failed, "#{device} didn't mount at #{mount_point}" unless mount_point?(mount_point)
      rescue Failed
        if created && !mount_point?(mount_point)
          unprotect_mount_point(mount_point)
          Dir.rmdir(mount_point)
        end
        raise
      end
      replace_fstab(*fstab) if fstab
      { 'mount_point' => mount_point }
    end

    # The users group owns everything on a FAT or exFAT drive (see OWNERLESS_FS).
    def ownerless_options
      gid = group_id(USERS_GROUP) or raise Failed, "the #{USERS_GROUP} group doesn't exist"
      ["gid=#{gid}", *OWNERLESS_MASKS]
    end

    def do_unmount_drive(mount_points, uuid)
      mount_points.each { |mp| run_command(['/usr/bin/umount', mp]) }
      remove_fstab_lines("UUID=#{uuid}") if uuid
      mount_points.each do |mp|
        next unless mp.start_with?("#{MNT}/storage-") && Dir.empty?(mp)

        unprotect_mount_point(mp)
        Dir.rmdir(mp)
      rescue SystemCallError
        nil
      end
      nil
    end

    # A data drive's mount point, an empty folder on the system disk, is made immutable (chattr
    # +i) while nothing is mounted on it: the drive mounted there covers it as usual, and while
    # the drive is missing nothing can put files in it on the system disk, as Greyhole did (its
    # metadata backups). Greyhole's job remakes that folder every minute while a pool drive is
    # missing, so an empty one of those is removed first; anything else in the way is left, and
    # the folder isn't protected. True when it was.
    def protect_mount_point(path)
      return false unless File.executable?(CHATTR) && File.lstat(path).directory? && !mount_point?(path)

      stray = File.join(path, GREYHOLE_METASTORE_BACKUP)
      Dir.rmdir(stray) if Dir.children(path) == [GREYHOLE_METASTORE_BACKUP] && File.lstat(stray).directory? && Dir.empty?(stray)
      return false unless Dir.empty?(path)

      run_command([CHATTR, '+i', path, { allow_failure: true }])
      true
    rescue SystemCallError, Failed
      false # never in the way of the mount itself
    end

    # Before an empty mount point is removed.
    def unprotect_mount_point(path)
      return unless File.executable?(CHATTR) && File.lstat(path).directory?

      run_command([CHATTR, '-i', path, { allow_failure: true }])
    rescue SystemCallError, Failed
      nil
    end

    # Rewrites fstab without the lines for +source+, keeping a copy of the old one as
    # /etc/fstab.amahi-backup.
    def remove_fstab_lines(source)
      old = File.read(FSTAB)
      new = old.lines.reject { |line| line.split.first == source }.join
      return if new == old
      replace_fstab(old, new)
    end

    def replace_fstab(old, new)
      File.write("#{FSTAB}.amahi-backup", old)
      do_install(FSTAB, new, nil, format('%o', File.stat(FSTAB).mode & 0o7777))
    end

    # The data drive lines Amahi-kai wrote before MOUNT_OPTIONS get them, and the share root's
    # bind mount is added once. A bad fstab can stop the NAS booting, so the new file must
    # parse, and findmnt --verify must find no error in it that the old one didn't have (an
    # unplugged drive is an error either way, which nofail is there for).
    def do_secure_fstab
      old = File.read(FSTAB)
      changed = 0
      new = old.lines.map do |line|
        fields = line.split
        drive = fields.size == 6 && fields[0].start_with?('UUID=') && fields[1].start_with?("#{MNT}/") &&
                (MOUNTABLE_FS + ['ntfs-3g']).include?(fields[2]) && fields[3] == FSTAB_OPTIONS_BEFORE
        next line unless drive
        changed += 1
        "#{fields[0]} #{fields[1]} #{fields[2]} #{FSTAB_OPTIONS} #{fields[4]} #{fields[5]}\n"
      end.join
      bind = fstab_entries.none? { |fields| fields[0] == SHARE_ROOT && fields[1] == SHARE_ROOT }
      new = "#{new.chomp}\n#{SHARE_ROOT_FSTAB}\n" if bind
      return { 'fstab_changed' => 0 } if new == old
      fstab_check!(old, new)
      replace_fstab(old, new)
      { 'fstab_changed' => changed + (bind ? 1 : 0) }
    end

    def fstab_check!(old, new)
      bad = new.lines.find { |line| !(line.strip.empty? || line.start_with?('#') || line.split.size.between?(4, 6)) }
      raise Failed, "the new fstab has a bad line: #{bad.strip}" if bad
      return unless File.executable?(FINDMNT)
      before, after = [old, new].map { |text| fstab_errors(text) }
      fresh = after - before
      raise Failed, "the new fstab has errors the old one didn't: #{fresh.join('; ')}" if fresh.any?
    end

    # findmnt --verify's errors for an fstab's text, each with the mount point it's under
    # (findmnt prints the mount point, then its findings indented), so one drive's error
    # doesn't stand in for another's.
    def fstab_errors(text)
      Dir.mktmpdir('amahi-fstab-', RUN_DIR) do |dir|
        path = "#{dir}/fstab"
        File.write(path, text)
        out, _err, _status = Open3.capture3(ENV_MIN, [FINDMNT, FINDMNT], '--verify', '--tab-file', path, unsetenv_others: true, chdir: '/')
        target = nil
        out.lines.filter_map do |line|
          target = line.strip unless line.start_with?(' ', "\t") || line.strip.empty?
          "#{target}: #{line.strip}" if line.strip.start_with?('[E]')
        end
      end
    end

    # Remounts the data drives whose fstab line has MOUNT_OPTIONS but whose mount doesn't yet,
    # and makes the share root a bind mount of itself with them.
    def do_secure_mounts
      remounted = []
      protected = []
      fstab_entries.each do |fields|
        next unless fields[1].start_with?("#{MNT}/") && fields[3].to_s.split(',').include?(MOUNT_OPTIONS.first)
        # A drive missing now: its mount point can't take files meanwhile
        unless mount_point?(fields[1])
          protected << fields[1] if protect_mount_point(fields[1])
          next
        end
        next if secured?(fields[1])
        run_command(['/usr/bin/mount', '-o', "remount,#{MOUNT_OPTIONS.join(',')}", fields[1]])
        remounted << fields[1]
      end
      if File.directory?(SHARE_ROOT) && !File.symlink?(SHARE_ROOT)
        run_command(['/usr/bin/mount', '--bind', SHARE_ROOT, SHARE_ROOT]) if mount_options(SHARE_ROOT).empty?
        unless secured?(SHARE_ROOT)
          run_command(['/usr/bin/mount', '-o', "remount,bind,#{MOUNT_OPTIONS.join(',')}", SHARE_ROOT])
          remounted << SHARE_ROOT
        end
        raise Failed, "#{SHARE_ROOT} isn't mounted #{MOUNT_OPTIONS.join(',')}" unless secured?(SHARE_ROOT)
      end
      { 'remounted' => remounted, 'protected' => protected }
    end

    def secured?(path)
      (MOUNT_OPTIONS - mount_options(path)).empty?
    end

    # The share root is root's, 0755: the web app's account owned it, so it could have put a link
    # in place of a share's folder there, and an app given that share would get whatever it
    # pointed to. The share folders in it stay the app's (shares.create_dir).
    def do_secure_share_root
      return nil unless File.directory?(SHARE_ROOT) && !File.symlink?(SHARE_ROOT)

      stat = File.lstat(SHARE_ROOT)
      return nil if stat.uid.zero? && stat.gid.zero? && (stat.mode & 0o7777) == 0o755

      with_dir(SHARE_ROOT) do |dir|
        dir.chown(0, 0)
        dir.chmod(0o755)
      end
      { 'share_root' => 'root:root 0755' }
    end

    # The options of the mount at +path+ (the newest, when several), from /proc/self/mounts;
    # empty when nothing is mounted there. (mount_point? can't see a folder bound onto itself.)
    def mount_options(path, mounts_file = '/proc/self/mounts')
      entry = File.readlines(mounts_file).map(&:split).select { |fields| fields[1] == path }.last
      entry ? entry[3].to_s.split(',') : []
    rescue SystemCallError
      []
    end

    def do_preview_drive(device, fstype)
      dir = Dir.mktmpdir('amahi-preview-', RUN_DIR)
      options = %w[ro nosuid nodev noexec]
      options << 'noload' if %w[ext3 ext4].include?(fstype) # don't replay the journal
      options << 'norecovery' if fstype == 'xfs'
      options << 'rescue=nologreplay' if fstype == 'btrfs' # ro alone still replays its log
      run_command(['/usr/bin/mount', *(fstype == 'ntfs' ? %w[-t ntfs-3g] : []), '-o', options.join(','), device, dir])
      begin
        directory_summary(dir)
      ensure
        run_command(['/usr/bin/umount', dir, { allow_failure: true }])
      end
    ensure
      Dir.rmdir(dir) if dir && !mount_point?(dir)
    end

    # { 'checked_at', 'smartctl' (installed?), 'drives' => { '/dev/sda' => SMART summary or
    # nil }, and pools.status's 'zfs' and 'pools' }, saved to STORAGE_HEALTH (root:amahi 0640).
    def do_check_health
      previous = read_json(STORAGE_HEALTH) || {}
      disks = block_tree.select { |d| d['type'] == 'disk' }.map { |d| d['path'] }.grep(WHOLE_DISK)
      health = { 'checked_at' => Time.now.utc.iso8601, 'smartctl' => File.executable?(SMARTCTL),
                 'drives' => disks.to_h { |disk| [disk, drive_health(disk, previous.dig('drives', disk))] } }
      health.merge!(do_pool_status(false)) # every 15 minutes: no scan of the drives, which would wake them
      do_install(STORAGE_HEALTH, "#{JSON.pretty_generate(health)}\n", nil, '0640', APP_USER)
      do_smartd_follow_need(health['drives'])
      { 'health' => health }
    end

    # --- Services that run only while they have work ---
    #
    # smartd while a drive has SMART to watch, Greyhole while its pool has a drive (and it isn't
    # switched off): each would otherwise start with nothing to do, fail, and be listed as failed
    # at every boot. Each is switched on (enabled and started) when it gets work, and off
    # (disabled, stopped, its failure forgotten) when it has none; otherwise it's left as it is,
    # so a stop on Settings → Servers lasts until the next restart, as for every service.

    # +drives+: { disk => its SMART data, or nil } as the storage check read them; read now when
    # not given (smart.setup).
    def do_smartd_follow_need(drives = nil)
      return nil unless File.executable?(SMARTCTL)

      drives ||= block_tree.select { |d| d['type'] == 'disk' }.map { |d| d['path'] }.grep(WHOLE_DISK).to_h { |disk| [disk, drive_health(disk, nil)] }
      { 'smartd' => follow_need(SMARTD_UNIT, drives.values.any?(Hash)) }
    end

    # One drive's SMART data from `smartctl --json -i -H -A` (at most 10 seconds): see
    # smart_summary. nil without smartctl, or for a drive without SMART (virtual disks). A
    # spun-down drive isn't woken: it keeps what was read last, marked asleep.
    def drive_health(disk, previous)
      return nil unless File.executable?(SMARTCTL)
      out, _err, status = Open3.capture3(ENV_MIN, ['/usr/bin/timeout', '/usr/bin/timeout'], '10', SMARTCTL, '--json',
                                         '-n', "standby,#{SMART_ASLEEP}", '-i', '-H', '-A', disk,
                                         unsetenv_others: true, chdir: '/')
      return (previous || {}).merge('asleep' => true) if status.exitstatus == SMART_ASLEEP
      smart_summary(JSON.parse(out))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # What the app's alerts need from smartctl's JSON: the drive's model, serial and
    # firmware, whether its own health check passed, power-on hours, temperature, whether
    # it's an SSD, the SMART_ATTRIBUTES (normalized value, threshold, raw count) and NVMe's
    # health log.
    def smart_summary(data)
      passed = data.dig('smart_status', 'passed')
      table = Array(data.dig('ata_smart_attributes', 'table')).select { |a| SMART_ATTRIBUTES.include?(a['id']) }
      nvme = data['nvme_smart_health_information_log']
      return nil if passed.nil? && table.empty? && nvme.nil?

      { 'model' => data['model_name'], 'serial' => data['serial_number'], 'firmware' => data['firmware_version'],
        'passed' => passed, 'power_on_hours' => data.dig('power_on_time', 'hours'),
        'temperature' => data.dig('temperature', 'current'), 'ssd' => data['rotation_rate'] == 0 || !nvme.nil?,
        'attributes' => table.to_h do |a|
          [a['id'].to_s, { 'name' => a['name'], 'value' => a['value'], 'thresh' => a['thresh'], 'raw' => a.dig('raw', 'value') }]
        end,
        'nvme' => nvme&.slice('critical_warning', 'percentage_used', 'media_errors', 'available_spare', 'available_spare_threshold') }
    end

    def device_name(path)
      File.realpath(path)
    rescue SystemCallError
      path # a missing drive: zpool shows the path it was last seen at
    end

    # { 'temperatures' => { '/dev/sda' => 34, '/dev/vda' => nil }, 'asleep' => ['/dev/sdc'] } for
    # the whole disks lsblk lists. A spun-down drive isn't woken for it: it has no temperature
    # and is listed as asleep.
    def do_drive_temperatures
      disks = block_tree.select { |d| d['type'] == 'disk' }.map { |d| d['path'] }.grep(WHOLE_DISK)
      readings = disks.to_h { |disk| [disk, drive_temperature(disk)] }
      { 'temperatures' => readings.transform_values { |value| value == :asleep ? nil : value },
        'asleep' => readings.select { |_disk, value| value == :asleep }.keys }
    end

    # smartctl's exit status is a bit mask that is often non-zero on healthy drives, so its
    # output is read whatever the status, unless it's the one for a sleeping drive (:asleep).
    # At most 5 seconds per disk.
    def drive_temperature(disk)
      out, _err, status = Open3.capture3(ENV_MIN, ['/usr/bin/timeout', '/usr/bin/timeout'], '5', SMARTCTL,
                                         '-n', "standby,#{SMART_ASLEEP}", '-A', disk, unsetenv_others: true, chdir: '/')
      return :asleep if status.exitstatus == SMART_ASLEEP
      TEMPERATURE_PATTERNS.each do |pattern|
        value = out[pattern, 1]
        return value.to_i if value
      end
      nil
    rescue SystemCallError
      nil
    end

    # Top-level entries with sizes and file counts, walking at most PREVIEW_LIMIT.
    def directory_summary(dir)
      started = Time.now
      walked = 0
      partial = false
      entries = Dir.children(dir).sort.reject { |name| name.start_with?('.') || name == 'lost+found' }.map do |name|
        path = File.join(dir, name)
        stat = File.lstat(path)
        entry = { 'name' => name.dup.force_encoding('UTF-8').scrub('?'), 'type' => stat.directory? ? 'directory' : 'file',
                  'size' => stat.directory? ? 0 : stat.size, 'file_count' => stat.directory? ? 0 : 1 }
        next entry unless stat.directory?
        Find.find(path) do |inner|
          walked += 1
          if walked > PREVIEW_LIMIT[:entries] || Time.now - started > PREVIEW_LIMIT[:seconds]
            partial = true
            break
          end
          inner_stat = File.lstat(inner)
          next unless inner_stat.file?
          entry['size'] += inner_stat.size
          entry['file_count'] += 1
        rescue SystemCallError
          next
        end
        entry
      end
      { 'entries' => entries, 'total_used' => entries.sum { |e| e['size'] },
        'file_count' => entries.sum { |e| e['file_count'] }, 'partial' => partial }
    end

    # lsblk's device tree (as root it sees everything; as anyone it sees mount points): disks
    # at the top, their partitions, LVM, RAID and encrypted volumes nested in 'children'.
    # lsblk only nests them when NAME is the first column; otherwise it lists every device
    # flat, and a disk would seem to have nothing on it. The drive checks depend on the
    # nesting, so a flat list is refused rather than read.
    def block_tree
      tree = JSON.parse(capture(['/usr/bin/lsblk', '-J', '-o', 'NAME,PATH,TYPE,FSTYPE,MOUNTPOINTS']))['blockdevices'] || []
      flat = tree.find { |node| node['type'] == 'part' || node['type'] == 'lvm' || node['type'].to_s.start_with?('raid', 'crypt') }
      raise Failed, "lsblk listed #{flat['path']} on its own, not under its disk" if flat
      tree
    rescue JSON::ParserError
      raise Failed, "couldn't read lsblk's output"
    end

    # [top-level disk, node] for +device+ in +tree+, or [nil, nil].
    def locate_device(tree, device)
      tree.each do |disk|
        node = find_node(disk, device)
        return [disk, node] if node
      end
      [nil, nil]
    end

    def find_node(node, device)
      return node if node['path'] == device
      (node['children'] || []).each do |child|
        found = find_node(child, device)
        return found if found
      end
      nil
    end

    # Every mount point in +node+'s subtree ("[SWAP]" included).
    def mountpoints(node)
      [*Array(node['mountpoints']).compact, *(node['children'] || []).flat_map { |c| mountpoints(c) }].uniq
    end

    # blkid's low-level probe of the device itself (not the cache): TYPE, UUID, ...
    def probe(device)
      out, _err, status = Open3.capture3(ENV_MIN, ['/usr/sbin/blkid', '/usr/sbin/blkid'], '-p', '-o', 'export', device,
                                         unsetenv_others: true, chdir: '/')
      return {} unless status.success? # exit 2: nothing found
      out.lines.to_h { |line| line.chomp.split('=', 2) }
    end

    def fstab_entries
      File.readlines(FSTAB).map(&:split).reject { |fields| fields.empty? || fields[0].start_with?('#') }
    end

    def mount_point?(path)
      File.stat(path).dev != File.stat(File.dirname(path)).dev
    rescue SystemCallError
      false
    end
  end
end
