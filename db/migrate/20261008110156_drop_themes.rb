# The theme system went in #102 (one look, no themes): its table and its setting go.
class DropThemes < ActiveRecord::Migration[8.1]
  def up
    # if_exists: MariaDB can't roll DDL back, so a rerun after a partial failure must work.
    drop_table :themes, if_exists: true
    execute("DELETE FROM settings WHERE name = 'theme'")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
