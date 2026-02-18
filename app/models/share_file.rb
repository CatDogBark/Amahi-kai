# ShareFile — indexed file/directory entry within a Share
#
# Maintains a database-backed index of all files across all shares.
# Replaces the old `locate`-based search with real metadata and
# instant lookups.

class ShareFile < ApplicationRecord
  belongs_to :share

  validates :name, presence: true
  validates :path, presence: true
  validates :relative_path, presence: true, uniqueness: { scope: :share_id }

  scope :files_only, -> { where(directory: false) }
  scope :directories_only, -> { where(directory: true) }
  scope :by_type, ->(type) { where(content_type: type) if type.present? }
  scope :search, ->(query) { where("name LIKE ?", "%#{sanitize_sql_like(query)}%") if query.present? }
  scope :recent, -> { order(file_modified_at: :desc) }

  # Content type categories
  AUDIO_EXTENSIONS = %w[aac aif flac iff m3u m4a mid midi mp3 mpa ogg opus ra ram wav wma].freeze
  IMAGE_EXTENSIONS = %w[bmp gif heic heif jpeg jpg mng pct png psd psp svg thm tif tiff webp].freeze
  VIDEO_EXTENSIONS = %w[3g2 3gp asf asx avi flv m4v mkv mov mp4 mpg mpeg ogv qt rm swf vob webm wmv].freeze
  DOCUMENT_EXTENSIONS = %w[csv doc docx epub html md odt ods pdf ppt pptx rtf tex txt xls xlsx xml].freeze

  def self.classify_extension(ext)
    ext = ext.to_s.downcase
    return 'audio' if AUDIO_EXTENSIONS.include?(ext)
    return 'image' if IMAGE_EXTENSIONS.include?(ext)
    return 'video' if VIDEO_EXTENSIONS.include?(ext)
    return 'document' if DOCUMENT_EXTENSIONS.include?(ext)
    'file'
  end

  # Build a ShareFile from a filesystem path
  def self.build_from_path(share, full_path, share_root)
    stat = File.stat(full_path)
    relative = full_path.sub(%r{\A#{Regexp.escape(share_root)}/?}, '')
    ext = File.extname(full_path).delete('.').downcase
    is_dir = stat.directory?

    new(
      share: share,
      name: File.basename(full_path),
      path: full_path,
      relative_path: relative,
      extension: is_dir ? nil : ext,
      content_type: is_dir ? 'directory' : classify_extension(ext),
      size: is_dir ? 0 : stat.size,
      directory: is_dir,
      file_modified_at: stat.mtime
    )
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
    Rails.logger.warn("ShareFile: skipping #{full_path}: #{e.message}")
    nil
  end

  # Human-readable file size
  def human_size
    return '-' if directory?
    ActionController::Base.helpers.number_to_human_size(size)
  end
end
