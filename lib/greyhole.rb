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
      SystemInfo.package_installed?('greyhole')
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
      sync_removals!
      records = drive_records
      DiskPoolPartition.all.map do |part|
        usage = part.usage
        {
          path: part.path,
          minimum_free: part.minimum_free,
          total: usage[:total],
          free: usage[:free],
          used: usage[:used],
          state: drive_state(part.path, records),
          removing: part.removing?
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

    # Takes a drive out of Greyhole's pool without losing files: Greyhole first moves the
    # copies kept only on it to the other drives, and the drive stays in the pool, marked
    # removing, until Greyhole is done (sync_removals!). A drive holding none of the shares'
    # files leaves at once. Returns :removed or :removing; raises GreyholeError when it can't
    # be removed safely now (drive_removal_blocker).
    def remove_drive!(path)
      part = DiskPoolPartition.find_by(path: path.to_s) or raise GreyholeError, "#{path} isn't in the pool"
      return :removing if part.removing?
      unless installed? && holds_files?(part)
        part.destroy
        configure! if installed?
        return :removed
      end
      blocker = drive_removal_blocker(part)
      raise GreyholeError, blocker if blocker
      begin
        privileged('greyhole.remove_drive', path: part.path, available: mounted_uuid(part.path).present?)
      rescue GreyholeError => e
        raise unless e.message.include?('exited 2')
        raise GreyholeError, "Greyhole is still checking the pool's files (fsck). Remove the drive once it's done."
      end
      part.update!(removing: true)
      :removing
    end

    # Why a drive holding files can't be removed now, or nil: the files need another drive to
    # go to, room there, and Greyhole running to move them.
    def drive_removal_blocker(part)
      others = DiskPoolPartition.where.not(id: part.id).where(removing: false).to_a
      return "It's the pool's only drive, so Greyhole has nowhere to move its files. Add another drive first." if others.empty?
      return "Start Greyhole first: it's what moves the drive's files to the other drives." unless running?
      return nil unless mounted_uuid(part.path) # a drive that's gone has nothing to move

      need = part.usage[:used].to_i
      room = others.sum { |other| [other.usage[:free].to_i - (other.minimum_free * 1024**3), 0].max }
      return nil if need <= room
      size = ->(bytes) { ActiveSupport::NumberHelper.number_to_human_size(bytes) }
      "The other drives don't have room for its files (#{size.call(need)} to move, #{size.call(room)} free above what Greyhole keeps free)."
    end

    # Whether any pooled share has files on the drive. A drive that isn't mounted, or a folder
    # that can't be read, counts as holding them.
    def holds_files?(part)
      return true unless mounted_uuid(part.path)
      Share.where('disk_pool_copies > 0').pluck(:name).any? do |name|
        dir = File.join(part.path, name)
        File.directory?(dir) && Dir.children(dir).any?
      end
    rescue SystemCallError
      true
    end

    # Drives and shares Greyhole has finished removing (it takes them out of greyhole.conf
    # itself) leave the pool here too: a drive's record goes, a share's copies turn Off. Runs
    # before the config is written, so they aren't put back.
    def sync_removals!
      return unless production?
      removing = DiskPoolPartition.where(removing: true).to_a
      if removing.any? && (listed = configured_drives)
        removing.reject { |part| listed.include?(part.path) }.each(&:destroy)
      end
      shares = Share.where(pool_removing: true).to_a
      if shares.any? && (listed = configured_shares)
        shares.reject { |share| listed.include?(share.name) }.each { |share| share.update!(disk_pool_copies: 0, pool_removing: false) }
      end
    end

    # The pool drives greyhole.conf lists now (the app may read it), or nil if it can't be read.
    def configured_drives
      File.read(CONFIG_PATH).scan(/^\s*storage_pool_drive\s*=\s*([^,\n]+)/).flatten.map(&:strip)
    rescue SystemCallError
      nil
    end

    # The shares greyhole.conf keeps copies of now, or nil if it can't be read.
    def configured_shares
      File.read(CONFIG_PATH).scan(/^\s*num_copies\[([^\]]+)\]/).flatten.map(&:strip)
    rescue SystemCallError
      nil
    end

    # Turns a share's pool off without losing files: Greyhole moves the share's files from the
    # pool drives back into its folder, and the share stays pooled, marked removing, until
    # it's done (sync_removals!). A share with no files on the drives turns Off at once.
    # Returns :removed or :removing; raises GreyholeError when it can't now (the helper
    # refuses when the folder's disk has no room for the files).
    def remove_share!(share)
      return :removing if share.pool_removing?
      unless installed? && share_on_drives?(share)
        share.update!(disk_pool_copies: 0)
        configure! if installed?
        return :removed
      end
      raise GreyholeError, "Start Greyhole first: it's what moves the share's files back into its folder." unless running?
      privileged('greyhole.remove_share', share: share.name)
      share.update!(pool_removing: true)
      :removing
    end

    # Whether the share has files on a pool drive. A folder that can't be read counts.
    def share_on_drives?(share)
      DiskPoolPartition.pluck(:path).any? do |drive|
        dir = File.join(drive, share.name)
        File.directory?(dir) && Dir.children(dir).any?
      end
    rescue SystemCallError
      true
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
        parse_queue_status(Shell.output('greyhole', '--status'))
      rescue StandardError
        { pending: 0, last_action: nil }
      end
    end

    # Writes /etc/greyhole.conf (root:amahi 0640: it holds the database password) and
    # restarts Greyhole if it's running. Returns false, with the reason logged, on failure.
    def configure!
      return true unless production?
      sync_removals!
      privileged('greyhole.write_config', content: generate_config)
      restart! if running?
      true
    rescue GreyholeError => e
      Rails.logger.error("Greyhole configure error: #{e.message}")
      false
    end

    # Has Greyhole check the pooled shares now, making the copies they're short of (a drive
    # just added, a share's copies gone up), instead of at its next daily job. Only while it
    # runs; a failure is logged, and the daily job still does it. True if it was asked.
    def check_pool!
      return false unless installed? && running?
      privileged('greyhole.fsck')
      true
    rescue GreyholeError => e
      Rails.logger.error("Greyhole: the pool check didn't start: #{e.message}")
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
          state: :ok,
          removing: part.removing?
        }
      end
    end

    def parse_queue_status(output)
      pending = output.scan(/(\d+) pending/).flatten.first.to_i rescue 0
      { pending: pending, last_action: nil }
    end
  end
end
