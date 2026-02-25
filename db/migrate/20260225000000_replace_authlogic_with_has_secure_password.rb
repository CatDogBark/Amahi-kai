class ReplaceAuthlogicWithHasSecurePassword < ActiveRecord::Migration[8.0]
  def change
    # has_secure_password expects a `password_digest` column
    add_column :users, :password_digest, :string

    # Remove Authlogic-specific columns
    remove_column :users, :crypted_password, :string
    remove_column :users, :password_salt, :string
    remove_column :users, :persistence_token, :string

    # Keep these — useful tracking columns
    # login_count, last_request_at, last_login_at, current_login_at,
    # last_login_ip, current_login_ip
  end
end
