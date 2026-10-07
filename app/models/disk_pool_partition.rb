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

  # The free space Greyhole leaves on every drive in its pool (GB), as Greyhole's own
  # examples do: a drive is never filled to the last byte.
  MINIMUM_FREE_GB = 10

  # Adds a drive to Greyhole's pool.
  def self.add!(path)
    create!(path: path, minimum_free: MINIMUM_FREE_GB)
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
