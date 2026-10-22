require 'shell'
require 'disk_manager'
require 'disk_service'

# Service object for setup wizard operations.
# Extracted from SetupController — handles drive preparation,
# Greyhole installation streaming, share creation, and system detection.
module SetupService
  class << self
    def detect_memory
      total_mb = begin
        File.read('/proc/meminfo').match(/MemTotal:\s+(\d+)/)[1].to_i / 1024
      rescue StandardError
        0
      end

      swap_mb = SystemInfo.swaps.sum { |swap| swap[:bytes] } / (1024 * 1024)

      recommended_swap = if total_mb < 2048
                           '4G'
                         elsif total_mb < 4096
                           '2G'
                         elsif total_mb < 8192
                           '1G'
                         end

      {
        total_mb: total_mb,
        swap_mb: swap_mb,
        has_swap: swap_mb > 0,
        needs_swap: total_mb < 8192 && swap_mb == 0,
        recommended_swap: recommended_swap
      }
    end

    def stream_prepare_drives(selected_drives, format_drives, sse)
      supported_fs = %w[ext2 ext3 ext4 xfs btrfs]

      if selected_drives.empty?
        sse.emit("⚠ No drives selected")
        sse.done
        return
      end

      sse.emit("Preparing #{selected_drives.size} drive#{'s' if selected_drives.size > 1}...")
      sse.emit("")

      # Drives join the pool; ones already in it stay (re-running this step used to empty it).
      success = true

      selected_drives.each do |device_path|
        begin
          devices = DiskManager.devices
          part = devices.flat_map { |d| d[:partitions] }.find { |p| p[:path] == device_path }
          unless part
            sse.emit("⚠ Device #{device_path} not found, skipping")
            next
          end

          mount_point = part[:mountpoint]
          will_format = part[:status] == :unformatted || format_drives.include?(device_path)

          if will_format
            sse.emit("Formatting #{device_path} as ext4...")
            DiskManager.format_disk!(device_path)
            sse.emit("  ✓ Format complete")
          end

          if mount_point.blank?
            sse.emit("Mounting #{device_path}...")
            mount_point = DiskManager.mount!(device_path)
            sse.emit("  ✓ Mounted at #{mount_point}")
          else
            sse.emit("#{device_path} already mounted at #{mount_point}")
          end

          next unless mount_point.present?

          fs_after = will_format ? 'ext4' : part[:fstype].to_s.downcase
          can_pool = supported_fs.include?(fs_after)

          # The same way Disks → Greyhole Pool adds a drive: once Greyhole is installed (going
          # Back after its step), its config follows and it starts.
          if can_pool
            DiskService.toggle_pool_partition(mount_point) unless DiskPoolPartition.exists?(path: mount_point)
            sse.emit("  ✓ Added to storage pool")
          else
            create_standalone_share(mount_point, part[:fstype], sse)
          end

          sse.emit("")
        rescue StandardError => e
          sse.emit("  ✗ Error: #{e.message}")
          Rails.logger.error("SetupService#stream_prepare_drives: #{e.message} for #{device_path}")
          success = false
        end
      end

      pool_count = DiskPoolPartition.count
      if pool_count > 0
        sse.emit("✓ #{pool_count} drive#{'s' if pool_count > 1} ready for storage pooling!")
      else
        sse.emit("✓ Drives prepared (no poolable drives — standalone shares created)")
      end
      sse.done(success ? "success" : "error")
    end

    # The copies chosen become the default for new pooled shares (Share.default_pool_copies),
    # once Greyhole is installed: a failed install leaves no setting behind.
    def stream_greyhole_install(default_copies, sse)
      if Rails.env.production?
        stream_greyhole_install_production(default_copies, sse)
      else
        stream_greyhole_install_dev(default_copies, sse)
      end
    end

    # The first share: in the Greyhole pool, with the default copies, when Greyhole is installed
    # and has drives; otherwise a plain share on the system disk. Its folder is where the
    # Shares page would put it.
    def create_first_share(name)
      path = Share.default_full_path(name)
      pool_copies = DiskPoolPartition.any? && greyhole_installed? ? Share.default_pool_copies : 0

      share = Share.new(
        name: name,
        path: path,
        visible: true,
        rdonly: false,
        everyone: true,
        extras: "",
        disk_pool_copies: pool_copies
      )

      if share.save
        # Update Greyhole config if it's running
        begin
          require 'greyhole'
          Greyhole.configure! if Greyhole.installed? && pool_copies > 0
        rescue StandardError => e
          Rails.logger.error("SetupService#create_first_share greyhole: #{e.message}")
        end
        share
      else
        raise share.errors.full_messages.join(", ")
      end
    end

    private

    def greyhole_installed?
      require 'greyhole'
      Greyhole.installed?
    rescue LoadError, StandardError
      false
    end

    def create_standalone_share(mount_point, fstype, sse)
      share_name = File.basename(mount_point).gsub(/[^a-zA-Z0-9\-]/, '')
      share_name = "drive-#{share_name}" if share_name.blank?
      unless Share.exists?(path: mount_point)
        share = Share.new(
          name: share_name, path: mount_point, visible: true, rdonly: false,
          everyone: true, extras: "", disk_pool_copies: 0
        )
        null_fs = ShareFileSystem.new(share)
        def null_fs.setup_directory; end
        def null_fs.update_guest_permissions; end
        share.instance_variable_set(:@file_system, null_fs)
        share.save!
      end
      sse.emit("  ✓ Created standalone share '#{share_name}' (#{fstype} — not pooled)")
    end

    def stream_greyhole_install_dev(default_copies, sse)
      # The steps Greyhole.install! reports, without installing anything (development and tests).
      lines = [
        "Adding the Greyhole apt repository...",
        "Preparing the Greyhole database...",
        "Writing the Greyhole config...",
        "Installing Greyhole and its PHP modules (this takes a few minutes)...",
        "  Setting up greyhole (0.15.30-1) ...",
        "✓ Greyhole package installed",
        "Loading the database schema...",
        "Configuring Samba for Greyhole...",
        "Enabling and starting Greyhole...",
        "",
        "  #{DiskPoolPartition.count} pool drives configured",
        "  Default copies: #{default_copies}",
        "✓ Greyhole is running!"
      ]
      lines.each do |line|
        sleep 0.3 unless Rails.env.test?
        sse.emit(line)
      end
      Setting.set('default_pool_copies', default_copies.to_s)
      sse.done
    end

    # Greyhole.install! writes the config (pool drives included) and starts Greyhole.
    def stream_greyhole_install_production(default_copies, sse)
      require 'greyhole'

      Greyhole.install! { |msg| sse.emit(msg) }
      Setting.set('default_pool_copies', default_copies.to_s) # only once it's installed (a failure is rescued below)

      sse.emit("")
      sse.emit("  #{DiskPoolPartition.count} pool drives configured")
      sse.emit("  Default copies: #{default_copies}")
      if Greyhole.running?
        sse.emit("✓ Greyhole is running!")
      else
        sse.emit("⚠ Greyhole was started but may take a moment to initialize")
      end

      sse.done
    rescue StandardError => e
      sse.emit("✗ Error: #{e.message}")
      Rails.logger.error("SetupService#stream_greyhole_install: #{e.message}")
      sse.done("error")
    end
  end
end
