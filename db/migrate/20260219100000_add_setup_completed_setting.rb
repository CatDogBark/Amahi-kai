class AddSetupCompletedSetting < ActiveRecord::Migration[7.0]
  def up
    # Setting is stored in the settings table - ensure the row exists
    # Use INSERT OR IGNORE for SQLite, INSERT IGNORE for MySQL/MariaDB
    if ActiveRecord::Base.connection.adapter_name =~ /sqlite/i
      execute "INSERT OR IGNORE INTO settings (name, value, kind) VALUES ('setup_completed', 'false', 'general')"
    else
      execute "INSERT IGNORE INTO settings (name, value, kind) VALUES ('setup_completed', 'false', 'general')"
    end
  end

  def down
    execute "DELETE FROM settings WHERE name = 'setup_completed'"
  end
end
