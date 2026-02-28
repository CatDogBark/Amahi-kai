require 'shell'
require 'shellwords'
require 'disk_manager'

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

      swap_mb = begin
        output = `swapon --show=SIZE --noheadings --bytes 2>/dev/null`.strip
        output.empty? ? 0 : output.split("\n").sum { |line| line.strip.to_i } / (1024 * 1024)
      rescue StandardError
        0
      end

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
        sse.send("⚠ No drives selected")
        sse.done
        return
      end

      sse.send("Preparing #{selected_drives.size} drive#{'s' if selected_drives.size > 1}...")
      sse.send("")

      # Remove existing pool partitions
      DiskPoolPartition.destroy_all
      success = true

      selected_drives.each do |device_path|
        begin
          devices = DiskManager.devices
          part = devices.flat_map { |d| d[:partitions] }.find { |p| p[:path] == device_path }
          unless part
            sse.send("⚠ Device #{device_path} not found, skipping")
            next
          end

          mount_point = part[:mountpoint]
          will_format = part[:status] == :unformatted || format_drives.include?(device_path)

          if will_format
            sse.send("Formatting #{device_path} as ext4...")
            DiskManager.format_disk!(device_path)
            sse.send("  ✓ Format complete")
          end

          if mount_point.blank?
            sse.send("Mounting #{device_path}...")
            mount_point = DiskManager.mount!(device_path)
            sse.send("  ✓ Mounted at #{mount_point}")
          else
            sse.send("#{device_path} already mounted at #{mount_point}")
          end

          next unless mount_point.present?

          fs_after = will_format ? 'ext4' : part[:fstype].to_s.downcase
          can_pool = supported_fs.include?(fs_after)

          if can_pool
            DiskPoolPartition.create!(path: mount_point, minimum_free: 10)
            sse.send("  ✓ Added to storage pool")
          else
            create_standalone_share(mount_point, part[:fstype], sse)
          end

          sse.send("")
        rescue StandardError => e
          sse.send("  ✗ Error: #{e.message}")
          Rails.logger.error("SetupService#stream_prepare_drives: #{e.message} for #{device_path}")
          success = false
        end
      end

      pool_count = DiskPoolPartition.count
      if pool_count > 0
        sse.send("✓ #{pool_count} drive#{'s' if pool_count > 1} ready for storage pooling!")
      else
        sse.send("✓ Drives prepared (no poolable drives — standalone shares created)")
      end
      sse.done(success ? "success" : "error")
    end

    def stream_greyhole_install(default_copies, sse)
      Setting.set('default_pool_copies', default_copies.to_s)

      unless Rails.env.production?
        stream_greyhole_install_dev(default_copies, sse)
        return
      end

      stream_greyhole_install_production(default_copies, sse)
    end

    def create_first_share(name)
      path = File.join(Share::DEFAULT_SHARES_ROOT, name.downcase.gsub(/\s+/, '-'))

      # Use default pool copies if Greyhole was installed
      default_copies = (Setting.get('default_pool_copies') || '0').to_i
      pool_copies = DiskPoolPartition.any? && default_copies > 0 ? default_copies : 0

      share = Share.new(
        name: name,
        path: path,
        visible: true,
        rdonly: false,
        everyone: true,
        tags: name.downcase,
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

    def create_standalone_share(mount_point, fstype, sse)
      share_name = File.basename(mount_point).gsub(/[^a-zA-Z0-9\-]/, '')
      share_name = "drive-#{share_name}" if share_name.blank?
      unless Share.exists?(path: mount_point)
        share = Share.new(
          name: share_name, path: mount_point, visible: true, rdonly: false,
          everyone: true, tags: "storage", extras: "", disk_pool_copies: 0
        )
        null_fs = ShareFileSystem.new(share)
        def null_fs.setup_directory; end
        def null_fs.update_guest_permissions; end
        share.instance_variable_set(:@file_system, null_fs)
        share.save!
      end
      sse.send("  ✓ Created standalone share '#{share_name}' (#{fstype} — not pooled)")
    end

    def stream_greyhole_install_dev(default_copies, sse)
      lines = [
        "Installing dependencies...",
        "  php8.3-cli php8.3-mbstring php8.3-mysql",
        "  Setting up php8.3-cli...",
        "Adding Greyhole repository...",
        "  Downloading signing key...",
        "  Adding source list...",
        "Updating package lists...",
        "Installing Greyhole...",
        "  Setting up greyhole (0.15.36-1) ...",
        "✓ Greyhole installed",
        "",
        "Generating configuration...",
        "  Writing /etc/greyhole.conf",
        "  #{DiskPoolPartition.count} pool drives configured",
        "  Default copies: #{default_copies}",
        "✓ Configuration written",
        "",
        "Starting Greyhole service...",
        "✓ Greyhole is running!"
      ]
      lines.each do |line|
        sleep 0.3
        sse.send(line)
      end
      sse.done
    end

    def stream_greyhole_install_production(default_copies, sse)
      require 'greyhole'

      Greyhole.install! { |msg| sse.send(msg) }

      sse.send("")
      sse.send("Generating configuration...")
      Greyhole.configure!
      sse.send("  #{DiskPoolPartition.count} pool drives configured")
      sse.send("  Default copies: #{default_copies}")
      sse.send("✓ Configuration written")

      sse.send("")
      sse.send("Starting Greyhole service...")
      Greyhole.start!
      if Greyhole.running?
        sse.send("✓ Greyhole is running!")
      else
        sse.send("⚠ Service started but may take a moment to initialize")
      end

      sse.done
    rescue StandardError => e
      sse.send("✗ Error: #{e.message}")
      Rails.logger.error("SetupService#stream_greyhole_install: #{e.message}")
      sse.done("error")
    end
  end
end
