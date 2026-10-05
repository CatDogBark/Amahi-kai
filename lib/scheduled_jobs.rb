# ScheduledJobs — the jobs that run on their own, for the dashboard's Jobs card and
# Settings → Jobs: Amahi-kai's systemd timers, Ubuntu's automatic security updates and its
# monthly ZFS scrub.
#
# Read live, without root: `systemctl list-timers -o json` gives each timer's last and next
# run as Unix times in microseconds (systemd's `show` prints those as local text), and
# `systemctl show` how the job's last run ended. Commands run as argument lists.

require 'json'
require 'open3'
require 'time'

class ScheduledJobs
  # timer   — the systemd timer (without .timer); its service has the same name
  # check   — listed only when this file exists
  CATALOG = [
    { key: 'storage-check', name: 'Storage health check', timer: 'amahi-kai-storage-check', schedule: 'Every 15 minutes',
      about: "Reads the pools and every drive's SMART data for the alerts" },
    { key: 'indexer', name: 'File search index', timer: 'amahi-kai-indexer', schedule: 'Every 10 minutes',
      about: 'Adds new and changed files in the shares to the search' },
    { key: 'snapshots', name: 'Pool snapshots', timer: 'amahi-kai-snapshots', schedule: 'Every hour',
      check: '/usr/sbin/zpool',
      about: "Takes each pool's hourly and daily snapshots and removes the oldest beyond what it keeps" },
    { key: 'app-backups', name: 'App update copies', timer: 'amahi-kai-app-backups', schedule: 'Daily',
      check: '/usr/bin/docker',
      about: "Deletes each app's copy from before its last update once it's 30 days old (Undo update)" },
    { key: 'update-check', name: 'Check for updates', timer: 'amahi-kai-update-check', schedule: 'Every 6 hours',
      about: 'Asks GitHub whether an update is waiting; never installs one' },
    { key: 'security-updates', name: 'Security updates', timer: 'apt-daily-upgrade', schedule: 'Daily',
      check: '/usr/bin/unattended-upgrade',
      about: "Ubuntu's unattended-upgrades installs security fixes, when the security audit has turned it on" }
  ].freeze

  # result: :ok, :failed, :running, or nil when it hasn't run yet.
  Job = Struct.new(:key, :name, :about, :schedule, :last_run, :next_run, :result, keyword_init: true)

  class << self
    # The jobs installed here, in CATALOG order, then the pool scrub if ZFS is installed.
    def all(health: StorageHealth.load)
      entries = CATALOG.select { |e| e[:check].nil? || File.exist?(e[:check]) }
      services = service_states(entries.map { |e| "#{e[:timer]}.service" })
      times = timer_times(entries.map { |e| "#{e[:timer]}.timer" })
      jobs = entries.filter_map do |entry|
        state = services["#{entry[:timer]}.service"]
        next unless state && state['LoadState'] == 'loaded'
        last, upcoming = times.fetch("#{entry[:timer]}.timer", [])
        Job.new(**entry.slice(:key, :name, :about, :schedule), last_run: last, next_run: upcoming,
                result: result(state, last))
      end
      [*jobs, scrub_job(health)].compact
    end

    private

    # { 'x.timer' => [last run, next run] } from list-timers' JSON; {} if it can't be read.
    def timer_times(timers)
      out, _err, status = Open3.capture3('systemctl', 'list-timers', '--all', '--output=json', *timers)
      return {} unless status.success?
      JSON.parse(out).to_h { |t| [t['unit'], [usec_time(t['last']), usec_time(t['next'])]] }
    rescue SystemCallError, JSON::ParserError
      {}
    end

    # { 'x.service' => { 'LoadState' =>, 'ActiveState' =>, 'Result' => } }, one `show` for all.
    def service_states(units)
      out, _err, _status = Open3.capture3('systemctl', 'show', '--property=Id,LoadState,ActiveState,Result', *units)
      out.split(/\n\n/).map { |block| block.lines.to_h { |line| line.chomp.split('=', 2) } }.index_by { |props| props['Id'] }
    rescue SystemCallError
      {}
    end

    def usec_time(value)
      value.is_a?(Integer) && value.positive? ? Time.at(value / 1_000_000) : nil
    end

    def result(state, last)
      return :running if state['ActiveState'] == 'activating'
      return nil unless last
      state['Result'] == 'success' ? :ok : :failed
    end

    # Ubuntu's ZFS package scrubs every healthy pool on the second Sunday of each month; the
    # pools' last scrubs come from the storage health check.
    def scrub_job(health)
      upcoming = StoragePools.next_scrub or return nil
      scans = health.pools.map { |pool| pool.scan.to_s }
      finished = scans.filter_map { |scan| scan[/\Ascrub repaired .* on (.+)\z/, 1] }.filter_map { |at| parse_time(at) }
      result = if scans.any? { |scan| scan.start_with?('scrub in progress') } then :running
               elsif finished.empty? then nil
               elsif scans.any? { |scan| scan[/\Ascrub repaired \S+ in .* with (\d+) errors/, 1].to_i.positive? } then :failed
               else :ok
               end
      Job.new(key: 'zfs-scrub', name: 'Pool scrub', schedule: 'Second Sunday of each month, 00:24',
              about: "Ubuntu's ZFS schedule reads every block of each healthy pool and repairs what it can" \
                     "#{' (no pools yet)' if health.pools.empty?}",
              last_run: finished.max, next_run: upcoming, result: result)
    end

    def parse_time(value)
      Time.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
