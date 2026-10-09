# The ZFS pool a share lives on (its folder is in the pool's shares dataset), or nil for a share
# on the system disk or in the Greyhole pool.
class AddZfsPoolToShares < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:shares, :zfs_pool)

    add_column :shares, :zfs_pool, :string
  end

  def down
    remove_column :shares, :zfs_pool if column_exists?(:shares, :zfs_pool)
  end
end
