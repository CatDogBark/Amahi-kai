require 'greyhole'

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

  def storage_pool
    @page_title = t('disks')
    @greyhole_status = Greyhole.status
    @pool_drives = Greyhole.pool_drives
    @partitions = partition_list
    @pool_partitions = DiskPoolPartition.all
  end

  def toggle_greyhole
    if Greyhole.running?
      Greyhole.stop!
    else
      Greyhole.start!
    end
    redirect_to disks_engine.storage_pool_path
  end

  def install_greyhole
    begin
      Greyhole.install!
      flash[:notice] = "Greyhole installed successfully!"
    rescue Greyhole::GreyholeError => e
      flash[:error] = "Failed to install Greyhole: #{e.message}"
    rescue => e
      flash[:error] = "Installation error: #{e.message}"
    end
    redirect_to disks_engine.storage_pool_path
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
          "    greyhole php php-mysqlnd php-mbstring",
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
            { cmd: "sudo mysql -u root -e \"GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;\" 2>&1", run: true },
          ]},
          { label: "Configuring PHP dependencies...", commands: [
            { cmd: "sudo apt-get install -y php-mbstring php-mysql 2>&1", run: true },
            { cmd: "sudo phpenmod mbstring 2>&1", run: true },
          ]},
          { label: "Creating minimal Greyhole config...", commands: [
            { cmd: "echo 'db_host = localhost\ndb_user = amahi\ndb_name = greyhole' | sudo tee /etc/greyhole.conf 2>&1", run: !File.exist?('/etc/greyhole.conf') },
          ]},
          { label: "Installing Greyhole package...", commands: [
            { cmd: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold greyhole 2>&1", run: true }
          ]},
          { label: "Loading Greyhole database schema...", commands: [
            { cmd: 'sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS greyhole" 2>&1', run: true },
            { cmd: "sudo mysql -u root -e \"GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;\" 2>&1", run: true },
            { cmd: "sudo mysql -u root greyhole < /usr/share/greyhole/schema-mysql.sql 2>&1", run: File.exist?('/usr/share/greyhole/schema-mysql.sql') }
          ]},
          { label: "Enabling Greyhole service...", commands: [
            { cmd: "sudo systemctl enable greyhole.service 2>&1", run: true },
            { cmd: "sudo systemctl start greyhole.service 2>&1", run: true }
          ]}
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
              sse_send.call("  ✗ Command failed")
              success = false
              break
            end
          end
          break unless success
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
