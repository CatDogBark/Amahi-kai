class DiskPoolPartition < ApplicationRecord
  validates :path, presence: true, uniqueness: true
  # Greyhole pools data drives mounted under /mnt; the root helper writes no other path
  # into greyhole.conf.
  validates :path, format: { with: %r{\A/mnt/[A-Za-z0-9][A-Za-z0-9._-]*(?:/(?!\.\.?(?:/|\z))[A-Za-z0-9._-]+)*\z},
                             message: 'must be a data drive mounted under /mnt' }
  validates :minimum_free, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def self.pool_paths
    pluck(:path)
  end

  # The free space Greyhole leaves on a drive, in GB: 10, or 5% of a smaller drive (at least
  # 1), so a small drive isn't full from the start (min_free larger than the drive left an
  # 8 GB drive unused).
  def self.default_minimum_free(path)
    stat = Sys::Filesystem.stat(path)
    gigabytes = stat.block_size * stat.blocks / 1024.0**3
    (gigabytes * 0.05).floor.clamp(1, 10)
  rescue Errno::ENOENT, Errno::EACCES, Sys::Filesystem::Error
    10
  end

  # Adds a drive to Greyhole's pool, leaving the default free space for its size.
  def self.add!(path)
    create!(path: path, minimum_free: default_minimum_free(path))
  end

  def usage
    begin
      stat = Sys::Filesystem.stat(path)
      {
        total: stat.block_size * stat.blocks,
        free: stat.block_size * stat.blocks_available,
        used: stat.block_size * (stat.blocks - stat.blocks_available)
      }
    rescue Errno::ENOENT, Errno::EACCES, Sys::Filesystem::Error
      { total: 0, free: 0, used: 0 }
    end
  end
end
