require 'greyhole'
require 'disk_manager'
require 'shell'
require 'disk_service'
require 'storage_pools'
require 'storage_health'

class DisksController < ApplicationController
  include SseStreaming

  before_action :admin_required
  # The storage health alerts at the top of every Disks page.
  before_action(only: %i[index mounts devices storage_pool pools]) { @health = StorageHealth.load }

  def index
    @page_title = t('disks')
    @disks = DiskUtils.stats rescue []
  end

  def mounts
    @page_title = t('disks')
    @mounts = DiskUtils.mounts rescue []
  end

  def devices
    @page_title = t('disks')
    # The disk the system runs from first, then the others in the kernel's order.
    @devices = DiskManager.devices.each_with_index.sort_by { |device, i| [device[:os_disk] ? 0 : 1, i] }.map(&:first)
  end

  def format_disk
    device = params[:device]
    begin
      DiskManager.format_disk!(device)
      flash[:notice] = "Successfully formatted #{device} as ext4"
    rescue DiskManager::DiskError => e
      flash[:error] = "Format failed: #{e.message}"
    rescue Shell::CommandError, Errno::ENOENT => e
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
    rescue Shell::CommandError, Errno::ENOENT => e
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
    rescue Shell::CommandError, Errno::ENOENT => e
      flash[:error] = "Unexpected error: #{e.message}"
      redirect_to disks_devices_path
    end
  end

  def mount_as_share
    device = params[:device]
    begin
      result = DiskService.create_share_from_mount(device)
      flash[:notice] = "Mounted #{device} at #{result[:mount_point]} and created share '#{result[:share_name]}'"
    rescue DiskManager::DiskError => e
      flash[:error] = "Mount failed: #{e.message}"
    rescue ActiveRecord::RecordInvalid, Shell::CommandError => e
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
    rescue Shell::CommandError, Errno::ENOENT => e
      flash[:error] = "Unexpected error: #{e.message}"
    end
    redirect_to disks_devices_path
  end

  def storage_pool
    @page_title = t('disks')
    @greyhole_status = Greyhole.status
    @greyhole_removal_blocker = Greyhole.removal_blocker if @greyhole_status[:installed]
    @pool_drives = Greyhole.pool_drives
    @partitions = DiskService.partition_list
    @pool_partitions = DiskPoolPartition.all
  end

  def toggle_disk_pool_partition
    path = params[:path]
    result = DiskService.toggle_pool_partition(path)

    respond_to do |format|
      format.html do
        flash[:notice] = "Greyhole is moving the files kept only on #{path} to the other drives; it leaves the pool when that's done." if result[:removing]
        redirect_to disks_storage_pool_path
      end
      format.any { render json: { status: 'ok', checked: result[:checked], removing: result[:removing], path: result[:path] } }
    end
  rescue Greyhole::GreyholeError => e
    respond_to do |format|
      format.html do
        flash[:error] = "#{path} stays in the pool: #{e.message}"
        redirect_to disks_storage_pool_path
      end
      format.any { render json: { status: 'error', message: e.message }, status: :unprocessable_content }
    end
  rescue ActiveRecord::RecordInvalid, Shell::CommandError => e
    Rails.logger.error("Toggle disk pool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def toggle_greyhole
    running = Greyhole.running?
    flash[:error] = "Greyhole didn't #{running ? 'stop' : 'start'}. Its reason is in: journalctl -u greyhole" unless DiskService.toggle_greyhole
    redirect_to disks_storage_pool_path
  end

  # Tells Greyhole to use the drive now mounted at one of its pool folders (swapped or
  # formatted, so Greyhole refused it).
  def accept_pool_drive
    path = params[:path].to_s
    Greyhole.accept_drive!(path)
    flash[:notice] = "Greyhole uses the drive at #{path} now."
    redirect_to disks_storage_pool_path
  rescue Greyhole::GreyholeError => e
    flash[:error] = "Greyhole didn't take the drive at #{path}: #{e.message}"
    redirect_to disks_storage_pool_path
  end

  def install_greyhole
    begin
      Greyhole.install!
      flash[:notice] = "Greyhole installed successfully!"
    rescue Greyhole::GreyholeError => e
      flash[:error] = "Failed to install Greyhole: #{e.message}"
    rescue Shell::CommandError, Errno::ENOENT, Errno::EACCES, IOError => e
      flash[:error] = "Installation error: #{e.message}"
    end
    redirect_to disks_storage_pool_path
  end

  def install_greyhole_stream
    stream_sse do |sse|
      sse.emit("Starting Greyhole installation...")
      DiskService.stream_greyhole_install(sse)
    end
  end

  def uninstall_greyhole_stream
    stream_sse do |sse|
      Greyhole.uninstall! { |line| sse.emit(line) }
      sse.emit('✓ Greyhole is uninstalled')
      sse.done
    rescue Greyhole::GreyholeError => e
      sse.emit("✗ #{e.message}")
      sse.done('error')
    end
  end

  # ZFS pools (docs/plans/storage.md): bitShare's storage, on drives of their own.
  def pools
    @page_title = t('disks')
    @status = StoragePools.status
    @drives = StoragePools.drives(@status[:pools], Array(@status[:offline]))
                          .each_with_index.sort_by { |drive, i| [drive[:role] == :os ? 0 : 1, i] }.map(&:first)
    @zfs_removal_blocker = StoragePools.removal_blocker(@status) if @status[:installed]
    names = @status[:pools].map(&:name)
    @new_pool_name = (1..).lazy.map { |n| "pool#{n}" }.find { |name| names.exclude?(name) }
    @smart_installed = StoragePools.smart_installed?
    @next_scrub = StoragePools.next_scrub
  end

  # The pool buttons post JSON and reload on { status: 'ok' }, or show the error.
  def create_pool
    pool_change { StoragePools.create!(name: params[:name], layout: params[:layout], devices: Array(params[:devices])) }
  end

  def replace_pool_drive
    pool_change { StoragePools.replace!(name: params[:name], old: params[:old], new: params[:new]) }
  end

  def add_pool_group
    pool_change { StoragePools.add_group!(name: params[:name], devices: Array(params[:devices])) }
  end

  def destroy_pool
    pool_change { StoragePools.destroy!(name: params[:name], confirm: params[:confirm]) }
  end

  def pool_offline
    pool_change { StoragePools.take_offline!(params[:name]) }
  end

  def pool_online
    pool_change { StoragePools.bring_online!(params[:name]) }
  end

  def scrub_pool
    pool_change { StoragePools.scrub!(params[:name]) }
  end

  def snapshot_pool
    pool_change { StoragePools.snapshot!(params[:name]) }
  end

  def pool_snapshot_policy
    pool_change { StoragePools.set_snapshot_policy!(name: params[:name], hourly: params[:hourly], daily: params[:daily]) }
  end

  def destroy_pool_snapshot
    pool_change { StoragePools.destroy_snapshot!(name: params[:name], snapshot: params[:snapshot]) }
  end

  def rollback_pool
    pool_change { StoragePools.rollback!(name: params[:name], snapshot: params[:snapshot], confirm: params[:confirm]) }
  end

  def check_health
    pool_change { StoragePools.check_health! }
  end

  # Installs what's missing of ZFS and the drive health tools.
  def uninstall_zfs_stream
    stream_sse do |sse|
      StoragePools.uninstall! { |line| sse.emit(line) }
      sse.emit('✓ ZFS is uninstalled')
      sse.done
    rescue StoragePools::Error => e
      sse.emit("✗ #{e.message}")
      sse.done('error')
    end
  end

  def install_storage_tools_stream
    stream_sse do |sse|
      StoragePools.install! { |line| sse.emit(line) }
      sse.emit('✓ Installed')
      sse.done
    rescue StoragePools::Error => e
      sse.emit("✗ #{e.message}")
      sse.done('error')
    end
  end

  private

  def pool_change
    yield
    render json: { status: 'ok' }
  rescue StoragePools::Error => e
    render json: { status: 'error', error: e.message }, status: :unprocessable_content
  end
end
