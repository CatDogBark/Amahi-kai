class DiskPoolPartition < ApplicationRecord
  validates :path, presence: true, uniqueness: true
  validates :minimum_free, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def self.pool_paths
    pluck(:path)
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
