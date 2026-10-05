require 'json'
require 'shellwords'
require 'shell'

# Lists drives, and formats, mounts, unmounts and previews data drives. The changes are
# made by the root helper (disks.* operations), which checks the drive itself: it
# refuses any drive with something mounted outside /mnt (the OS disk) and writes fstab
# lines as UUID=... /mnt/<name> <type> defaults,nofail,x-systemd.device-timeout=10s 0 2.
class DiskManager
  VALID_DEVICE_PATTERN = %r{\A/dev/[svx]d[a-z]+\d*\z}
  VALID_NVME_PATTERN = %r{\A/dev/nvme\d+n\d+(p\d+)?\z}

  class DiskError < StandardError; end

  # Detect all block devices with partition info
  def self.devices
    raw = execute_command("lsblk -J -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL,UUID,LABEL 2>/dev/null")
    return sample_devices if raw.blank?

    begin
      data = JSON.parse(raw)
    rescue JSON::ParserError
      return sample_devices
    end

    devices = []
    (data["blockdevices"] || []).each do |dev|
      next unless dev["type"] == "disk"

      device_path = "/dev/#{dev['name']}"
      children = dev["children"] || []

      partitions = children.map do |part|
        part_path = "/dev/#{part['name']}"
        {
          name: part["name"],
          path: part_path,
          size: part["size"],
          fstype: part["fstype"],
          mountpoint: part["mountpoint"],
          uuid: part["uuid"],
          status: partition_status(part)
        }
      end

      # If disk has no partitions, treat the disk itself as a formattable unit
      if children.empty?
        partitions = [{
          name: dev["name"],
          path: device_path,
          size: dev["size"],
          fstype: dev["fstype"],
          mountpoint: dev["mountpoint"],
          uuid: dev["uuid"],
          status: partition_status(dev)
        }]
      end

      devices << {
        name: dev["name"],
        path: device_path,
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

  # Format a device as ext4.
  def self.format_disk!(device)
    validate_device!(device)
    raise DiskError, "Cannot format OS disk!" if os_disk?(device)
    privileged('disks.format', device: device)
    true
  end

  # Mount a partition at +mount_point+ (default: the next free /mnt/storage-N) and add it
  # to fstab. Returns the mount point.
  def self.mount!(device, mount_point = nil)
    validate_device!(device)
    raise DiskError, "Cannot mount OS disk partition this way!" if os_disk?(device)

    mount_point ||= auto_mount_point
    reply = privileged('disks.mount', device: device, mount_point: mount_point)
    reply['mount_point'] || mount_point
  end

  # Unmount a partition and remove its fstab line.
  def self.unmount!(device)
    validate_device!(device)
    raise DiskError, "Cannot unmount OS disk!" if os_disk?(device)
    privileged('disks.unmount', device: device)
    true
  end

  # Preview contents of an unmounted partition.
  # The helper mounts it read-only for a moment and lists the top level with sizes.
  # Returns hash with :entries (array), :total_used, :file_count
  def self.preview(device)
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
    { entries: entries, total_used: reply['total_used'].to_i, file_count: reply['file_count'].to_i }
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

  private

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

  # The whole disk a device belongs to: /dev/sda1 -> /dev/sda, /dev/nvme0n1p2 -> /dev/nvme0n1.
  def self.base_device(device)
    device.match?(VALID_NVME_PATTERN) ? device.sub(/p\d+\z/, '') : device.sub(/\d+\z/, '')
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
    raise DiskError, e.message
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
    output = execute_command("mountpoint -q #{Shellwords.escape(path)} 2>/dev/null; echo $?")
    output.to_s.strip == "0"
  end

  def self.production?
    defined?(Rails) && Rails.env.production?
  end

  def self.execute_command(cmd)
    stdout, _stderr, _status = Shell.capture(cmd)
    stdout
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
          # Get directory size with du (faster than Ruby recursion)
          size_str = `du -sb #{Shellwords.escape(full)} 2>/dev/null`.split("\t").first.to_i
          count_str = `find #{Shellwords.escape(full)} -type f 2>/dev/null | wc -l`.strip.to_i
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
    ]
  end
end
