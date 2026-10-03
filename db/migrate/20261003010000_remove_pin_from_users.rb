# The PIN was stored but never used for login, and setting one returned a 500.
class RemovePinFromUsers < ActiveRecord::Migration[8.0]
  def up
    remove_column :users, :pin if column_exists?(:users, :pin)
  end

  def down
    add_column :users, :pin, :text unless column_exists?(:users, :pin)
  end
end
