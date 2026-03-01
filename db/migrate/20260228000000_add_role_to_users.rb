class AddRoleToUsers < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:users, :role)
      add_column :users, :role, :string, default: 'user', null: false
    end

    # Migrate existing data: admin flag → role
    execute "UPDATE users SET role = 'admin' WHERE admin = TRUE"
    execute "UPDATE users SET role = 'user' WHERE admin = FALSE OR admin IS NULL"
  end

  def down
    remove_column :users, :role
  end
end
