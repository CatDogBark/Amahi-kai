require 'disk_manager'
require 'greyhole'

# Service object for disk management operations.
# Extracted from DisksController — handles disk pool toggling,
# Greyhole streaming install, and share creation from mounts.
module DiskService
  class << self
    # Adds a drive to Greyhole's pool, or takes it out (safely: Greyhole.remove_drive!).
    # { checked: in the pool, removing: Greyhole is moving its files off, path: }.
    def toggle_pool_partition(path)
      if DiskPoolPartition.exists?(path: path)
        removing = Greyhole.remove_drive!(path) == :removing
        return { checked: removing, removing: removing, path: path }
      end

      first = !DiskPoolPartition.exists?
      DiskPoolPartition.add!(path)
      checked = true

      # Regenerate Greyhole config whenever pool membership changes. With its first drive in,
      # Greyhole has something to do: start it (it can't run without one). Then it checks the
      # pool, making the copies the shares are short of on the new drive.
      begin
        if Greyhole.installed?
          Greyhole.configure!
          Greyhole.start! if first && !Greyhole.running?
          Greyhole.check_pool!
        end
      rescue StandardError => e
        Rails.logger.error("Greyhole configure failed: #{e.message}")
      end

      { checked: checked, removing: false, path: path }
    end

    # Starts or stops Greyhole; true if that worked.
    def toggle_greyhole
      if Greyhole.running?
        Greyhole.stop!
      else
        Greyhole.start!
      end
    end

    def create_share_from_mount(device)
      mp = DiskManager.mount!(device)
      share_name = File.basename(mp).gsub(/[^a-zA-Z0-9\-]/, '')
      share_name = "drive-#{share_name}" if share_name.blank?

      unless Share.exists?(path: mp)
        share = Share.new(
          name: share_name,
          path: mp,
          visible: true,
          rdonly: false,
          everyone: true,
          extras: "",
          disk_pool_copies: 0
        )
        share.save!
      end

      { mount_point: mp, share_name: share_name }
    end

    def partition_list
      DiskManager.share_storage
    rescue StandardError
      []
    end

    def stream_greyhole_install(sse)
      unless Rails.env.production?
        stream_greyhole_install_dev(sse)
        return
      end
      stream_greyhole_install_production(sse)
    end

    private

    def stream_greyhole_install_dev(sse)
      lines = [
        "Adding Greyhole apt repository...",
        "  Downloading signing key...",
        "  Adding source list...",
        "Updating package lists...",
        "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
        "  Get:2 https://www.greyhole.net/releases/deb stable InRelease",
        "  Fetched 12.4 kB in 1s (8,432 B/s)",
        "Installing greyhole...",
        "  Reading package lists...",
        "  Building dependency tree...",
        "  The following NEW packages will be installed:",
        "    greyhole php php-mysqlnd php8.3-mbstring",
        "  0 upgraded, 4 newly installed, 0 to remove.",
        "  Need to get 2,847 kB of archives.",
        "  Get:1 https://www.greyhole.net/releases/deb stable/main amd64 greyhole amd64 0.16.4-1 [847 kB]",
        "  Unpacking greyhole (0.16.4-1) ...",
        "  Setting up greyhole (0.16.4-1) ...",
        "Setting up Greyhole database...",
        "  Creating database...",
        "  Loading schema...",
        "Enabling Greyhole service...",
        "  Created symlink /etc/systemd/system/multi-user.target.wants/greyhole.service",
        "",
        "✓ Greyhole installed successfully!"
      ]
      lines.each do |line|
        sleep(0.3)
        sse.emit(line)
      end
      sse.done
    end

    # Greyhole.install! is the one install path (the setup wizard uses it too).
    def stream_greyhole_install_production(sse)
      Greyhole.install! { |msg| sse.emit(msg) }
      sse.emit(Greyhole.running? ? "  ✓ Greyhole is running" : "  ⚠ Greyhole isn't running yet: add storage pool drives first")
      sse.emit("✓ Greyhole installed successfully!")
      sse.done
    rescue Greyhole::GreyholeError => e
      sse.emit("  ✗ #{e.message}")
      sse.emit("✗ Installation failed. Check the output above for errors.")
      sse.done("error")
    end
  end
end
