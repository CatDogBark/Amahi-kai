# Deleting a user left its share permissions (cap_accesses, cap_writers) behind; User takes
# them along now. These are the ones already left, and any whose share is gone. Running it
# again finds none.
class DropPermissionsOfDeletedUsers < ActiveRecord::Migration[8.1]
  def up
    %w[cap_accesses cap_writers].each do |table|
      execute(<<~SQL)
        DELETE FROM #{table}
        WHERE user_id IS NULL OR share_id IS NULL
           OR user_id NOT IN (SELECT id FROM users) OR share_id NOT IN (SELECT id FROM shares)
      SQL
    end
  end

  # The rows pointed at nothing; there's nothing to bring back.
  def down; end
end
