module SharesHelper

  # The New Share form's Where: [label, value] for the system disk, the Greyhole pool (once it
  # has drives) and each ZFS pool that's online (SharesController#params_create_share).
  def share_where_choices
    choices = [['System disk', 'disk']]
    choices << ['Greyhole pool (2 copies)', 'greyhole'] if Greyhole.installed? && DiskPoolPartition.exists?
    if StoragePools.zfs_installed?
      StoragePools.status[:pools].each { |pool| choices << ["ZFS pool #{pool.name} (#{pool.layout})", "zfs:#{pool.name}"] }
    end
    choices
  end

  # The value of +share+'s Where, for the form drawn again after a refusal.
  def share_where_value(share)
    return "zfs:#{share.zfs_pool}" if share&.zfs?
    share&.disk_pool_copies.to_i.positive? ? 'greyhole' : 'disk'
  end

  # The Shares list's label for where a share lives (Share#storage_label).
  def share_storage_badge(share)
    kind = if share.zfs? then 'zfs'
           elsif share.disk_pool_copies.to_i.positive? then 'greyhole'
           else 'disk'
           end
    content_tag(:span, share.storage_label, class: "share-storage share-storage-#{kind} ms-2", id: "share-storage-#{share.id}")
  end

  def confirm_share_destroy_message(comment)
    [t('are_you_sure_share', :share => comment),
     t('this_shares_files_deleted'), "", t('there_is_no_undo'), ""].join("\n")
  end

end
