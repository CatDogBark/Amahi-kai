# What the update check found for an installed app (docs/plans/apps.md, P4.9): a newer release or
# a newer build of its image, asked of its registry every 6 hours and with Check now, kept until
# the next check; and when it last asked, with why it couldn't when it couldn't. Safe to run again.
class AddVersionCheckToDockerApps < ActiveRecord::Migration[8.1]
  COLUMNS = { newer_tag: :string, newer_image: :string, newer_kind: :string, newer_notes: :string,
              versions_checked_at: :datetime, versions_error: :string }.freeze

  def change
    COLUMNS.each { |name, type| add_column :docker_apps, name, type unless column_exists?(:docker_apps, name) }
    add_column :docker_apps, :newer_major, :boolean, null: false, default: false unless column_exists?(:docker_apps, :newer_major)
  end
end
