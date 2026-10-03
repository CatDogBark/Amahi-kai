# A per-user token stored in each session at login. Changing the password changes
# it, which ends every other session for that user (see UserSession.find).
class AddSessionTokenToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :session_token, :string unless column_exists?(:users, :session_token)
  end

  def down
    remove_column :users, :session_token
  end
end
