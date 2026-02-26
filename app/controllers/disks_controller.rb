require 'greyhole'
require 'disk_manager'

class DisksController < ApplicationController
  before_action :admin_required

  def index
    @page_title = t('disks')
    unless use_sample_data?
      @disks = DiskUtils.stats
    else
      @disks = SampleData.load('disks')
    end
  end

  def mounts
    @page_title = t('disks')
    unless use_sample_data?
      @mounts = DiskUtils.mounts
    else
      @mounts = SampleData.load('mounts')
    end
  end

  def devices
    @page_title = t('disks')
    @devices = DiskManager.devices
  end

  def format_disk
    device = params[:device]
    begin
      DiskManager.format_disk!(device)
      flash[:notice] = "Successfully formatted #{device} as ext4"
    rescue DiskManager::DiskError => e
      flash[:error] = "Format failed: #{e.message}"
    rescue StandardError => e
      flash[:error] = "Unexpected error: #{e.message}"
    end
    redirect_to disks_devices_path
  end

  def mount_disk
    device = params[:device]
    mount_point = params[:mount_point].presence
    begin
      mp = DiskManager.mount!(device, mount_point)
      flash[:notice] = "Mounted #{device} at #{mp}"
    rescue DiskManager::DiskError => e
      flash[:error] = "Mount failed: #{e.message}"
    rescue StandardError => e
      flash[:error] = "Unexpected error: #{e.message}"
    end
    redirect_to disks_devices_path
  end

  def preview_disk
    device = params[:device]
    begin
      @preview = DiskManager.preview(device)
      @device = device
      render :preview
    rescue DiskManager::DiskError => e
      flash[:error] = "Preview failed: #{e.message}"
      redirect_to disks_devices_path
    rescue StandardError => e
      flash[:error] = "Unexpected error: #{e.message}"
      redirect_to disks_devices_path
    end
  end

  def mount_as_share
    device = params[:device]
    begin
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

      flash[:notice] = "Mounted #{device} at #{mp} and created share '#{share_name}'"
    rescue DiskManager::DiskError => e
      flash[:error] = "Mount failed: #{e.message}"
    rescue StandardError => e
      flash[:error] = "Error: #{e.message}"
    end
    redirect_to disks_devices_path
  end

  def unmount_disk
    device = params[:device]
    begin
      DiskManager.unmount!(device)
      flash[:notice] = "Unmounted #{device}"
    rescue DiskManager::DiskError => e
      flash[:error] = "Unmount failed: #{e.message}"
    rescue StandardError => e
      flash[:error] = "Unexpected error: #{e.message}"
    end
    redirect_to disks_devices_path
  end

  def storage_pool
    @page_title = t('disks')
    @greyhole_status = Greyhole.status
    @pool_drives = Greyhole.pool_drives
    @partitions = partition_list
    @pool_partitions = DiskPoolPartition.all
  end

  def toggle_disk_pool_partition
    path = params[:path]
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

    respond_to do |format|
      format.html { redirect_to disks_storage_pool_path }
      format.any { render json: { status: 'ok', checked: checked, path: path } }
    end
  rescue StandardError => e
    Rails.logger.error("Toggle disk pool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def toggle_greyhole
    if Greyhole.running?
      Greyhole.stop!
    else
      Greyhole.start!
    end
    redirect_to disks_storage_pool_path
  end

  def install_greyhole
    begin
      Greyhole.install!
      flash[:notice] = "Greyhole installed successfully!"
    rescue Greyhole::GreyholeError => e
      flash[:error] = "Failed to install Greyhole: #{e.message}"
    rescue StandardError => e
      flash[:error] = "Installation error: #{e.message}"
    end
    redirect_to disks_storage_pool_path
  end

  def install_greyhole_stream
    # Disable middleware buffering
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    # Use chunked transfer
    self.response_body = Enumerator.new do |yielder|
      sse_send = ->(data, event = nil) {
        msg = ""
        msg += "event: #{event}\n" if event
        msg += "data: #{data}\n\n"
        yielder << msg
      }

      sse_send.call("Starting Greyhole installation...")

      unless Rails.env.production?
        # Dev/test mode — simulate install
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
          sse_send.call(line)
        end
        sse_send.call("success", "done")
      else
        # Production — real install with streamed output
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
          sse_send.call(step[:label])
          step[:commands].each do |c|
            next unless c[:run]
            IO.popen(c[:cmd]) do |io|
              io.each_line do |line|
                sse_send.call("  #{line.chomp}")
              end
            end
            unless $?.success?
              if step[:nonfatal]
                sse_send.call("  ⚠ Non-critical step failed (continuing)")
              else
                sse_send.call("  ✗ Command failed")
                success = false
                break
              end
            end
          end
          break unless success
        end

        # Try starting greyhole — non-fatal if it fails (needs config first)
        sse_send.call("Starting Greyhole service...")
        system("sudo systemctl start greyhole.service 2>/dev/null")
        if system("systemctl is-active --quiet greyhole")
          sse_send.call("  ✓ Greyhole is running")
        else
          sse_send.call("  ⚠ Service not started — configure storage pool drives first")
        end

        if success && DiskPoolPartition.any?
          sse_send.call("Generating Greyhole configuration...")
          Greyhole.configure!
          sse_send.call("  ✓ Configuration written")
        end

        if success
          sse_send.call("✓ Greyhole installed successfully!")
          sse_send.call("success", "done")
        else
          sse_send.call("✗ Installation failed. Check the output above for errors.")
          sse_send.call("error", "done")
        end
      end
    end
  end

  private

  def partition_list
    begin
      PartitionUtils.new.info
    rescue
      []
    end
  end
end
