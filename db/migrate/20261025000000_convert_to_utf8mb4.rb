# MariaDB's three-byte utf8, which production connected with, holds no character past U+FFFF:
# a name with an emoji in it wasn't saved, and a file whose name has one stayed out of the
# search index. The database and its tables move to utf8mb4 (config/database.yml connects
# with it now). Only the tables with a table or column not on it yet are converted, so running
# it again does nothing; SQLite (the specs, development) has nothing to convert.
class ConvertToUtf8mb4 < ActiveRecord::Migration[8.1]
  CHARSET = 'utf8mb4'.freeze
  COLLATION = 'utf8mb4_general_ci'.freeze

  def up
    return unless connection.adapter_name.match?(/mysql|maria/i)

    database = connection.current_database
    execute("ALTER DATABASE #{quote_table_name(database)} CHARACTER SET #{CHARSET} COLLATE #{COLLATION}")
    tables = select_values(<<~SQL)
      SELECT DISTINCT t.table_name FROM information_schema.tables t
      LEFT JOIN information_schema.columns c ON c.table_schema = t.table_schema AND c.table_name = t.table_name
      WHERE t.table_schema = #{quote(database)} AND t.table_type = 'BASE TABLE'
        AND (t.table_collation NOT LIKE '#{CHARSET}%' OR (c.character_set_name IS NOT NULL AND c.character_set_name <> '#{CHARSET}'))
    SQL
    tables.each do |table|
      execute("ALTER TABLE #{quote_table_name(table)} CONVERT TO CHARACTER SET #{CHARSET} COLLATE #{COLLATION}")
    end
  end

  # Nothing to undo: utf8mb4 holds everything utf8 did.
  def down; end
end
