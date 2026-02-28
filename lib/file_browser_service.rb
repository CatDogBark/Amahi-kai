require 'shell'
require 'shellwords'

# Service object for file browser operations.
# Extracted from FileBrowserController — handles all file system
# operations so the controller only deals with HTTP concerns.
module FileBrowserService
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

  class << self
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

    def build_breadcrumbs(share_name, relative_path)
      parts = relative_path.split('/').reject(&:blank?)
      crumbs = [{ name: share_name, path: '' }]
      parts.each_with_index do |part, i|
        crumbs << { name: part, path: parts[0..i].join('/') }
      end
      crumbs
    end

    def upload_files(full_path, files, overwrite: false)
      uploaded = []
      files.each do |file|
        next unless file.respond_to?(:original_filename)
        filename = sanitize_filename(file.original_filename)
        dest = File.join(full_path, filename)

        # Don't overwrite without flag
        if File.exist?(dest) && !overwrite
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
      uploaded
    end

    def create_folder(full_path, name)
      name = sanitize_filename(name)
      folder_path = File.join(full_path, name)
      raise "Already exists" if File.exist?(folder_path)

      Shell.run("mkdir -p #{Shellwords.escape(folder_path)}")
      Shell.run("chmod 2775 #{Shellwords.escape(folder_path)}")
      name
    end

    def rename_entry(full_path, old_name, new_name)
      new_name = sanitize_filename(new_name)
      old_path = safe_join(full_path, old_name)
      new_path = File.join(full_path, new_name)

      raise "Not found" unless File.exist?(old_path)
      raise "Name already taken" if File.exist?(new_path)

      File.rename(old_path, new_path)
      { old_name: old_name, new_name: new_name }
    end

    def delete_entries(full_path, names)
      deleted = []
      names.each do |name|
        target = safe_join(full_path, name)
        next unless File.exist?(target)

        if File.directory?(target)
          FileUtils.rm_rf(target)
        else
          File.delete(target)
        end
        deleted << name
      end
      deleted
    end

    def create_zip(full_path)
      require 'zip'
      dir_name = File.basename(full_path)
      temp_zip = Tempfile.new([dir_name, '.zip'])

      Zip::OutputStream.open(temp_zip.path) do |zos|
        base = full_path
        Dir.glob(File.join(base, '**', '*')).each do |file|
          next if File.directory?(file)
          relative = file.sub("#{base}/", '')
          zos.put_next_entry(relative)
          zos.write(File.read(file))
        end
      end

      temp_zip
    end

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

    def file_icon(name, is_dir)
      return FILE_ICONS[:directory] if is_dir
      ext = File.extname(name).downcase
      FILE_ICONS[ext] || '📄'
    end

    def sanitize_filename(name)
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

    def resolve_path(share_path, raw_path)
      relative_path = (raw_path || '').to_s
        .gsub(/\.\./, '')     # Strip directory traversal
        .gsub(%r{//+}, '/')   # Collapse multiple slashes
        .gsub(%r{^/|/$}, '')  # Strip leading/trailing slashes

      full_path = File.join(share_path, relative_path)

      # Final security check: resolved path must be under the share root
      real_share = File.realpath(share_path) rescue share_path
      real_full = File.realpath(full_path) rescue full_path

      unless real_full.start_with?(real_share)
        raise "Access denied"
      end

      [relative_path, full_path]
    end
  end
end
