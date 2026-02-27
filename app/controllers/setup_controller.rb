require 'shell'
require 'shellwords'
require 'swap_service'

class SetupController < ApplicationController
  include SseStreaming

  layout 'setup'

  # Skip the setup redirect for this controller (avoid infinite loop)
  skip_before_action :check_setup_completed
  before_action :login_required
  before_action :admin_required

  def welcome
    @memory = detect_memory
  end

  def create_swap
    size = params[:size].to_s
    size = '2G' unless %w[1G 2G 4G].include?(size)

    stream_sse do |sse|
      sse.send("Checking current swap status...")
      existing = `swapon --show --noheadings 2>/dev/null`.strip
      unless existing.empty?
        sse.send("⚠ Swap already active (#{existing.split.first}). Skipping.")
        sse.done
        next
      end

      success = SwapService.create!(size) { |msg| sse.send(msg) }
      unless success
        sse.send("✗ Failed to create swap file. Check disk space.")
        sse.done("error")
        next
      end

      sse.send("✓ Swap enabled! #{size} swap file is active and persistent.")
      sse.done
    end
  end

  def admin
  end

  def update_admin
    user = current_user
    if params[:password].blank?
      flash[:error] = "Password cannot be blank."
      render :admin; return
    end
    if params[:password] != params[:password_confirmation]
      flash[:error] = "Passwords do not match."
      render :admin; return
    end
    if params[:password].length < 8
      flash[:error] = "Password must be at least 8 characters."
      render :admin; return
    end
    user.password = params[:password]
    user.password_confirmation = params[:password_confirmation]
    if user.save
      session[:admin_password_changed] = true
      redirect_to setup_network_path
    else
      flash[:error] = user.errors.full_messages.join(", ")
      render :admin
    end
  end

  def network
    @hostname = `hostname`.strip rescue "amahi"
    @ip = `hostname -I`.strip.split.first rescue "unknown"
    @server_name = Setting.get('server-name') || @hostname
  end

  def update_network
    name = params[:server_name].to_s.strip
    unless name.blank?
      Setting.set('server-name', name)
      # Actually change the system hostname
      Platform.set_hostname!(name)
    end
    redirect_to setup_storage_path
  end

  def storage
    require 'disk_manager'
    @devices = begin
      DiskManager.devices
    rescue StandardError => e
      Rails.logger.error("SetupController#storage: #{e.message}")
      []
    end
    @pool_paths = DiskPoolPartition.all.map(&:path) rescue []
  end

  def preview_drive
    require 'disk_manager'
    device = params[:device]
    begin
      preview = DiskManager.preview(device)
      render json: { status: 'ok', device: device, entries: preview[:entries], total_used: preview[:total_used], file_count: preview[:file_count] }
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end
  end

  def update_storage
    # Redirect to greyhole step — actual work happens in prepare_drives_stream
    redirect_to setup_greyhole_path
  end

  def prepare_drives_stream
    require 'disk_manager'

    selected_drives = (params[:drives] || '').split(',')
    format_drives = (params[:format_drives] || '').split(',')
    supported_fs = %w[ext2 ext3 ext4 xfs btrfs]

    stream_sse do |sse|
      if selected_drives.empty?
        sse.send("⚠ No drives selected")
        sse.done
        next
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
            sse.send("  ✓ Created standalone share '#{share_name}' (#{part[:fstype]} — not pooled)")
          end

          sse.send("")
        rescue StandardError => e
          sse.send("  ✗ Error: #{e.message}")
          Rails.logger.error("SetupController#prepare_drives_stream: #{e.message} for #{device_path}")
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
  end

  def greyhole
    @pool_drives = DiskPoolPartition.count
    @greyhole_installed = begin
      require 'greyhole'
      Greyhole.installed?
    rescue StandardError
      false
    end
    @default_copies = Setting.get('default_pool_copies') || '2'
  end

  def install_greyhole
    redirect_to setup_share_path
  end

  def install_greyhole_stream
    require 'greyhole'

    default_copies = (params[:default_copies] || '2').to_i
    default_copies = 2 if default_copies < 1

    stream_sse do |sse|
      sse.send("Installing Greyhole...")
      sse.send("")

      Setting.set('default_pool_copies', default_copies.to_s)

      unless Rails.env.production?
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
        next
      end

      begin
        sse.send("Installing Greyhole package and dependencies...")
        Greyhole.install!
        sse.send("✓ Greyhole installed")

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
        Rails.logger.error("SetupController#install_greyhole_stream: #{e.message}")
        sse.done("error")
      end
    end
  end

  def share
  end

  def create_share
    name = params[:share_name].to_s.strip
    if name.blank?
      redirect_to setup_complete_path; return
    end

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
      session[:first_share_created] = name
      # Update Greyhole config if it's running
      begin
        require 'greyhole'
        Greyhole.configure! if Greyhole.installed? && pool_copies > 0
      rescue StandardError => e
        Rails.logger.error("SetupController#create_share greyhole: #{e.message}")
      end
    else
      flash[:error] = share.errors.full_messages.join(", ")
      render :share; return
    end

    redirect_to setup_complete_path
  end

  def complete
    @admin_password_changed = session[:admin_password_changed]
    @server_name = Setting.get('server-name')
    @pool_partitions = DiskPoolPartition.all rescue []
    @first_share = session[:first_share_created]
    @standalone_drives = session[:standalone_drives] || []
    @greyhole_installed = begin
      require 'greyhole'
      Greyhole.installed?
    rescue StandardError
      false
    end
    @default_copies = Setting.get('default_pool_copies') || '0'
  end

  def finish
    Setting.set('setup_completed', 'true')
    session.delete(:admin_password_changed)
    session.delete(:first_share_created)
    session.delete(:greyhole_installed)
    session.delete(:default_copies)
    session.delete(:standalone_drives)
    redirect_to root_path, notice: "Setup complete! Welcome to Amahi-kai."
  end

  private

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
end
