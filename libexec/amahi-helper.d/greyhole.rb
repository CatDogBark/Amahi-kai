# frozen_string_literal: true

# Greyhole: its config and database, the pool drives, fsck and its trash.
module AmahiHelper
  GREYHOLE_BIN = '/usr/bin/greyhole'

  # Greyhole switched off on Disks → Greyhole Pool: it stays off after a restart (follow_need).
  GREYHOLE_OFF = '/var/lib/amahi-kai/greyhole-off'

  TRASH_STAGING = '.amahi-restore'

  # Uninstalling Greyhole or ZFS removes these packages (and nothing else; the PHP modules and
  # smartmontools other things use stay).
  GREYHOLE_PACKAGES = %w[greyhole].freeze

  GREYHOLE_SCHEMA = '/usr/share/greyhole/schema-mysql.sql'

  MYSQL = '/usr/bin/mysql'

  # Greyhole reaches its database as the app's MariaDB user, which already exists.
  GREYHOLE_DB_SQL = "CREATE DATABASE IF NOT EXISTS greyhole; " \
                    "GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;"

  # Greyhole runs as root and some of its settings run commands, so its config may only
  # hold the lines the app generates. Pool drives must be data drives under /mnt.
  GREYHOLE_LINES = [
    /\Adb_host = localhost\z/, /\Adb_user = amahi\z/, /\Adb_name = greyhole\z/, /\Adb_pass = [[:print:]]+\z/,
    %r{\Astorage_pool_drive = (/mnt/[A-Za-z0-9][A-Za-z0-9._-]{0,63}(?:/[A-Za-z0-9._-]+)*), min_free: \d{1,6}gb\z},
    /\Anum_copies\[[[:print:]]{1,64}\] = (?:\d{1,2}|max)\z/
  ].freeze

  GREYHOLE_SHARE_NAME = /\A[A-Za-z0-9][A-Za-z0-9 _-]{0,63}\z/


  add_operations(
    # /etc/greyhole.conf, root:amahi 0640 (it holds the database password).
    'greyhole.write_config' => {
      params: %w[content],
      validate: ->(a) { { content: greyhole_conf(a['content']) } },
      plan: lambda { |v|
        [[:install, GREYHOLE_CONF, v[:content], nil, '0640', APP_USER],
         [:install, GREYHOLE_POOL_CONF, greyhole_pool_lines(v[:content]), nil, '0644']]
      }
    },
    # Greyhole's database, and its schema once the package has put it in place.
    'greyhole.setup_database' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:greyhole_database]] }
    },
    # Tells Greyhole the drive mounted at one of its pool folders is the one to use there
    # (greyhole --replaced): it forgets the filesystem it recorded for that folder, and
    # restarts, recording this one. For a drive that was swapped or formatted, which
    # Greyhole otherwise refuses to use.
    'greyhole.replace_drive' => {
      params: %w[path],
      validate: ->(a) { installed!(GREYHOLE_BIN) && { path: mounted_greyhole_drive(a['path']) } },
      plan: ->(v) { [[GREYHOLE_BIN, "--replaced=#{v[:path]}"]] }
    },
    # Asks Greyhole to remove one of its drives (greyhole --remove), answering its question,
    # whether the drive is still there, from `available`: if it is (it must be mounted),
    # Greyhole first moves the file copies kept only on it to the other drives; if not, those
    # are lost and the other copies are made again. Greyhole then takes the drive out of
    # greyhole.conf itself and restarts. It exits 2, scheduling nothing, while an fsck is
    # pending.
    'greyhole.remove_drive' => {
      params: %w[path available],
      validate: lambda { |a|
        installed!(GREYHOLE_BIN)
        available = boolean(a, 'available')
        { path: available ? mounted_greyhole_drive(a['path']) : listed_greyhole_drive(a['path']), available: available }
      },
      plan: ->(v) { [[GREYHOLE_BIN, "--remove=#{v[:path]}", { stdin: v[:available] ? "yes\n" : "no\n" }]] }
    },
    # Asks Greyhole to check the pooled shares now (greyhole --fsck, queued for its daemon), so
    # it makes the copies they're short of: on a drive just added to the pool, or for a share
    # whose copies went up. Its daily job checks only when greyhole.conf has changed, the
    # next morning. Takes nothing from the app.
    'greyhole.fsck' => {
      params: [],
      validate: ->(_a) { installed!(GREYHOLE_BIN) && {} },
      plan: ->(_v) { [[GREYHOLE_BIN, '--fsck', '--dont-walk-metadata-store']] }
    },
    # Takes a share out of Greyhole's pool without losing files (greyhole --remove-share):
    # Greyhole moves the share's files from the pool drives back into its folder, then takes
    # the share out of greyhole.conf itself and restarts. The daemon does the moving, after
    # the work queued before it. Refused when the folder's disk has no room for them.
    'greyhole.remove_share' => {
      params: %w[share],
      validate: ->(a) { installed!(GREYHOLE_BIN) && share_pool_removal(a['share']) },
      plan: ->(v) { [[GREYHOLE_BIN, "--remove-share=#{v[:share]}"]] }
    },
    # Greyhole's trash (Disks → Pool Trash): it keeps a file deleted from a pooled share, or
    # the old version of one changed, in <drive>/.gh_trash/<share>/<path> on each drive that
    # had a copy. Restore puts it back into its share through Greyhole (greyhole --cp, which
    # makes its copies again), when the share is still pooled and has no file by that name
    # now; then the trash's copies go.
    'greyhole.trash_restore' => {
      params: %w[share path],
      validate: ->(a) { installed!(GREYHOLE_BIN) && trash_restore(a['share'], a['path']) },
      plan: ->(v) { [[:restore_from_trash, v[:share], v[:path], v[:copies]]] }
    },
    # Deletes one file from Greyhole's trash, every copy of it.
    'greyhole.trash_delete' => {
      params: %w[share path],
      validate: ->(a) { installed!(GREYHOLE_BIN) && trash_item(a['share'], a['path']) },
      plan: ->(v) { [[:remove_trash_copies, v[:share], v[:copies]]] }
    },
    # Empties Greyhole's trash on every pool drive (greyhole --empty-trash).
    'greyhole.trash_empty' => {
      params: [],
      validate: ->(_a) { installed!(GREYHOLE_BIN) && {} },
      plan: ->(_v) { [[GREYHOLE_BIN, '--empty-trash']] }
    },
    # Disks → Greyhole Pool's switch: off stops Greyhole and keeps it off after a restart
    # (GREYHOLE_OFF); on starts it, and at every boot, once its pool has a drive.
    'greyhole.switch' => {
      params: %w[on],
      validate: ->(a) { installed!(GREYHOLE_BIN) && { on: boolean(a, 'on') } },
      plan: ->(v) { [[:greyhole_switch, v[:on]]] }
    },
    # Greyhole runs, now and at boot, while its pool has a drive and it isn't switched off: run
    # after its install and each change to its config (the pool's first drive starts it, the last
    # one gone stops it), and at every System Update.
    'greyhole.follow_need' => {
      params: [],
      validate: ->(_a) { installed!(GREYHOLE_BIN) && {} },
      plan: ->(_v) { [[:greyhole_follow_need]] }
    },
    # Removes Greyhole (Disks → Greyhole Pool) when its config lists no drives and no share
    # keeping copies: the package, its config and its apt repository. Its database stays, so
    # installing it again picks up where it was.
    'greyhole.uninstall' => {
      params: [],
      validate: ->(_a) { installed!(GREYHOLE_BIN) && greyhole_removable! },
      plan: lambda { |_v|
        repository = APT_REPOSITORIES.fetch('greyhole')
        [['/usr/bin/systemctl', 'disable', '--now', 'greyhole.service', { allow_failure: true }],
         ['/usr/bin/apt-get', '-y', '-o', 'DPkg::Lock::Timeout=300', 'purge', *GREYHOLE_PACKAGES, { env: APT_ENV, stream: true }],
         [:remove_files, GREYHOLE_CONF, GREYHOLE_POOL_CONF, GREYHOLE_OFF, repository[:list], repository[:keyring]],
         # The package leaves systemd's unit for its init script loaded until a reload, and listed
         # as failed if Greyhole couldn't start (with no drives, it fails at every boot).
         ['/usr/bin/systemctl', 'daemon-reload', { allow_failure: true }],
         ['/usr/bin/systemctl', 'reset-failed', 'greyhole.service', { allow_failure: true }]]
      }
    },
  )

  class << self
    def greyhole_removable!
      lines = File.exist?(GREYHOLE_CONF) ? File.readlines(GREYHOLE_CONF, chomp: true) : []
      if lines.any? { |line| line.match?(/\A\s*storage_pool_drive\s*=/) }
        raise Refused, 'Greyhole still has drives in its pool; take them out on Disks → Greyhole Pool first'
      end
      if (share = lines.filter_map { |line| line[/\A\s*num_copies\[([^\]]+)\]/, 1] }.first)
        raise Refused, "the share #{share} still keeps copies with Greyhole; turn that off on Shares first"
      end
      {}
    end

    # The folders holding a pooled share's copies, one per mounted Greyhole drive
    # (<drive>/<share>), for an app's mounts; with +folder+, that folder in each
    # (<drive>/<share>/<folder>). One that's missing is made (amahi:users 2775, as Greyhole makes
    # them), through handles: a drive just added to the pool gets the share's copies after the
    # app's mounts are made, and the app sees them there.
    def greyhole_copies(share, folder = nil)
      raise Failed, "share #{share.inspect} can't be a folder on a pool drive" if %w[. ..].include?(share)

      greyhole_drives.select { |drive| mount_point?(drive) }.filter_map do |drive|
        parts = folder ? folder.split('/') : []
        levels = (0..parts.size).map { |count| ["#{drive}/#{share}", *parts.first(count)].join('/') }
        levels.each do |path|
          break if File.symlink?(path) # left alone, and not mounted
          next if File.exist?(path)

          do_mkdir_p(path)
          do_own_dir(path, APP_USER, USERS_GROUP, '2775')
        end
        copy = levels.last
        copy if folder ? real_folder?(copy) : File.directory?(copy) && !File.symlink?(copy)
      end.uniq
    end

    # Greyhole's storage pool drives, as greyhole.conf lists them (folders under DRIVES_ROOT).
    def greyhole_drives
      return [] unless File.exist?(GREYHOLE_CONF)
      drives = File.read(GREYHOLE_CONF).scan(/^\s*storage_pool_drive\s*=\s*([^,\n]+)/).flatten.map(&:strip)
      drives.select { |drive| normalized_path?(drive) && drive.start_with?("#{DRIVES_ROOT}/") && !drive.include?(',') }.uniq
    rescue SystemCallError
      []
    end

    # The shares greyhole.conf keeps copies of (num_copies[<name>]).
    def greyhole_shares
      return [] unless File.exist?(GREYHOLE_CONF)
      File.read(GREYHOLE_CONF).scan(/^\s*num_copies\[([^\]]+)\]/).flatten.map(&:strip).uniq
    rescue SystemCallError
      []
    end

    # A share Greyhole can take out of its pool: one it pools, with a plain name (Greyhole edits
    # greyhole.conf with the name as a pattern), whose folder's disk has room for all its
    # files. The room is Greyhole's own measure: every file in the folder, the ones on the
    # drives counted through the folder's links to them.
    def share_pool_removal(value)
      name = string(value, 'share', max: 64)
      raise Refused, "#{name} isn't a share Greyhole pools" unless greyhole_shares.include?(name)
      unless name.match?(GREYHOLE_SHARE_NAME)
        raise Refused, "Greyhole can only take shares named with letters, digits, spaces, - and _ out of its pool: rename #{name} first"
      end
      share = samba_shares[name.downcase] or raise Refused, "#{name} isn't in Samba's config"
      need = folder_size(share[:path])
      free = free_space(share[:path])
      if need > free
        raise Refused, "the share's folder doesn't have room for its files: #{gigabytes(need)} GB to move back, " \
                       "#{gigabytes(free)} GB free on its disk"
      end
      { share: name }
    end

    # The size of every file in a folder, following links to files (Greyhole's on the drives).
    def folder_size(path)
      total = 0
      Find.find(path) do |entry|
        stat = File.stat(entry)
        total += stat.size if stat.file?
      rescue SystemCallError
        next
      end
      total
    end

    # A file in Greyhole's trash: its share and path there, and its copies, one per pool
    # drive that has it (<drive>/.gh_trash/<share>/<path>, a file reached through no link).
    def trash_item(share_value, path_value)
      share = string(share_value, 'share', max: 64)
      raise Refused, "#{share.inspect} isn't a share name" if share.include?('/') || share.start_with?('.', '-')
      path = string(path_value, 'path', max: 4096)
      raise Refused, 'path must be relative, without . or .. or //' unless normalized_path?("/#{path}") && !path.start_with?('/')
      copies = greyhole_drives.filter_map do |drive|
        copy = "#{drive}/#{GREYHOLE_TRASH}/#{share}/#{path}"
        # its own real path: no link anywhere on the way, the drive's trash folder included
        copy if File.file?(copy) && !File.symlink?(copy) && File.realpath(copy) == copy
      rescue SystemCallError
        nil
      end
      raise Refused, "#{share}/#{path} isn't in the pool's trash" if copies.empty?
      { share: share, path: path, copies: copies }
    end

    # A trash file that can go back into its share: the share is still pooled, and has no file
    # by that name now.
    def trash_restore(share_value, path_value)
      item = trash_item(share_value, path_value)
      share = item[:share]
      raise Refused, "#{share} isn't in the pool any more: turn its copies back on to restore its files" unless greyhole_shares.include?(share)
      folder = samba_shares.dig(share.downcase, :path) or raise Refused, "#{share} isn't in Samba's config"
      target = "#{folder}/#{item[:path]}"
      raise Refused, "#{share} has a #{item[:path]} now: rename or move it, then restore" if File.exist?(target) || File.symlink?(target)
      item
    end

    # One of Greyhole's pool drives, as greyhole.conf lists it.
    def listed_greyhole_drive(value)
      value = string(value, 'path', max: 256)
      raise Refused, "#{value} isn't one of Greyhole's drives" unless greyhole_drives.include?(value)
      value
    end

    # A Greyhole pool drive with a filesystem mounted there now: the drive Greyhole is to use.
    def mounted_greyhole_drive(value)
      value = listed_greyhole_drive(value)
      raise Refused, "nothing is mounted at #{value}: mount the drive on Disks → Devices first" unless mount_point?(value)
      value
    end

    # --- Greyhole and packages ---

    def greyhole_conf(value)
      value = string(value, 'content', max: 64 * 1024)
      value.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        match = GREYHOLE_LINES.lazy.map { |re| line.match(re) }.find(&:itself)
        raise Refused, "greyhole.conf line #{line.sub(/\Adb_pass = .*/, 'db_pass = ...').inspect} is not one Amahi-kai writes" unless match
        pool = match[1] if match.size > 1 # storage_pool_drive's path
        raise Refused, "pool drive #{pool} must be a normalized path" if pool && !normalized_path?(pool)
      end
      value
    end

    # greyhole.conf's lines but the database's (db_host, db_user, db_pass, db_name).
    def greyhole_pool_lines(content)
      content.lines.reject { |line| line.strip.start_with?('db_') }.join
    end

    # Puts a file from Greyhole's trash back into its share: a copy of it, opened without
    # following links and checked to be the trash's file, is staged in a root-only folder on
    # its drive, and greyhole --cp puts that into the share, making its copies. Then the
    # trash's copies go.
    def do_restore_from_trash(share, path, copies)
      source = copies.first
      drive = greyhole_drives.find { |d| source.start_with?("#{d}/#{GREYHOLE_TRASH}/") } or raise Failed, "#{source} isn't in a pool drive's trash"
      root = "#{drive}/#{TRASH_STAGING}"
      Dir.mkdir(root, 0o700) unless File.exist?(root) || File.symlink?(root)
      raise Failed, "#{root} isn't a folder" if File.symlink?(root) || !File.directory?(root)
      stage = "#{root}/#{SecureRandom.hex(8)}"
      Dir.mkdir(stage, 0o700)
      staged = "#{stage}/#{File.basename(path)}"
      File.open(source, File::RDONLY | File::NOFOLLOW) do |src|
        raise Failed, "#{share}/#{path} moved while it was being restored" unless File.readlink("/proc/self/fd/#{src.fileno}") == source
        stat = src.stat
        raise Failed, "#{share}/#{path} isn't a file" unless stat.file?
        File.open(staged, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |dst|
          IO.copy_stream(src, dst)
          dst.chown(stat.uid, stat.gid)
          dst.chmod(stat.mode & 0o777)
        end
        File.utime(stat.atime, stat.mtime, staged)
      end
      dir = File.dirname(path)
      run_command([GREYHOLE_BIN, '--cp', staged, dir == '.' ? "#{share}/" : "#{share}/#{dir}/"])
      do_remove_trash_copies(share, copies)
    rescue SystemCallError => e
      raise Failed, "couldn't restore #{share}/#{path}: #{e.message}"
    ensure
      FileUtils.rm_rf(stage) if stage
    end

    # Deletes a trash file's copies, and the trash folders left empty, with find, which
    # doesn't follow links.
    def do_remove_trash_copies(share, copies)
      copies.each do |copy|
        drive = greyhole_drives.find { |d| copy.start_with?("#{d}/#{GREYHOLE_TRASH}/") } or next
        top = "#{drive}/#{GREYHOLE_TRASH}/#{share}"
        run_command(['/usr/bin/find', top, '-path', copy.gsub(/[\\*?\[\]]/) { |c| "\\#{c}" }, '-type', 'f', '-delete'])
        run_command(['/usr/bin/find', top, '-mindepth', '1', '-type', 'd', '-empty', '-delete'])
      end
      nil
    end

    def do_greyhole_follow_need
      { 'greyhole' => follow_need('greyhole.service', greyhole_drives.any? && !File.exist?(GREYHOLE_OFF)) }
    end

    # Asked for on the page, so a start or stop that fails says why.
    def do_greyhole_switch(on)
      if on
        raise Failed, 'Greyhole needs a drive in its pool to run: add one first' if greyhole_drives.empty?

        FileUtils.rm_f(GREYHOLE_OFF)
        switch_unit('greyhole.service', true)
      else
        do_install(GREYHOLE_OFF, "Switched off on Disks → Greyhole Pool\n", nil, '0644')
        switch_unit('greyhole.service', false)
      end
      { 'on' => on }
    end

    # 'on' when +unit+ was switched on, 'off' when switched off, nil when it's left as it was.
    def follow_need(unit, work)
      enabled = unit_state('is-enabled', unit) == 'enabled'
      if work && !enabled
        switch_unit(unit, true, allow_failure: true)
        'on'
      elsif !work && (enabled || unit_state('is-active', unit) == 'failed')
        switch_unit(unit, false, allow_failure: true)
        'off'
      end
    end

    def do_greyhole_database
      run_command([MYSQL, '-u', 'root', '--batch', '-e', GREYHOLE_DB_SQL])
      return nil unless File.exist?(GREYHOLE_SCHEMA)
      count = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'greyhole'"
      return 'schema already loaded' if capture([MYSQL, '-u', 'root', '--batch', '--skip-column-names', '-e', count]).to_i.positive?
      run_command([MYSQL, '-u', 'root', 'greyhole', { stdin: File.read(GREYHOLE_SCHEMA) }])
      nil
    end
  end
end
