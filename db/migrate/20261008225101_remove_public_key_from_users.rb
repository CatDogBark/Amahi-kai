# Users' SSH public keys: web users get no shell, and the code that saved and installed the
# keys went long ago, so the column goes.
class RemovePublicKeyFromUsers < ActiveRecord::Migration[8.1]
  def up
    # MariaDB can't roll DDL back, so a rerun after a partial failure must work.
    remove_column :users, :public_key if column_exists?(:users, :public_key)
  end

  def down
    add_column :users, :public_key, :text unless column_exists?(:users, :public_key)
  end
end
