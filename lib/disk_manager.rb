require 'json'
require 'shellwords'
require 'shell'

class DiskManager
  VALID_DEVICE_PATTERN = %r{\A/dev/[svx]d[a-z]+\d*\z}
  VALID_NVME_PATTERN = %r{\A/dev/nvme\d+n\d+(p\d+)?\z}

  class DiskError < StandardError; end

  # Detect all block devices with partition info
  def self.devices
    raw = execute_command("lsblk -J -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL,UUID 2>/dev/null")
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
        os_disk: os_disk_from_partitions?(partitions),
        partitions: partitions
      }
    end

    devices
  end

  # Format a device as ext4
  def self.format_disk!(device)
    validate_device!(device)
    raise DiskError, "Cannot format OS disk!" if os_disk?(device)

    if production?
      execute_command("sudo /sbin/mkfs.ext4 -F #{Shellwords.escape(device)}")
    else
      Rails.logger.info("[DiskManager] SIMULATED: mkfs.ext4 -F #{device}") if defined?(Rails)
    end
    true
  end

  # Mount a partition
  def self.mount!(device, mount_point = nil)
    validate_device!(device)
    raise DiskError, "Cannot mount OS disk partition this way!" if os_disk?(device)

    mount_point ||= auto_mount_point
    uuid = get_uuid(device)
    fstype = detect_fstype(device)

    if production?
      execute_command("sudo /usr/bin/mkdir -p #{Shellwords.escape(mount_point)}")

      # Use appropriate mount type for the filesystem
      mount_cmd = "sudo /bin/mount"
      mount_cmd += " -t ntfs-3g" if fstype&.downcase == "ntfs"
      mount_cmd += " #{Shellwords.escape(device)} #{Shellwords.escape(mount_point)}"
      mount_output = `#{mount_cmd} 2>&1`
      mount_status = $?.exitstatus

      # Verify mount actually worked
      unless mount_status == 0 && mount_point_active?(mount_point)
        execute_command("sudo /usr/bin/rmdir #{Shellwords.escape(mount_point)} 2>/dev/null")
        detail = mount_output.to_s.strip.presence || "unknown error (exit #{mount_status})"
        raise DiskError, "Mount failed — #{device} at #{mount_point}: #{detail}"
      end

      # Add to fstab using UUID for persistence
      if uuid.present?
        fstab_type = (fstype&.downcase == "ntfs") ? "ntfs-3g" : (fstype.presence || "ext4")
        fstab_line = "UUID=#{uuid} #{mount_point} #{fstab_type} defaults 0 2"
        # Check if already in fstab
        fstab = File.read("/etc/fstab") rescue ""
        unless fstab.include?(uuid)
          execute_command("echo #{Shellwords.escape(fstab_line)} | sudo /usr/bin/tee -a /etc/fstab")
        end
      end
    else
      Rails.logger.info("[DiskManager] SIMULATED: mount #{device} #{mount_point}") if defined?(Rails)
    end
    mount_point
  end

  # Unmount a partition
  def self.unmount!(device)
    validate_device!(device)
    raise DiskError, "Cannot unmount OS disk!" if os_disk?(device)

    # Find current mount point
    mount_point = find_mount_point(device)
    raise DiskError, "Device #{device} is not mounted" if mount_point.blank?

    uuid = get_uuid(device)

    if production?
      execute_command("sudo /bin/umount #{Shellwords.escape(mount_point)}")
      # Remove from fstab
      if uuid.present?
        # Read fstab, filter out the line, write back
        fstab = File.read("/etc/fstab") rescue ""
        new_fstab = fstab.lines.reject { |l| l.include?(uuid) }.join
        File.write("/tmp/fstab.new", new_fstab)
        execute_command("sudo /usr/bin/cp /tmp/fstab.new /etc/fstab")
      end
      # Clean up empty mount point directory
      if mount_point.start_with?("/mnt/storage-")
        execute_command("sudo /usr/bin/rmdir #{Shellwords.escape(mount_point)} 2>/dev/null")
      end
    else
      Rails.logger.info("[DiskManager] SIMULATED: umount #{mount_point}") if defined?(Rails)
    end
    true
  end

  # Preview contents of an unmounted partition.
  # Temp-mounts, reads top-level directory listing with sizes, then unmounts.
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

    # Temp-mount for preview
    preview_mount = "/tmp/amahi-preview-#{SecureRandom.hex(4)}"
    begin
      if production?
        execute_command("sudo /usr/bin/mkdir -p #{Shellwords.escape(preview_mount)}")
        result = execute_command("sudo /bin/mount -o ro #{Shellwords.escape(device)} #{Shellwords.escape(preview_mount)} 2>&1")
      else
        # Dev/test: return sample data
        return sample_preview
      end

      read_directory_summary(preview_mount)
    ensure
      if production?
        execute_command("sudo /bin/umount #{Shellwords.escape(preview_mount)} 2>/dev/null")
        execute_command("sudo /usr/bin/rmdir #{Shellwords.escape(preview_mount)} 2>/dev/null")
      end
    end
  end

  # Check if a device is the OS disk
  def self.os_disk?(device)
    # Strip partition number to get base device
    base = device.gsub(/\d+$/, '')
    all = devices
    dev = all.find { |d| d[:path] == base || d[:path] == device }
    return false unless dev
    dev[:os_disk]
  end

  private

  def self.os_disk_from_partitions?(partitions)
    partitions.any? { |p| p[:mountpoint].present? && ['/', '/boot', '/boot/efi'].include?(p[:mountpoint]) }
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

  def self.detect_fstype(device)
    output = execute_command("sudo /sbin/blkid -s TYPE -o value #{Shellwords.escape(device)} 2>/dev/null")
    output.to_s.strip.presence
  end

  def self.get_uuid(device)
    output = execute_command("sudo /sbin/blkid -s UUID -o value #{Shellwords.escape(device)} 2>/dev/null")
    output.to_s.strip.presence
  end

  def self.find_mount_point(device)
    output = execute_command("lsblk -no MOUNTPOINT #{Shellwords.escape(device)} 2>/dev/null")
    output.to_s.strip.presence
  end

  def self.auto_mount_point
    # Clean up stale fstab entries and empty dirs before picking a number
    cleanup_stale_mounts! if production?

    # Find the lowest available storage number (reuse gaps from unmounted drives)
    num = 1
    loop do
      candidate = "/mnt/storage-#{num}"
      # Available if the directory doesn't exist, or exists but is empty and not a mount point
      if !Dir.exist?(candidate)
        return candidate
      elsif Dir.empty?(candidate) && !mount_point_active?(candidate)
        return candidate
      end
      num += 1
    end
  end

  # Remove fstab entries whose UUIDs no longer exist on any attached device,
  # and clean up orphaned /mnt/storage-* directories
  def self.cleanup_stale_mounts!
    return unless production?

    # Get all UUIDs currently present on the system
    output, _stderr, _status = Shell.capture("/sbin/blkid -s UUID -o value 2>/dev/null")
    live_uuids = output.strip.lines.map(&:strip).reject(&:empty?)

    # Read fstab and find stale /mnt/storage-* entries
    fstab = File.read("/etc/fstab") rescue ""
    stale_found = false
    new_lines = fstab.lines.map do |line|
      next line if line.strip.start_with?("#") || line.strip.empty?
      next line unless line.include?("/mnt/storage-")
      # Extract UUID from fstab line
      if line =~ /UUID=([^\s]+)/
        uuid = $1
        if live_uuids.include?(uuid)
          line  # UUID still exists, keep it
        else
          stale_found = true
          Rails.logger.info("[DiskManager] Removing stale fstab entry: #{line.strip}") if defined?(Rails)
          nil   # UUID gone, remove the line
        end
      else
        line
      end
    end.compact

    if stale_found
      File.write("/tmp/fstab.new", new_lines.join)
      execute_command("sudo /usr/bin/cp /tmp/fstab.new /etc/fstab")
    end

    # Remove empty, unmounted /mnt/storage-* directories
    Dir.glob("/mnt/storage-*").each do |dir|
      next unless File.directory?(dir)
      next if mount_point_active?(dir)
      begin
        Dir.rmdir(dir) if Dir.empty?(dir)
      rescue SystemCallError
        # Not empty or permission denied — skip
      end
    end
  rescue => e
    Rails.logger.error("[DiskManager] cleanup_stale_mounts! failed: #{e.message}") if defined?(Rails)
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
    rescue => e
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
