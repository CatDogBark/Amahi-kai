require 'json'
require 'shellwords'

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

    if production?
      execute_command("sudo /usr/bin/mkdir -p #{Shellwords.escape(mount_point)}")
      execute_command("sudo /bin/mount #{Shellwords.escape(device)} #{Shellwords.escape(mount_point)}")
      # Add to fstab using UUID for persistence
      if uuid.present?
        fstab_line = "UUID=#{uuid} #{mount_point} ext4 defaults 0 2"
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
    else
      Rails.logger.info("[DiskManager] SIMULATED: umount #{mount_point}") if defined?(Rails)
    end
    true
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

  def self.get_uuid(device)
    output = execute_command("sudo /sbin/blkid -s UUID -o value #{Shellwords.escape(device)} 2>/dev/null")
    output.to_s.strip.presence
  end

  def self.find_mount_point(device)
    output = execute_command("lsblk -no MOUNTPOINT #{Shellwords.escape(device)} 2>/dev/null")
    output.to_s.strip.presence
  end

  def self.auto_mount_point
    existing = Dir.glob("/mnt/storage-*").sort
    next_num = 1
    if existing.any?
      nums = existing.map { |p| p.match(/storage-(\d+)/)&.captures&.first&.to_i }.compact
      next_num = (nums.max || 0) + 1
    end
    "/mnt/storage-#{next_num}"
  end

  def self.production?
    defined?(Rails) && Rails.env.production?
  end

  def self.execute_command(cmd)
    if defined?(Command) && Command.respond_to?(:execute)
      Command.execute(cmd)
    else
      `#{cmd}`
    end
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
