require 'shell'
require 'shellwords'

# What the web file browser reads: folder listings, breadcrumbs, file types and zips of
# folders. It never changes a share (FileBrowserController).
module FileBrowserService
  # A path that can't be used as given (with "." or ".." in it). It's a SecurityError so the
  # path checks that rescue SecurityError catch it too.
  class InvalidName < SecurityError; end
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

    # The files a folder's zip holds, as [name in the zip, path]: every file under it whose
    # real path is in one of +roots+. A link pointing anywhere else is left out, as it is for
    # a single download.
    def zip_files(full_path, roots = [full_path])
      base = full_path.chomp('/') # the share's top folder comes with a trailing slash
      Dir.glob(File.join(base, '**', '*')).filter_map do |file|
        [file.delete_prefix("#{base}/"), file] if File.file?(file) && inside_any?(roots, file)
      end
    end

    # Writes the folder's zip to +zip+ (a ZipKit streamer, sending it as it's made), each file
    # copied a piece at a time. A file gone or unreadable since the folder was listed is left
    # out.
    def write_zip(zip, full_path, roots = [full_path])
      zip_files(full_path, roots).each do |name, path|
        File.open(path, 'rb') do |io|
          zip.write_file(name, modification_time: io.mtime) { |sink| IO.copy_stream(io, sink) }
        end
      rescue SystemCallError
        next
      end
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

    # [relative path, full path] for +raw_path+ in a share. +roots+: the share's folder first,
    # then anywhere else its files may really be (a pooled share's folders on the Greyhole pool
    # drives). The path, with links followed, must be in one of them.
    def resolve_path(roots, raw_path)
      roots = Array(roots)
      segments = (raw_path || '').to_s.split('/').reject(&:empty?)
      raise InvalidName, "Invalid path" if segments.any? { |s| s == '.' || s == '..' }
      relative_path = segments.join('/')
      full_path = File.join(roots.first, relative_path)

      raise SecurityError, "Access denied" unless inside_any?(roots, full_path)

      [relative_path, full_path]
    end

    def inside_any?(roots, path)
      roots.any? { |root| inside?(root, path) }
    end

    # Is +path+ (after following symlinks) +base+ itself or inside it? Compares whole
    # path segments: a plain prefix match let /files/movies reach /files/movies-private.
    def inside?(base, path)
      real_base = File.realpath(base) rescue base
      real_path = File.realpath(path) rescue path
      real_path == real_base || real_path.start_with?(real_base.chomp('/') + '/')
    end
  end
end
