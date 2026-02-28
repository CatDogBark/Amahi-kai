require 'disk_manager'
require 'greyhole'
require 'shell'

# Service object for disk management operations.
# Extracted from DisksController — handles disk pool toggling,
# Greyhole streaming install, and share creation from mounts.
module DiskService
  class << self
    def toggle_pool_partition(path)
      part = DiskPoolPartition.where(path: path).first
      if part
        part.destroy
        checked = false
      else
        min_free = 10
        DiskPoolPartition.create!(path: path, minimum_free: min_free)
        checked = true
      end

      # Regenerate Greyhole config whenever pool membership changes
      begin
        Greyhole.configure! if Greyhole.installed?
      rescue StandardError => e
        Rails.logger.error("Greyhole configure failed: #{e.message}")
      end

      { checked: checked, path: path }
    end

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
          tags: "storage",
          extras: "",
          disk_pool_copies: 0
        )
        share.save!
      end

      { mount_point: mp, share_name: share_name }
    end

    def partition_list
      PartitionUtils.new.info
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
        sse.send(line)
      end
      sse.done
    end

    def stream_greyhole_install_production(sse)
      success = true
      steps = [
        { label: "Adding Greyhole apt repository...", commands: [
          { cmd: "curl -s #{Greyhole::GREYHOLE_REPO_KEY} | sudo gpg --dearmor -o #{Greyhole::KEYRING_PATH} 2>&1", run: !File.exist?(Greyhole::KEYRING_PATH) },
          { cmd: "echo 'deb [signed-by=#{Greyhole::KEYRING_PATH}] #{Greyhole::GREYHOLE_REPO_URL} stable main' | sudo tee #{Greyhole::SOURCES_PATH} 2>&1", run: !File.exist?(Greyhole::SOURCES_PATH) },
        ]},
        { label: "Updating package lists...", commands: [
          { cmd: "sudo apt-get update 2>&1", run: true }
        ]},
        { label: "Pre-configuring Greyhole database...", commands: [
          { cmd: 'sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS greyhole" 2>&1', run: true },
          { cmd: %Q(sudo mysql -u root -e "CREATE USER IF NOT EXISTS 'amahi'@'localhost' IDENTIFIED BY '#{ENV.fetch("DATABASE_PASSWORD", "")}'; GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;" 2>&1), run: true },
        ]},
        { label: "Configuring PHP dependencies...", commands: [
          { cmd: "sudo apt-get install -y php8.3-mbstring php8.3-mysql 2>&1", run: true },
          { cmd: "sudo phpenmod mbstring 2>&1", run: true },
        ]},
        { label: "Creating minimal Greyhole config...", commands: [
          { cmd: "echo 'db_host = localhost\ndb_user = amahi\ndb_pass = #{ENV.fetch('DATABASE_PASSWORD', '')}\ndb_name = greyhole' | sudo tee /etc/greyhole.conf 2>&1", run: !File.exist?('/etc/greyhole.conf') },
        ]},
        { label: "Installing Greyhole package...", commands: [
          { cmd: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold greyhole 2>&1", run: true }
        ]},
        { label: "Loading Greyhole database schema...", commands: [
          { cmd: 'sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS greyhole" 2>&1', run: true },
          { cmd: %Q(sudo mysql -u root -e "CREATE USER IF NOT EXISTS 'amahi'@'localhost' IDENTIFIED BY '#{ENV.fetch("DATABASE_PASSWORD", "")}'; GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;" 2>&1), run: true },
          { cmd: "sudo mysql -u root greyhole < /usr/share/greyhole/schema-mysql.sql 2>&1", run: File.exist?('/usr/share/greyhole/schema-mysql.sql') }
        ]},
        { label: "Enabling Greyhole service...", commands: [
          { cmd: "sudo systemctl enable greyhole.service 2>&1", run: true },
        ]},
        { label: "Starting Greyhole service...", commands: [], nonfatal: true }
      ]

      steps.each do |step|
        sse.send(step[:label])
        step[:commands].each do |c|
          next unless c[:run]
          IO.popen(c[:cmd]) do |io|
            io.each_line do |line|
              sse.send("  #{line.chomp}")
            end
          end
          unless $?.success?
            if step[:nonfatal]
              sse.send("  ⚠ Non-critical step failed (continuing)")
            else
              sse.send("  ✗ Command failed")
              success = false
              break
            end
          end
        end
        break unless success
      end

      # Try starting greyhole — non-fatal if it fails (needs config first)
      sse.send("Starting Greyhole service...")
      Greyhole.start!
      if Greyhole.running?
        sse.send("  ✓ Greyhole is running")
      else
        sse.send("  ⚠ Service not started — configure storage pool drives first")
      end

      if success && DiskPoolPartition.any?
        sse.send("Generating Greyhole configuration...")
        Greyhole.configure!
        sse.send("  ✓ Configuration written")
      end

      if success
        sse.send("✓ Greyhole installed successfully!")
        sse.done
      else
        sse.send("✗ Installation failed. Check the output above for errors.")
        sse.done("error")
      end
    end
  end
end
