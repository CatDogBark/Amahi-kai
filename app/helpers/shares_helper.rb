module SharesHelper

  def confirm_share_destroy_message(comment)
    [t('are_you_sure_share', :share => comment),
     t('this_shares_files_deleted'), "", t('there_is_no_undo'), ""].join("\n")
  end

  def tags_to_str(tags)
    tags.blank? ? '(add tags)' : tags
  end

end
