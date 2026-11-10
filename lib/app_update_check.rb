require 'app_versions'
require 'app_catalog'

# Whether each installed app has a newer version (docs/plans/apps.md, P4.9), asked of its image's
# registry: a newer release of the tag it runs, by the tag's shape (AppVersions.newest: 12.1
# finds 12.4, 1.27.3-rootless finds 28.3.0-rootless, with a word that it's a new major version),
# or a newer build of the same tag. A catalog app's version floats so on its manifest's tag (the
# catalog's signature covers what it's allowed to do, not each version); an app of your own
# follows the tag its file names. A private image's lookups go through the helper with its token
# (RegistryTokens).
#
# What it finds is kept on the app's record (newer_*, versions_checked_at, versions_error), shown
# where updates show (DockerApp#newer_found); nothing is updated. It runs every 6 hours
# (amahi-kai-app-versions.timer: rails apps:check_versions) and with Check now, which waits for
# the answers only a while (CHECK_NOW_WAIT): one that comes later is still kept.
class AppUpdateCheck
  CHECK_NOW_WAIT = 20

  class << self
    # The apps that run, or ran: what Install made a record of.
    def installed
      DockerApp.where(status: %w[running stopped error]).to_a
    end

    # Checks +apps+ at once, each in a thread of its own, and waits up to +wait+ seconds for them
    # (nil: for every one).
    def run(apps = installed, wait: nil)
      threads = apps.map { |app| Thread.new { check(app) } }
      deadline = wait && (clock + wait)
      threads.each { |thread| deadline ? thread.join([deadline - clock, 0].max) : thread.join }
      threads.count(&:alive?)
    end

    # One app's check, kept on its record. The answer, AppVersions::Result, or nil when the
    # registry couldn't be asked (the record says why).
    def check(app, versions: AppVersions.new(tokens: RegistryTokens))
      entry = AppCatalog.find(app.identifier)
      found = versions.check_image(app.image, releases: entry&.dig(:releases), id: app.identifier)
      newer = found unless found.kind == :current
      keep(app, newer_tag: newer&.latest, newer_image: newer&.image, newer_kind: newer&.kind&.to_s, newer_major: newer&.major == true,
                newer_notes: newer&.notes, versions_error: nil)
      found
    rescue AppVersions::Private => e
      keep(app, versions_error: "#{e.message}. If it's private, add a token for #{e.place} on Private images (under Apps).".truncate(250))
      nil
    rescue StandardError => e
      keep(app, versions_error: e.message.to_s.truncate(240))
      nil
    end

    private

    # Written with a connection of the thread's own; what was found before stays when the
    # registry couldn't be asked.
    def keep(app, fields)
      ActiveRecord::Base.connection_pool.with_connection do
        app.update_columns(fields.merge(versions_checked_at: Time.current))
      end
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("AppUpdateCheck: #{app.identifier}: #{e.message}")
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
