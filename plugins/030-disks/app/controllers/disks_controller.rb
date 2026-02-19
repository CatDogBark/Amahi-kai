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

  private

  def partition_list
    begin
      PartitionUtils.new.info
    rescue
      []
    end
  end
end
