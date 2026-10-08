require 'file_browser_service'

# The Trash, beside the shares in the file browser (admins): every share's deleted files
# (Trash), to restore or delete for good, and how long it keeps them.
class TrashController < ApplicationController
  before_action :admin_required

  def index
    @page_title = t('shares') # it's part of the file browser, below the shares
    @trash = Trash.contents
    @days = Trash.days
    # A pooled share's file goes back through Greyhole, which needs the share still pooled
    # (and not turning off).
    @pooled_shares = Share.where('disk_pool_copies > 0').where(pool_removing: false).pluck(:name)
  end

  def restore
    Trash.restore!(params[:kind], params[:share], params[:path])
    flash[:notice] = "#{params[:share]}/#{params[:path]} is back in its share."
  rescue Trash::Error, Privileged::Error => e
    flash[:error] = "Couldn't restore #{params[:share]}/#{params[:path]}: #{e.message}"
  ensure
    redirect_to trash_path
  end

  def delete
    Trash.delete!(params[:kind], params[:share], params[:path])
    flash[:notice] = "Deleted #{params[:share]}/#{params[:path]} for good."
  rescue Trash::Error, Privileged::Error => e
    flash[:error] = "Couldn't delete #{params[:share]}/#{params[:path]}: #{e.message}"
  ensure
    redirect_to trash_path
  end

  def empty
    Trash.empty!
    flash[:notice] = 'The trash is empty.'
  rescue Trash::Error, Privileged::Error => e
    flash[:error] = "Couldn't empty the trash: #{e.message}"
  ensure
    redirect_to trash_path
  end

  # How long the Trash keeps files.
  def keep
    Trash.set_days!(params[:days])
    flash[:notice] = params[:days].to_i.zero? ? 'The Trash keeps files until it is emptied.' : "The Trash keeps files for #{params[:days].to_i} days."
  rescue Trash::Error, Privileged::Error => e
    flash[:error] = "Couldn't change how long the Trash keeps files: #{e.message}"
  ensure
    redirect_to trash_path
  end
end
