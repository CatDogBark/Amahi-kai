require 'greyhole'
require 'disk_manager'
require 'shell'
require 'disk_service'

class DisksController < ApplicationController
  include SseStreaming

  before_action :admin_required

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
    @devices = DiskManager.devices
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
    @pool_drives = Greyhole.pool_drives
    @partitions = DiskService.partition_list
    @pool_partitions = DiskPoolPartition.all
  end

  def toggle_disk_pool_partition
    path = params[:path]
    result = DiskService.toggle_pool_partition(path)

    respond_to do |format|
      format.html { redirect_to disks_storage_pool_path }
      format.any { render json: { status: 'ok', checked: result[:checked], path: result[:path] } }
    end
  rescue ActiveRecord::RecordInvalid, Greyhole::GreyholeError, Shell::CommandError => e
    Rails.logger.error("Toggle disk pool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def toggle_greyhole
    DiskService.toggle_greyhole
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
    stream_sse do |sse|
      sse.send("Starting Greyhole installation...")
      DiskService.stream_greyhole_install(sse)
    end
  end
end
