# Tables left from the original Amahi platform (web apps, plugins, firewall rules,
# app databases, monitored servers). Nothing in Amahi-kai reads or writes them.
class DropUnusedLegacyTables < ActiveRecord::Migration[8.1]
  TABLES = %i[app_dependencies apps dbs firewalls plugins servers webapp_aliases webapps].freeze

  def up
    # if_exists: MariaDB can't roll DDL back, so a rerun after a partial failure must work.
    TABLES.each { |t| drop_table t, if_exists: true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
