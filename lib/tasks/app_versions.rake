require 'app_update_check'

namespace :apps do
  # amahi-kai-app-versions.timer runs it every 6 hours, as the app's user (docs/plans/apps.md, P4.9)
  desc "Check every installed app's image for a newer version, and keep what's found"
  task check_versions: :environment do
    apps = AppUpdateCheck.installed
    AppUpdateCheck.run(apps)
    apps.each(&:reload)
    puts "Checked #{apps.size} app(s): " \
         "#{apps.count { |app| app.newer_found }} with a newer version, #{apps.count { |app| app.versions_error.present? }} couldn't be asked"
  end
end
