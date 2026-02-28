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

    @entries = list_directory(@full_path)
    @breadcrumbs = build_breadcrumbs
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

    uploaded = []
    files.each do |file|
      next unless file.respond_to?(:original_filename)
      filename = sanitize_filename(file.original_filename)
      dest = File.join(@full_path, filename)

      # Don't overwrite without flag
      if File.exist?(dest) && !params[:overwrite]
        next
      end

      # Write to temp file first, then move to destination with proper ownership
      tmp = File.join('/tmp', "amahi-upload-#{SecureRandom.hex(8)}")
      File.open(tmp, 'wb') { |f| f.write(file.read) }
      Shell.run("cp #{Shellwords.escape(tmp)} #{Shellwords.escape(dest)}")
      Shell.run("chown amahi:users #{Shellwords.escape(dest)}")
      FileUtils.rm_f(tmp)
      uploaded << filename
    end

    render json: { status: 'ok', uploaded: uploaded, count: uploaded.size }
  rescue StandardError => e
    Rails.logger.error("FileBrowser#upload ERROR: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # POST /files/:share_id/new_folder
  def new_folder
    name = sanitize_filename(params[:name].to_s.strip)
    if name.blank?
      return render json: { error: "Folder name required" }, status: :unprocessable_entity
    end

    folder_path = File.join(@full_path, name)
    if File.exist?(folder_path)
      return render json: { error: "Already exists" }, status: :conflict
    end

    Shell.run("mkdir -p #{Shellwords.escape(folder_path)}")
    Shell.run("chmod 2775 #{Shellwords.escape(folder_path)}")
    render json: { status: 'ok', name: name }
  rescue StandardError => e
    Rails.logger.error("FileBrowser#new_folder ERROR: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # PUT /files/:share_id/rename
  def rename
    old_name = params[:old_name].to_s.strip
    new_name = sanitize_filename(params[:new_name].to_s.strip)

    if old_name.blank? || new_name.blank?
      return render json: { error: "Names required" }, status: :unprocessable_entity
    end

    old_path = safe_join(@full_path, old_name)
    new_path = File.join(@full_path, new_name)

    unless File.exist?(old_path)
      return render json: { error: "Not found" }, status: :not_found
    end

    if File.exist?(new_path)
      return render json: { error: "Name already taken" }, status: :conflict
    end

    File.rename(old_path, new_path)
    render json: { status: 'ok', old_name: old_name, new_name: new_name }
  end

  # DELETE /files/:share_id/delete
  def delete
    names = Array(params[:names]).map(&:to_s).reject(&:blank?)
    if names.empty?
      return render json: { error: "No items selected" }, status: :unprocessable_entity
    end

    deleted = []
    names.each do |name|
      target = safe_join(@full_path, name)
      next unless File.exist?(target)

      if File.directory?(target)
        FileUtils.rm_rf(target)
      else
        File.delete(target)
      end
      deleted << name
    end

    render json: { status: 'ok', deleted: deleted, count: deleted.size }
  end

  # GET /files/:share_id/preview/*path
  def preview
    unless File.file?(@full_path)
      return render json: { error: "Not a file" }, status: :not_found
    end

    @filename = File.basename(@full_path)
    @file_size = File.size(@full_path)
    @mime_type = detect_mime_type(@full_path)
    @previewable = previewable?(@mime_type, @file_size)

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

    mime = detect_mime_type(@full_path)
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
    # The relative path within the share
    @relative_path = (params[:path] || '').to_s
      .gsub(/\.\./, '')     # Strip directory traversal
      .gsub(%r{//+}, '/')   # Collapse multiple slashes
      .gsub(%r{^/|/$}, '')  # Strip leading/trailing slashes

    @full_path = File.join(@share.path, @relative_path)

    # Final security check: resolved path must be under the share root
    real_share = File.realpath(@share.path) rescue @share.path
    real_full = File.realpath(@full_path) rescue @full_path

    unless real_full.start_with?(real_share)
      flash[:error] = "Access denied"
      redirect_to file_browser_path(@share)
    end
  end

  def list_directory(path)
    entries = Dir.entries(path).reject { |e| e.start_with?('.') }.sort_by { |e|
      # Folders first, then alphabetical
      [File.directory?(File.join(path, e)) ? 0 : 1, e.downcase]
    }

    entries.map do |name|
      full = File.join(path, name)
      stat = File.stat(full) rescue nil
      next nil unless stat

      {
        name: name,
        directory: stat.directory?,
        size: stat.directory? ? nil : stat.size,
        modified: stat.mtime,
        mime: stat.directory? ? nil : detect_mime_type(full),
        icon: file_icon(name, stat.directory?)
      }
    end.compact
  end

  def build_breadcrumbs
    parts = @relative_path.split('/').reject(&:blank?)
    crumbs = [{ name: @share.name, path: '' }]
    parts.each_with_index do |part, i|
      crumbs << { name: part, path: parts[0..i].join('/') }
    end
    crumbs
  end

  def send_file_download
    mime = detect_mime_type(@full_path)
    send_file @full_path,
      type: mime,
      disposition: 'attachment',
      filename: File.basename(@full_path)
  end

  def send_directory_as_zip
    require 'zip'
    dir_name = File.basename(@full_path)
    temp_zip = Tempfile.new([dir_name, '.zip'])

    Zip::OutputStream.open(temp_zip.path) do |zos|
      base = @full_path
      Dir.glob(File.join(base, '**', '*')).each do |file|
        next if File.directory?(file)
        relative = file.sub("#{base}/", '')
        zos.put_next_entry(relative)
        zos.write(File.read(file))
      end
    end

    send_file temp_zip.path,
      type: 'application/zip',
      disposition: 'attachment',
      filename: "#{dir_name}.zip"
  ensure
    temp_zip&.close
  end

  def sanitize_filename(name)
    # Strip path separators, null bytes, and dangerous characters
    name.gsub(%r{[/\\:\x00]}, '').gsub('..', '').strip.truncate(255)
  end

  def safe_join(base, name)
    sanitized = sanitize_filename(name)
    path = File.join(base, sanitized)
    real_base = File.realpath(base) rescue base
    real_path = File.realpath(path) rescue path
    raise "Access denied" unless real_path.start_with?(real_base)
    path
  end

  MIME_TYPES = {
    # Images
    '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png',
    '.gif' => 'image/gif', '.webp' => 'image/webp', '.svg' => 'image/svg+xml',
    '.bmp' => 'image/bmp', '.ico' => 'image/x-icon',
    # Video
    '.mp4' => 'video/mp4', '.webm' => 'video/webm', '.mkv' => 'video/x-matroska',
    '.avi' => 'video/x-msvideo', '.mov' => 'video/quicktime',
    # Audio
    '.mp3' => 'audio/mpeg', '.ogg' => 'audio/ogg', '.wav' => 'audio/wav',
    '.flac' => 'audio/flac', '.m4a' => 'audio/mp4',
    # Text
    '.txt' => 'text/plain', '.md' => 'text/markdown', '.csv' => 'text/csv',
    '.json' => 'application/json', '.xml' => 'application/xml',
    '.html' => 'text/html', '.css' => 'text/css', '.js' => 'text/javascript',
    '.rb' => 'text/x-ruby', '.py' => 'text/x-python', '.sh' => 'text/x-shellscript',
    '.yml' => 'text/yaml', '.yaml' => 'text/yaml', '.log' => 'text/plain',
    '.conf' => 'text/plain', '.cfg' => 'text/plain', '.ini' => 'text/plain',
    # Documents
    '.pdf' => 'application/pdf',
    '.doc' => 'application/msword', '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls' => 'application/vnd.ms-excel', '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    # Archives
    '.zip' => 'application/zip', '.tar' => 'application/x-tar',
    '.gz' => 'application/gzip', '.7z' => 'application/x-7z-compressed',
    '.rar' => 'application/x-rar-compressed',
  }.freeze

  def detect_mime_type(path)
    ext = File.extname(path).downcase
    MIME_TYPES[ext] || 'application/octet-stream'
  end

  def previewable?(mime, size)
    return false if size > 50.megabytes

    case mime
    when /^image\// then size < 20.megabytes
    when /^video\// then true
    when /^audio\// then true
    when /^text\//, 'application/json', 'application/xml' then size < 2.megabytes
    when 'application/pdf' then size < 30.megabytes
    else false
    end
  end

  FILE_ICONS = {
    # Folders
    :directory => '📁',
    # Images
    '.jpg' => '🖼️', '.jpeg' => '🖼️', '.png' => '🖼️', '.gif' => '🖼️',
    '.webp' => '🖼️', '.svg' => '🖼️', '.bmp' => '🖼️',
    # Video
    '.mp4' => '🎬', '.webm' => '🎬', '.mkv' => '🎬', '.avi' => '🎬', '.mov' => '🎬',
    # Audio
    '.mp3' => '🎵', '.ogg' => '🎵', '.wav' => '🎵', '.flac' => '🎵', '.m4a' => '🎵',
    # Documents
    '.pdf' => '📄', '.doc' => '📄', '.docx' => '📄',
    '.xls' => '📊', '.xlsx' => '📊',
    # Code/Text
    '.txt' => '📝', '.md' => '📝', '.json' => '📝', '.xml' => '📝',
    '.rb' => '💎', '.py' => '🐍', '.js' => '📜', '.sh' => '⚙️',
    '.yml' => '📝', '.yaml' => '📝', '.log' => '📋',
    # Archives
    '.zip' => '📦', '.tar' => '📦', '.gz' => '📦', '.7z' => '📦', '.rar' => '📦',
  }.freeze

  def file_icon(name, is_dir)
    return FILE_ICONS[:directory] if is_dir
    ext = File.extname(name).downcase
    FILE_ICONS[ext] || '📄'
  end
end
