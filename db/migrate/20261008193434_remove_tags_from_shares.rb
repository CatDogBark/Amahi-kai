# Share tags went in #104, and the last code that wrote them in #105 (now running), so their
# column goes.
class RemoveTagsFromShares < ActiveRecord::Migration[8.1]
  def up
    # MariaDB can't roll DDL back, so a rerun after a partial failure must work.
    remove_column :shares, :tags if column_exists?(:shares, :tags)
  end

  def down
    add_column :shares, :tags, :string, default: '' unless column_exists?(:shares, :tags)
  end
end
