# A pool drive Greyhole is removing (moving the files kept only on it to the other drives)
# stays in the pool, marked removing, until Greyhole is done and has taken it out of
# greyhole.conf.
class AddRemovingToDiskPoolPartitions < ActiveRecord::Migration[8.0]
  def change
    add_column :disk_pool_partitions, :removing, :boolean, default: false, null: false
  end
end
