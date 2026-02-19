require 'greyhole'

class DisksController < ApplicationController
  before_action :admin_required
  include ActionController::Live

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
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'

    sse = SSEWriter.new(response.stream)

    begin
      sse.write("Starting Greyhole installation...\n")

      unless Greyhole.production?
        # Dev/test mode — simulate install
        ["Adding Greyhole apt repository...",
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
        ].each do |line|
          sleep(0.3)
          sse.write(line)
        end
        sse.finish(true)
      else
        # Production — real install with streamed output
        steps = [
          { label: "Adding Greyhole apt repository...", commands: [
            ["curl -s #{Greyhole::GREYHOLE_REPO_KEY} | sudo gpg --dearmor -o #{Greyhole::KEYRING_PATH}", !File.exist?(Greyhole::KEYRING_PATH)],
            ["echo 'deb [signed-by=#{Greyhole::KEYRING_PATH}] #{Greyhole::GREYHOLE_REPO_URL} stable main' | sudo tee #{Greyhole::SOURCES_PATH} > /dev/null", !File.exist?(Greyhole::SOURCES_PATH)],
          ]},
          { label: "Updating package lists...", commands: [
            ["sudo apt-get update 2>&1", true]
          ]},
          { label: "Installing Greyhole package...", commands: [
            ["sudo apt-get install -y greyhole 2>&1", true]
          ]},
          { label: "Setting up Greyhole database...", commands: [
            ['sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS greyhole" 2>&1', true],
            ["sudo mysql -u root -e \"GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;\" 2>&1", true],
            ['sudo mysql -u root greyhole < /usr/share/greyhole/schema-mysql.sql 2>&1', File.exist?('/usr/share/greyhole/schema-mysql.sql')]
          ]},
          { label: "Enabling Greyhole service...", commands: [
            ["sudo systemctl enable greyhole.service 2>&1", true],
            ["sudo systemctl start greyhole.service 2>&1", true]
          ]}
        ]

        success = true
        steps.each do |step|
          sse.write("\n#{step[:label]}")
          step[:commands].each do |cmd, should_run|
            next unless should_run
            IO.popen(cmd) do |io|
              io.each_line do |line|
                sse.write("  #{line.chomp}")
              end
            end
            unless $?.success?
              sse.write("  ✗ Command failed: #{cmd.split.first}")
              success = false
              break
            end
          end
          break unless success
        end

        if success && DiskPoolPartition.any?
          sse.write("\nGenerating Greyhole configuration...")
          Greyhole.configure!
          sse.write("  ✓ Configuration written")
        end

        if success
          sse.write("\n✓ Greyhole installed successfully!")
        else
          sse.write("\n✗ Installation failed. Check the output above for errors.")
        end
        sse.finish(success)
      end
    rescue => e
      sse.write("\n✗ Error: #{e.message}")
      sse.finish(false)
    ensure
      response.stream.close
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

  # Simple SSE helper
  class SSEWriter
    def initialize(stream)
      @stream = stream
    end

    def write(data)
      @stream.write("data: #{data}\n\n")
    rescue IOError
      # Client disconnected
    end

    def finish(success)
      @stream.write("event: done\ndata: #{success ? 'success' : 'error'}\n\n")
    rescue IOError
    end
  end
end
