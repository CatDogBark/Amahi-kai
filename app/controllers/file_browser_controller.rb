require 'file_browser_service'

class FileBrowserController < ApplicationController
  before_action :browse_required
  before_action :set_share
  before_action :check_share_access
  before_action :check_write_access, only: [:upload, :new_folder, :rename, :delete]
  before_action :resolve_path
  skip_forgery_protection only: [:upload, :new_folder, :rename, :delete]

  # GET /files/:share_id/browse/*path
  def browse
    unless File.directory?(@full_path)
      # If it's a file, send it
      if File.file?(@full_path)
        return send_file_download
      end
      flash[:error] = "Path not found"
      return redirect_to file_browser_path(@share)
    end

    @entries = FileBrowserService.list_directory(@full_path)
    @breadcrumbs = FileBrowserService.build_breadcrumbs(@share.name, @relative_path)
  end

  # GET /files/:share_id/download/*path
  def download
    unless File.exist?(@full_path)
      flash[:error] = "File not found"
      return redirect_to file_browser_path(@share, path: @relative_path)
    end

    if File.directory?(@full_path)
      send_directory_as_zip
    else
      send_file_download
    end
  end

  # POST /files/:share_id/upload
  def upload
    unless File.directory?(@full_path)
      return render json: { error: "Target directory not found" }, status: :not_found
    end

    files = Array(params[:files])
    if files.empty?
      return render json: { error: "No files selected" }, status: :unprocessable_entity
    end

    uploaded = FileBrowserService.upload_files(@full_path, files, overwrite: !!params[:overwrite])
    render json: { status: 'ok', uploaded: uploaded, count: uploaded.size }
  rescue StandardError => e
    Rails.logger.error("FileBrowser#upload ERROR: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # POST /files/:share_id/new_folder
  def new_folder
    name = params[:name].to_s.strip
    if name.blank?
      return render json: { error: "Folder name required" }, status: :unprocessable_entity
    end

    created_name = FileBrowserService.create_folder(@full_path, name)
    render json: { status: 'ok', name: created_name }
  rescue StandardError => e
    Rails.logger.error("FileBrowser#new_folder ERROR: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # PUT /files/:share_id/rename
  def rename
    old_name = params[:old_name].to_s.strip
    new_name = params[:new_name].to_s.strip

    if old_name.blank? || new_name.blank?
      return render json: { error: "Names required" }, status: :unprocessable_entity
    end

    result = FileBrowserService.rename_entry(@full_path, old_name, new_name)
    render json: { status: 'ok', old_name: result[:old_name], new_name: result[:new_name] }
  rescue StandardError => e
    status = case e.message
             when "Not found" then :not_found
             when "Name already taken" then :conflict
             else :internal_server_error
             end
    render json: { error: e.message }, status: status
  end

  # DELETE /files/:share_id/delete
  def delete
    names = Array(params[:names]).map(&:to_s).reject(&:blank?)
    if names.empty?
      return render json: { error: "No items selected" }, status: :unprocessable_entity
    end

    deleted = FileBrowserService.delete_entries(@full_path, names)
    render json: { status: 'ok', deleted: deleted, count: deleted.size }
  end

  # GET /files/:share_id/preview/*path
  def preview
    unless File.file?(@full_path)
      return render json: { error: "Not a file" }, status: :not_found
    end

    @filename = File.basename(@full_path)
    @file_size = File.size(@full_path)
    @mime_type = FileBrowserService.detect_mime_type(@full_path)
    @previewable = FileBrowserService.previewable?(@mime_type, @file_size)

    if request.format.json?
      render json: {
        name: @filename,
        size: @file_size,
        mime: @mime_type,
        previewable: @previewable
      }
    end
    # Otherwise renders preview.html.erb
  end

  # GET /files/:share_id/raw/*path — serves file content for preview embeds
  def raw
    unless File.file?(@full_path)
      return head :not_found
    end

    mime = FileBrowserService.detect_mime_type(@full_path)
    send_file @full_path,
      type: mime,
      disposition: 'inline',
      filename: File.basename(@full_path)
  end

  private

  def set_share
    @share = Share.find_by!(name: params[:share_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Share not found"
    redirect_to root_path
  end

  def check_share_access
    unless current_user.can_access_share?(@share)
      flash[:error] = "You don't have access to this share"
      redirect_to root_path
    end
  end

  def check_write_access
    unless current_user.can_write_share?(@share)
      render json: { error: "Write access denied" }, status: :forbidden
    end
  end

  def resolve_path
    @relative_path, @full_path = FileBrowserService.resolve_path(@share.path, params[:path])
  rescue StandardError
    flash[:error] = "Access denied"
    redirect_to file_browser_path(@share)
  end

  def send_file_download
    mime = FileBrowserService.detect_mime_type(@full_path)
    send_file @full_path,
      type: mime,
      disposition: 'attachment',
      filename: File.basename(@full_path)
  end

  def send_directory_as_zip
    temp_zip = FileBrowserService.create_zip(@full_path)
    dir_name = File.basename(@full_path)
    send_file temp_zip.path,
      type: 'application/zip',
      disposition: 'attachment',
      filename: "#{dir_name}.zip"
  ensure
    temp_zip&.close
  end
end
