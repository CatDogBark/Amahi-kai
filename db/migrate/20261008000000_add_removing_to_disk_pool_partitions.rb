# A drive Greyhole is moving files off (Remove from the pool), shown as Removing until it's done.
class AddRemovingToDiskPoolPartitions < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:disk_pool_partitions, :removing)

    add_column :disk_pool_partitions, :removing, :boolean, default: false, null: false
  end

  def down
    remove_column :disk_pool_partitions, :removing if column_exists?(:disk_pool_partitions, :removing)
  end
end
