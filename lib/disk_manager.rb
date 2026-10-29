require 'json'
require 'shell'

# Lists drives, their temperatures and what's mounted, and formats, mounts, unmounts and
# previews data drives. The changes are made by the root helper (disks.* operations), which
# checks the drive itself: it refuses any drive with something mounted outside /mnt (the OS
# disk) and writes fstab lines as
# UUID=... /mnt/<name> <type> defaults,nofail,x-systemd.device-timeout=10s 0 2.
# Commands run as argument lists (Shell.output), never through a shell.
class DiskManager
  VALID_DEVICE_PATTERN = %r{\A/dev/[svx]d[a-z]+\d*\z}
  VALID_NVME_PATTERN = %r{\A/dev/nvme\d+n\d+(p\d+)?\z}
  # udev's links for each drive and partition, named for its model and serial (or WWN), which stay
  # with it whatever name the kernel gives it at boot or when it's plugged in. The pages name a
  # drive by one (its :ref), so a page left open acts on that drive, or on none, never on whichever
  # drive has its old kernel name now (resolve).
  BY_ID = '/dev/disk/by-id'.freeze
  BY_ID_NAME = /\A[\w.:@+=-]{1,200}\z/
  BY_ID_PREFERENCE = %w[ata- nvme- scsi- usb- wwn- virtio-].freeze

  class DiskError < StandardError
    include ReportableError
  end

  # Detect all block devices with partition info
  # Outside production, a machine without lsblk's answer gets the sample drives. In production
  # that would offer drives that aren't there, and a request for one acts on whatever real drive
  # has its name, so it's an error.
  def self.devices
    raw = lsblk_json
    if raw.blank?
      raise DiskError.new("Couldn't list the drives (lsblk gave no answer)", failed: true) if production?

      return sample_devices
    end

    begin
      data = JSON.parse(raw)
    rescue JSON::ParserError
      raise DiskError.new("Couldn't read lsblk's list of the drives", failed: true) if production?

      return sample_devices
    end

    devices = []
    refs = by_id_refs
    homes = fstab_sources
    (data["blockdevices"] || []).each do |dev|
      next unless dev["type"] == "disk"

      device_path = "/dev/#{dev['name']}"
      children = dev["children"] || []

      # home: where the drive's fstab line mounts it (a drive that was mounted before, missing or
      # not), or nil
      partitions = children.map do |part|
        part_path = "/dev/#{part['name']}"
        {
          name: part["name"],
          path: part_path,
          ref: refs[part_path] || part_path,
          size: part["size"],
          fstype: part["fstype"],
          mountpoint: part["mountpoint"],
          uuid: part["uuid"],
          home: part["uuid"] && homes["UUID=#{part['uuid']}"],
          status: partition_status(part)
        }
      end

      # If disk has no partitions, treat the disk itself as a formattable unit
      if children.empty?
        partitions = [{
          name: dev["name"],
          path: device_path,
          ref: refs[device_path] || device_path,
          size: dev["size"],
          fstype: dev["fstype"],
          mountpoint: dev["mountpoint"],
          uuid: dev["uuid"],
          home: dev["uuid"] && homes["UUID=#{dev['uuid']}"],
          status: partition_status(dev)
        }]
      end

      devices << {
        name: dev["name"],
        path: device_path,
        ref: refs[device_path] || device_path,
        model: dev["model"] || "Unknown",
        size: dev["size"],
        serial: dev["serial"],
        os_disk: (mountpoints_in(dev) & OS_MOUNTPOINTS).any?,
        zfs_pool: zfs_pool_in(dev),
        partitions: partitions
      }
    end

    devices
  end

  # The kernel name of the drive a page named (its :ref): a /dev/disk/by-id link is followed to
  # the drive it names now; a kernel name stays as it is (a drive with no link, such as a virtual
  # disk without a serial number).
  def self.resolve(ref)
    ref = ref.to_s
    return ref unless ref.start_with?("#{BY_ID}/")

    name = ref.delete_prefix("#{BY_ID}/")
    raise DiskError, "Invalid device path: #{ref}" unless name.match?(BY_ID_NAME)
    File.realpath(ref)
  rescue Errno::ENOENT
    raise DiskError, "#{name} isn't connected any more: reload the page"
  rescue SystemCallError => e
    raise DiskError, "#{name} can't be found: #{e.message}"
  end

  # { '/dev/sdb' => '/dev/disk/by-id/ata-Samsung_SSD_870_S6P...', '/dev/sdb1' => '...-part1' }: a
  # link for each drive and partition that has one, a model-and-serial name before a WWN.
  def self.by_id_refs
    names = Dir.children(BY_ID).select { |name| name.match?(BY_ID_NAME) }
    names.sort_by { |name| [BY_ID_PREFERENCE.index { |prefix| name.start_with?(prefix) } || BY_ID_PREFERENCE.size, name] }
         .each_with_object({}) do |name, refs|
      link = File.join(BY_ID, name)
      refs[File.realpath(link)] ||= link
    rescue SystemCallError
      next # gone meanwhile
    end
  rescue SystemCallError
    {}
  end

  # { 'UUID=...' => '/mnt/storage-2', ... }: each fstab line's source and mount point.
  def self.fstab_sources
    fstab = File.read("/etc/fstab") rescue ""
    fstab.lines.map(&:split).reject { |f| f.size < 2 || f[0].start_with?("#") }.to_h { |f| f.first(2) }
  end

  # Format a device as ext4.
  def self.format_disk!(device)
    device = resolve(device)
    validate_device!(device)
    raise DiskError, "Cannot format OS disk!" if os_disk?(device)
    privileged('disks.format', device: device)
    true
  end

  # Mount a partition at +mount_point+ and add it to fstab. Returns the mount point. By default
  # a drive mounted before goes back where its fstab line says (Greyhole, and the shares on it,
  # look for it there), and any other at the next free /mnt/storage-N.
  def self.mount!(device, mount_point = nil)
    device = resolve(device)
    validate_device!(device)
    raise DiskError, "Cannot mount OS disk partition this way!" if os_disk?(device)

    mount_point ||= devices.flat_map { |d| d[:partitions] }.find { |p| p[:path] == device }&.dig(:home) || auto_mount_point
    reply = privileged('disks.mount', device: device, mount_point: mount_point)
    reply['mount_point'] || mount_point
  end

  # Unmount a partition and remove its fstab line.
  def self.unmount!(device)
    device = resolve(device)
    validate_device!(device)
    raise DiskError, "Cannot unmount OS disk!" if os_disk?(device)
    privileged('disks.unmount', device: device)
    true
  end

  # Preview contents of an unmounted partition.
  # The helper mounts it read-only for a moment and lists the top level with sizes.
  # Returns hash with :entries (array), :total_used, :file_count, and :partial when the helper
  # stopped counting (PREVIEW_LIMIT: the totals are at least that)
  def self.preview(device)
    device = resolve(device)
    validate_device!(device)
    raise DiskError, "Cannot preview OS disk!" if os_disk?(device)

    # Check it has a filesystem
    devices_list = devices
    part = devices_list.flat_map { |d| d[:partitions] }.find { |p| p[:path] == device }
    raise DiskError, "Device not found: #{device}" unless part
    raise DiskError, "No filesystem on #{device} — nothing to preview" if part[:status] == :unformatted

    # If already mounted, just read it
    if part[:status] == :mounted && part[:mountpoint].present?
      return read_directory_summary(part[:mountpoint])
    end
    return sample_preview unless production?

    reply = privileged('disks.preview', device: device)
    entries = Array(reply['entries']).map do |e|
      { name: e['name'], type: e['type'] == 'directory' ? :directory : :file, size: e['size'].to_i, file_count: e['file_count'].to_i }
    end
    { entries: entries, total_used: reply['total_used'].to_i, file_count: reply['file_count'].to_i, partial: reply['partial'] == true }
  end

  # Check if a device is the OS disk
  def self.os_disk?(device)
    # Stripping trailing digits turned /dev/nvme0n1p2 into /dev/nvme0n1p, which
    # matched no disk, so NVMe partitions on the OS disk passed this check.
    base = base_device(device)
    all = devices
    dev = all.find { |d| d[:path] == base || d[:path] == device }
    return false unless dev
    dev[:os_disk]
  end

  # The drives with their temperatures in °F, for Disks' overview (nil: the drive doesn't say, or
  # it's asleep, spun down, and isn't woken for it). The colour follows the drive's own °C: warm
  # from 40, hot from 50.
  def self.stats
    temperatures, asleep = drive_temperatures
    devices.map do |disk|
      temp = temperatures[disk[:path]].to_i
      {
        device: disk[:path],
        model: disk[:model],
        size: disk[:size],
        temp_f: temp > 0 ? ((temp * 1.8) + 32).round : nil,
        tempcolor: temp_color(temp),
        asleep: asleep.include?(disk[:path])
      }
    end
  end

  # Mounted filesystems as df lists them, without tmpfs and the like, for Disks → Mounts.
  def self.mounts
    Shell.output('df', '-BK').lines.drop(1).filter_map do |line|
      filesystem, kib, used, available, use_percent, mount = line.strip.split(/\s+/, 6)
      next if mount.nil? || %w[tmpfs devtmpfs none overlay].include?(filesystem)

      {
        filesystem: filesystem,
        bytes: kib.to_i * 1024,
        used: used.to_i * 1024,
        available: available.to_i * 1024,
        use_percent: use_percent,
        mount: mount
      }
    end.sort_by { |m| m[:filesystem] }
  end

  # Data drives mounted under /mnt (share storage), with their size and free space: the
  # drives Greyhole's pool can take (the helper refuses any other), for Disks → Greyhole Pool.
  def self.share_storage(mounts_file = '/proc/self/mounts')
    File.readlines(mounts_file).filter_map do |line|
      device, path = line.split
      next unless device&.start_with?('/dev/')

      path = path.gsub(/\\([0-7]{3})/) { Regexp.last_match(1).to_i(8).chr } # \040 is a space
      next unless path.start_with?('/mnt/')

      total, free = filesystem_space(path)
      { device: device, path: path, bytes_total: total, bytes_free: free }
    end
  rescue SystemCallError
    []
  end

  # The whole disk a device belongs to: /dev/sda1 -> /dev/sda, /dev/nvme0n1p2 -> /dev/nvme0n1.
  def self.base_device(device)
    device.match?(VALID_NVME_PATTERN) ? device.sub(/p\d+\z/, '') : device.sub(/\d+\z/, '')
  end

  OS_MOUNTPOINTS = ['/', '/boot', '/boot/efi'].freeze

  # Mount points of a block device and everything under it: partitions, and the
  # LVM or RAID volumes inside them (Ubuntu's default install puts / on LVM).
  def self.mountpoints_in(node)
    [node["mountpoint"], *(node["children"] || []).flat_map { |c| mountpoints_in(c) }].compact
  end

  # The pool named on a ZFS-labelled disk or partition, if any: such a drive belongs to
  # Disks → ZFS Pools (the helper refuses to format or mount it).
  def self.zfs_pool_in(node)
    return node["label"].presence || "unnamed" if node["fstype"] == "zfs_member"
    (node["children"] || []).each do |child|
      found = zfs_pool_in(child)
      return found if found
    end
    nil
  end

  def self.partition_status(part)
    if part["mountpoint"].present?
      :mounted
    elsif part["fstype"].present?
      :unmounted
    else
      :unformatted
    end
  end

  def self.validate_device!(device)
    unless device.match?(VALID_DEVICE_PATTERN) || device.match?(VALID_NVME_PATTERN)
      raise DiskError, "Invalid device path: #{device}"
    end
  end

  # Runs a root helper operation; its refusal or failure becomes a DiskError.
  def self.privileged(operation, **args)
    Privileged.call(operation, **args)
  rescue Privileged::Error => e
    raise ReportableError.from_privileged(DiskError, e)
  end

  def self.auto_mount_point
    # Lowest free /mnt/storage-N. A slot listed in /etc/fstab stays taken even when its
    # drive is unplugged, so a new drive never collides with one that comes back.
    claimed = fstab_mount_points
    num = 1
    loop do
      candidate = "/mnt/storage-#{num}"
      unless claimed.include?(candidate)
        # Free if the directory doesn't exist, or exists but is empty and not a mount point
        return candidate if !Dir.exist?(candidate)
        return candidate if Dir.empty?(candidate) && !mount_point_active?(candidate)
      end
      num += 1
    end
  end

  # Mount points named in /etc/fstab. (This replaces a cleanup that deleted fstab lines
  # whose UUID unprivileged blkid couldn't see, which could drop a working drive.)
  def self.fstab_mount_points
    fstab = File.read("/etc/fstab") rescue ""
    fstab.lines.map(&:split).reject { |f| f.empty? || f[0].start_with?("#") }.map { |f| f[1] }.compact
  end

  def self.mount_point_active?(path)
    Shell.success?('mountpoint', '-q', path)
  end

  def self.production?
    defined?(Rails) && Rails.env.production?
  end

  # lsblk lists partitions and volumes under their disk only when NAME is the first column.
  def self.lsblk_json
    Shell.output('lsblk', '-J', '-o', 'NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL,UUID,LABEL')
  end

  # SMART data needs root, so the helper reads it: [{ '/dev/sda' => 34, '/dev/vda' => nil }, the
  # drives asleep].
  def self.drive_temperatures
    reply = Privileged.call('disks.temperatures')
    [reply['temperatures'] || {}, Array(reply['asleep'])]
  rescue Privileged::Error => e
    Rails.logger.warn("DiskManager: #{e.message}") if defined?(Rails)
    [{}, []]
  end

  def self.temp_color(temp)
    return 'hot' if temp > 49
    return 'warm' if temp > 39

    'cool'
  end

  # A mounted filesystem's size and free space, in bytes.
  def self.filesystem_space(path)
    require 'sys/filesystem'
    stat = Sys::Filesystem.stat(path)
    [stat.block_size * stat.blocks, stat.block_size * stat.blocks_available]
  rescue StandardError => e
    Rails.logger.error("DiskManager: no size for #{path}: #{e.message}") if defined?(Rails)
    [0, 0]
  end

  def self.read_directory_summary(path)
    entries = []
    total_size = 0
    file_count = 0

    begin
      Dir.entries(path).sort.each do |name|
        next if name.start_with?('.')
        next if name == 'lost+found'
        full = File.join(path, name)
        stat = File.stat(full) rescue next

        if stat.directory?
          # The folder's size with du and its files with find (faster than Ruby recursion);
          # find prints a dot per file.
          size_str = Shell.output('du', '-sb', '--', full).split("\t").first.to_i
          count_str = Shell.output('find', full, '-type', 'f', '-printf', '.').length
          entries << { name: name, type: :directory, size: size_str, file_count: count_str }
          total_size += size_str
          file_count += count_str
        else
          entries << { name: name, type: :file, size: stat.size }
          total_size += stat.size
          file_count += 1
        end
      end
    rescue StandardError => e
      Rails.logger.error("DiskManager.read_directory_summary: #{e.message}") if defined?(Rails)
    end

    { entries: entries, total_used: total_size, file_count: file_count }
  end

  def self.sample_preview
    {
      entries: [
        { name: "Movies", type: :directory, size: 45_000_000_000, file_count: 120 },
        { name: "Music", type: :directory, size: 8_500_000_000, file_count: 2400 },
        { name: "Photos", type: :directory, size: 12_000_000_000, file_count: 8500 },
        { name: "readme.txt", type: :file, size: 1024 }
      ],
      total_used: 65_501_001_024,
      file_count: 11021
    }
  end

  def self.sample_devices
    [
      {
        name: "sda", path: "/dev/sda", model: "VBOX HARDDISK", size: "40G", serial: "VB001",
        os_disk: true,
        partitions: [
          { name: "sda1", path: "/dev/sda1", size: "512M", fstype: "vfat", mountpoint: "/boot/efi", uuid: "ABCD-1234", status: :mounted },
          { name: "sda2", path: "/dev/sda2", size: "39.5G", fstype: "ext4", mountpoint: "/", uuid: "abcd-5678-efgh", status: :mounted }
        ]
      },
      {
        name: "sdb", path: "/dev/sdb", model: "VBOX HARDDISK", size: "100G", serial: "VB002",
        os_disk: false,
        partitions: [
          { name: "sdb1", path: "/dev/sdb1", size: "100G", fstype: "ext4", mountpoint: nil, uuid: "xxxx-yyyy-zzzz", status: :unmounted }
        ]
      },
      {
        name: "sdc", path: "/dev/sdc", model: "VBOX HARDDISK", size: "200G", serial: "VB003",
        os_disk: false,
        partitions: [
          { name: "sdc", path: "/dev/sdc", size: "200G", fstype: nil, mountpoint: nil, uuid: nil, status: :unformatted }
        ]
      }
    ].each { |disk| [disk, *disk[:partitions]].each { |node| node[:ref] = node[:path] } }
  end

  private_class_method :mountpoints_in, :zfs_pool_in, :partition_status, :validate_device!,
                       :privileged, :auto_mount_point, :fstab_mount_points, :mount_point_active?,
                       :production?, :lsblk_json, :drive_temperatures, :temp_color,
                       :filesystem_space, :read_directory_summary, :sample_preview, :sample_devices
end
