class CreateDiskPoolPartitions < ActiveRecord::Migration[5.1]
  def change
    create_table :disk_pool_partitions do |t|
      t.string :path, null: false
      t.integer :minimum_free, default: 10
      t.timestamps
    end

    add_index :disk_pool_partitions, :path, unique: true
  end
end
