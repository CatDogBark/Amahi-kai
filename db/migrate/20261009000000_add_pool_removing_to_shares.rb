# A share Greyhole is moving back off the pool (its copies turned Off), shown as Removing
# until it's done.
class AddPoolRemovingToShares < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:shares, :pool_removing)

    add_column :shares, :pool_removing, :boolean, default: false, null: false
  end

  def down
    remove_column :shares, :pool_removing if column_exists?(:shares, :pool_removing)
  end
end
