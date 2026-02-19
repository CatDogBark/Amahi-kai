class AddSetupCompletedSetting < ActiveRecord::Migration[7.0]
  def up
    # Setting is stored in the settings table - we just ensure the row exists
    execute "INSERT IGNORE INTO settings (name, value, kind) VALUES ('setup_completed', 'false', 'general')"
  end

  def down
    execute "DELETE FROM settings WHERE name = 'setup_completed'"
  end
end
