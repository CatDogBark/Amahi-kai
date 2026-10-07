require 'open3'
require 'shell'

# Greyhole storage pooling. Installing it, its config and its service go through the
# root helper: packages.add_repository (Greyhole's apt repository, key fingerprint
# pinned), packages.install, greyhole.setup_database, greyhole.write_config (only the
# lines generate_config writes) and services.* for greyhole.service.
class Greyhole
  class GreyholeError < StandardError; end

  CONFIG_PATH = '/etc/greyhole.conf'
  PACKAGES = %w[php8.3-mbstring php8.3-mysql greyhole].freeze

  class << self
    def enabled?
      return false unless production?
      installed? && running?
    end

    def installed?
      return true unless production?
      output = `dpkg-query -W -f='${Status}' greyhole 2>/dev/null`.strip
      output == 'install ok installed'
    end

    def running?
      return false unless production?
      # Greyhole uses an LSB init script — systemctl is-active returns "active"
      # even when the daemon has exited. Check for the actual process instead, with pgrep
      # run directly: through a shell, the shell's own command line matches the pattern.
      stdout, _stderr, status = Open3.capture3('pgrep', '-f', 'greyhole --daemon')
      status.success? && stdout.strip.present?
    rescue SystemCallError
      false
    end

    def status
      return dummy_status unless production?
      {
        installed: installed?,
        running: running?,
        queue: queue_status,
        pool_drives: pool_drives
      }
    end

    # The one way to install Greyhole (Disks → Storage Pool and the setup wizard).
    # Reports progress, including apt's output, through the block. Raises GreyholeError.
    def install!(&progress)
      progress ||= proc { |_msg| } # no-op if no block given
      return true unless production?

      progress.call("Adding the Greyhole apt repository...")
      privileged('packages.add_repository', repository: 'greyhole')
      # The database and config exist before the package's install scripts run.
      progress.call("Preparing the Greyhole database...")
      privileged('greyhole.setup_database')
      progress.call("Writing the Greyhole config...")
      privileged('greyhole.write_config', content: generate_config)
      progress.call("Installing Greyhole and its PHP modules (this takes a few minutes)...")
      privileged('packages.install', packages: PACKAGES) { |line| progress.call("  #{line}") }
      progress.call("✓ Greyhole package installed")
      progress.call("Loading the database schema...")
      privileged('greyhole.setup_database')

      # Share settings for pooled shares (Share.samba_conf adds them once Greyhole is
      # installed); Samba picks up the vfs module on a restart.
      progress.call("Configuring Samba for Greyhole...")
      SambaService.push_config
      privileged('services.restart', service: 'smbd')

      progress.call("Enabling and starting Greyhole...")
      privileged('services.enable', service: 'greyhole')
      true
    end

    # Why Greyhole can't be uninstalled now, or nil when it can: nothing may still use it.
    def removal_blocker
      return 'Take its drives out of the storage pool first.' if DiskPoolPartition.exists?
      share = Share.where('disk_pool_copies > 0').order(:name).first
      return "The share #{share.name} keeps copies with Greyhole: turn that off on Shares first." if share
      nil
    end

    # Removes Greyhole when nothing uses it (removal_blocker), through the root helper, with
    # apt's output passed to the block, then takes its settings out of Samba's config.
    # Raises GreyholeError.
    def uninstall!(&progress)
      progress ||= proc { |_msg| }
      return true unless production?
      blocker = removal_blocker
      raise GreyholeError, blocker if blocker

      progress.call("Stopping Greyhole and removing it...")
      privileged('greyhole.uninstall') { |line| progress.call("  #{line}") }
      progress.call("Updating Samba's configuration...")
      SambaService.push_config
      privileged('services.restart', service: 'smbd')
      true
    end

    def start!
      return true unless production?
      service('services.start')
    end

    def stop!
      return true unless production?
      service('services.stop')
    end

    def restart!
      return true unless production?
      service('services.restart')
    end

    # The pool's drives, with their space and how Greyhole stands with each (drive_state).
    def pool_drives
      return dummy_pool_drives unless production?
      records = drive_records
      DiskPoolPartition.all.map do |part|
        usage = part.usage
        {
          path: part.path,
          minimum_free: part.minimum_free,
          total: usage[:total],
          free: usage[:free],
          used: usage[:used],
          state: drive_state(part.path, records)
        }
      end
    end

    # How Greyhole stands with the drive at a pool folder: :ok; :not_mounted (nothing is
    # mounted there, so Greyhole can't use it); :changed (a different filesystem than the one
    # Greyhole recorded there: the drive was swapped or formatted, and Greyhole won't use it
    # until it's told to, with accept_drive!); or :new (no record yet: Greyhole records this
    # one when it next starts).
    def drive_state(path, records = drive_records)
      uuid = mounted_uuid(path)
      return :not_mounted unless uuid
      return :new unless records.key?(path)
      records[path] == uuid ? :ok : :changed
    end

    # Greyhole's own record of the filesystem it uses at each pool folder, { path => UUID }
    # (blkid's): its sp_drives_definitions setting, a PHP-serialized array in its database,
    # which the app's database user may read. {} when it can't be read.
    def drive_records
      return {} unless production?
      value = ActiveRecord::Base.connection.select_value(
        "SELECT value FROM greyhole.settings WHERE name = 'sp_drives_definitions'"
      )
      parse_drive_records(value.to_s)
    rescue ActiveRecord::ActiveRecordError
      {}
    end

    # a:2:{s:14:"/mnt/storage-1";s:36:"<uuid>";...}: the paths, and their UUIDs (nil for a
    # drive recorded as gone, b:0).
    def parse_drive_records(text)
      text.scan(/s:\d+:"([^"]*)";(?:s:\d+:"([^"]*)"|b:0|i:\d+);/).to_h
    end

    # Tells Greyhole the drive mounted at +path+ (one of its pool folders) is the one to use
    # there, through the root helper (greyhole --replaced). It restarts Greyhole.
    def accept_drive!(path)
      return true unless production?
      privileged('greyhole.replace_drive', path: path.to_s)
      true
    end

    def queue_status
      return { pending: 0, last_action: nil } unless production?
      begin
        output = `greyhole --status 2>/dev/null`
        parse_queue_status(output)
      rescue StandardError
        { pending: 0, last_action: nil }
      end
    end

    # Writes /etc/greyhole.conf (root:amahi 0640: it holds the database password) and
    # restarts Greyhole if it's running. Returns false, with the reason logged, on failure.
    def configure!
      return true unless production?
      privileged('greyhole.write_config', content: generate_config)
      restart! if running?
      true
    rescue GreyholeError => e
      Rails.logger.error("Greyhole configure error: #{e.message}")
      false
    end

    def generate_config
      lines = []
      lines << "# Greyhole configuration - generated by Amahi-kai"
      lines << "# Do not edit manually - changes will be overwritten"
      lines << ""
      db_pass = ENV.fetch('DATABASE_PASSWORD', '')
      lines << "db_host = localhost"
      lines << "db_user = amahi"
      lines << "db_pass = #{db_pass}" if db_pass.present?
      lines << "db_name = greyhole"
      lines << ""

      # Storage pool drives
      DiskPoolPartition.all.each do |part|
        lines << "storage_pool_drive = #{part.path}, min_free: #{part.minimum_free}gb"
      end
      lines << ""

      # Share settings
      Share.where('disk_pool_copies > 0').each do |share|
        copies = share.disk_pool_copies
        copies_str = copies >= 99 ? 'max' : copies.to_s
        lines << "num_copies[#{share.name}] = #{copies_str}"
      end

      lines.join("\n")
    end

    private

    def privileged(operation, **args, &block)
      Privileged.call(operation, **args, &block)
    rescue Privileged::Error => e
      raise GreyholeError, e.message
    end

    def service(operation)
      Privileged.call(operation, service: 'greyhole')
      true
    rescue Privileged::Error => e
      Rails.logger.error("Greyhole: #{operation} failed: #{e.message}")
      false
    end

    def production?
      defined?(Rails) && Rails.env.production?
    end

    # The UUID of the filesystem mounted at +path+, or nil if nothing is.
    def mounted_uuid(path)
      out, _err, status = Open3.capture3('findmnt', '-n', '-o', 'UUID', '--mountpoint', path)
      status.success? ? out.strip.presence : nil
    rescue SystemCallError
      nil
    end

    def dummy_status
      {
        installed: false,
        running: false,
        queue: { pending: 0, last_action: nil },
        pool_drives: dummy_pool_drives
      }
    end

    def dummy_pool_drives
      DiskPoolPartition.all.map do |part|
        {
          path: part.path,
          minimum_free: part.minimum_free,
          total: 500_000_000_000,
          free: 250_000_000_000,
          used: 250_000_000_000,
          state: :ok
        }
      end
    end

    def parse_queue_status(output)
      pending = output.scan(/(\d+) pending/).flatten.first.to_i rescue 0
      { pending: pending, last_action: nil }
    end
  end
end
