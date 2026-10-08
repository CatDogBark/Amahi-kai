require 'shell'
require 'shellwords'
require 'swap_service'
require 'setup_service'

class SetupController < ApplicationController
  include SseStreaming

  layout 'setup'

  # Skip the setup redirect for this controller (avoid infinite loop)
  skip_before_action :check_setup_completed
  before_action :login_required
  before_action :admin_required
  before_action :redirect_if_setup_completed
  before_action :set_no_cache

  def welcome
    @memory = SetupService.detect_memory
  end

  def create_swap
    size = params[:size].to_s
    size = '2G' unless %w[1G 2G 4G].include?(size)

    stream_sse do |sse|
      sse.emit("Checking current swap status...")
      existing = SystemInfo.swaps.first
      if existing
        sse.emit("⚠ Swap already active (#{existing[:name]}). Skipping.")
        sse.done
        next
      end

      success = SwapService.create!(size) { |msg| sse.emit(msg) }
      unless success
        sse.emit("✗ Failed to create swap file. Check disk space.")
        sse.done("error")
        next
      end

      sse.emit("✓ Swap enabled! #{size} swap file is active and persistent.")
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
      keep_signed_in_after_password_change(user)
      redirect_to setup_network_path
    else
      flash[:error] = user.errors.full_messages.join(", ")
      render :admin
    end
  end

  def network
    @hostname = SystemInfo.hostname
    @ip = SystemInfo.ip_address
    @server_name = Setting.get('server-name') || @hostname
  end

  def update_network
    name = params[:server_name].to_s.strip
    unless name.blank?
      Setting.set('server-name', name)
      # Actually change the system hostname
      flash[:warning] = "Saved the server name, but the system hostname couldn't be changed (details in the Amahi-kai log)" unless Platform.set_hostname!(name)
    end
    redirect_to setup_storage_path
  end

  def storage
    require 'disk_manager'
    @devices = begin
      DiskManager.devices
    rescue DiskManager::DiskError, Shell::CommandError => e
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
    rescue DiskManager::DiskError, Shell::CommandError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end
  end

  def update_storage
    # Redirect to greyhole step — actual work happens in prepare_drives_stream
    redirect_to setup_greyhole_path
  end

  def prepare_drives_stream
    selected_drives = (params[:drives] || '').split(',')
    format_drives = (params[:format_drives] || '').split(',')

    stream_sse do |sse|
      SetupService.stream_prepare_drives(selected_drives, format_drives, sse)
    end
  end

  def greyhole
    @pool_drives = DiskPoolPartition.count
    @greyhole_installed = begin
      require 'greyhole'
      Greyhole.installed?
    rescue LoadError, Greyhole::GreyholeError
      false
    end
    @default_copies = Setting.get('default_pool_copies') || '2'
  end

  def install_greyhole
    redirect_to setup_share_path
  end

  def install_greyhole_stream
    default_copies = (params[:default_copies] || '2').to_i
    default_copies = 2 if default_copies < 1

    stream_sse do |sse|
      sse.emit("Installing Greyhole...")
      sse.emit("")
      SetupService.stream_greyhole_install(default_copies, sse)
    end
  end

  def share
  end

  def create_share
    name = params[:share_name].to_s.strip
    if name.blank?
      redirect_to setup_complete_path; return
    end

    begin
      SetupService.create_first_share(name)
      session[:first_share_created] = name
    rescue ActiveRecord::RecordInvalid, Errno::ENOENT, Errno::EACCES, Shell::CommandError => e
      flash[:error] = e.message
      render :share; return
    end

    redirect_to setup_complete_path
  end

  def complete
    # Checked against the account itself, so a password changed on the Users page counts too.
    @admin_password_changed = !User.seed_admin_password_in_use?
    @server_name = Setting.get('server-name')
    @pool_partitions = DiskPoolPartition.all rescue []
    @first_share = session[:first_share_created]
    @standalone_drives = session[:standalone_drives] || []
    @greyhole_installed = begin
      require 'greyhole'
      Greyhole.installed?
    rescue LoadError, Greyhole::GreyholeError
      false
    end
    @default_copies = Setting.get('default_pool_copies') || '0'
  end

  def finish
    # The seeded password is public; setup can't end while it still logs in.
    if User.seed_admin_password_in_use?
      flash[:error] = "Change the admin password before finishing setup."
      redirect_to setup_admin_path
      return
    end
    Setting.set('setup_completed', 'true')
    session.delete(:first_share_created)
    session.delete(:greyhole_installed)
    session.delete(:default_copies)
    session.delete(:standalone_drives)
    redirect_to root_path, notice: "Setup complete! Welcome to Amahi-kai."
  end

  private

  # The wizard formats drives and resets the storage pool; once setup is done it stays closed.
  def redirect_if_setup_completed
    redirect_to root_path if setup_completed?
  end

  def set_no_cache
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end
end
