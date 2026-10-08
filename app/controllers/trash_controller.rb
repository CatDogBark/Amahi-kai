require 'file_browser_service'

# The Trash, beside the shares in the file browser (admins): what Greyhole keeps of files
# deleted or changed in pooled shares (GreyholeTrash), to restore or delete for good.
class TrashController < ApplicationController
  before_action :admin_required

  def index
    @page_title = t('trash')
    @greyhole_installed = Greyhole.installed?
    @trash = GreyholeTrash.contents
    # Restore needs the share pooled (and not turning off): Greyhole puts the file back.
    @pooled_shares = Share.where('disk_pool_copies > 0').where(pool_removing: false).pluck(:name)
  end

  def restore
    GreyholeTrash.restore!(params[:share], params[:path])
    flash[:notice] = "#{params[:share]}/#{params[:path]} is back in its share. Greyhole makes its copies again."
  rescue Privileged::Error => e
    flash[:error] = "Couldn't restore #{params[:share]}/#{params[:path]}: #{e.message}"
  ensure
    redirect_to trash_path
  end

  def delete
    GreyholeTrash.delete!(params[:share], params[:path])
    flash[:notice] = "Deleted #{params[:share]}/#{params[:path]} for good."
  rescue Privileged::Error => e
    flash[:error] = "Couldn't delete #{params[:share]}/#{params[:path]}: #{e.message}"
  ensure
    redirect_to trash_path
  end

  def empty
    GreyholeTrash.empty!
    flash[:notice] = 'The trash is empty.'
  rescue Privileged::Error => e
    flash[:error] = "Couldn't empty the trash: #{e.message}"
  ensure
    redirect_to trash_path
  end
end
