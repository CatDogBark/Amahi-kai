# frozen_string_literal: true

# Sharing: user accounts, share folders, Samba's config and the trash.
module AmahiHelper
  SMB_CONF = '/etc/samba/smb.conf'

  LMHOSTS = '/etc/samba/lmhosts'

  TESTPARM = '/usr/bin/testparm'

  # Samba's recycle bin in each share that isn't pooled (Share#share_conf), and how many days
  # the Trash keeps files (written by trash.set_days; 30 when it isn't there).
  RECYCLE_BIN = '.recycle'

  TRASH_DAYS = '/etc/amahi-kai/trash-days'

  TRASH_DEFAULT_DAYS = 30

  # Greyhole's weekly job: its file check, and a report of its usage stats to greyhole.net,
  # which Amahi-kai takes out (do_stop_greyhole_stats).
  GREYHOLE_WEEKLY_CRON = '/etc/cron.weekly/greyhole'

  SAMBA_SPECIAL_SECTIONS = %w[global homes printers print$].freeze

  # --- Samba config checks ---------------------------------------------------------

  # Samba runs as root, and its config can make it run commands, load code and change
  # identities, so only the parameters listed here are accepted: the ones Share.samba_conf
  # writes, and a few a share's Advanced settings may add (masks and modes, hidden and vetoed
  # files, the Apple and recycle modules' own). Every other parameter is refused, whatever it
  # does. Names are compared the way Samba does: case and spaces don't count ("Read Only" is
  # "readonly"), and both the app's spelling and testparm's canonical one are listed
  # ("writeable" comes back as "read only").
  SAMBA_GLOBAL_PARAMS = %w[
    workgroup serverstring netbiosname loadprinters printing printcapname disablespoolss logfile loglevel
    maxlogsize preferredmaster oslevel timeserver unixextensions smb1unixextensions security largereadwrite
    encryptpasswords doscharset unixcharset guestaccount maptoguest winssupport clientlanmanauth hostsallow
    interfaces bindinterfacesonly widelinks followsymlinks allowinsecurewidelinks idmapconfig*:backend
  ].freeze

  SAMBA_SHARE_PARAMS = %w[
    comment path directory writeable writable readonly browseable browsable available validusers invalidusers
    writelist readlist guestok guestonly createmask forcecreatemode directorymask forcedirectorymode vfsobjects
    dfreecommand hidedotfiles hidefiles vetofiles deletevetofiles hideunreadable hideunwriteablefiles casesensitive
    defaultcase preservecase shortpreservecase manglednames storedosattributes maparchive maphidden mapsystem
    mapreadonly dosfilemode easupport inheritpermissions inheritacls aclallowexecutealways oplocks level2oplocks
    kerneloplocks strictlocking posixlocking strictallocate usesendfile maxconnections volume accessbasedshareenum
    deletereadonly
  ].freeze

  # The modules' own settings, "module:name"; shadow_copy2's point at folders, so they stay out.
  SAMBA_MODULE_PARAMS = %w[fruit: recycle: streams_xattr: catia: full_audit: acl_xattr: worm: readonly: crossrename:].freeze

  SAMBA_VFS_MODULES = %w[
    greyhole recycle fruit streams_xattr catia acl_xattr shadow_copy2 full_audit dirsort worm readonly crossrename
  ].freeze

  # Global values pinned to what Share.header_workgroup writes: no printing, no SMB1 unix
  # extensions (they let a client make links), the guest account nobody.
  SAMBA_PINNED = {
    'guestaccount' => 'nobody', 'unixextensions' => 'no', 'smb1unixextensions' => 'no', 'loadprinters' => 'no',
    'printing' => 'bsd', 'printcapname' => '/dev/null', 'disablespoolss' => 'yes'
  }.freeze

  # Samba's defaults differ from these, so a config must say them: the raw one, and testparm's
  # output, which leaves out parameters at their default (unix extensions has two names).
  SAMBA_REQUIRED = {
    'unix extensions = no' => %w[unixextensions smb1unixextensions], 'load printers = no' => %w[loadprinters],
    'printing = bsd' => %w[printing], 'printcap name = /dev/null' => %w[printcapname],
    'disable spoolss = yes' => %w[disablespoolss]
  }.freeze

  # Samba's dfree command for pooled shares: Amahi-kai's, which reads GREYHOLE_POOL_CONF
  # (greyhole-dfree reads greyhole.conf, which the people connected can't).
  GREYHOLE_DFREE = "#{APP_DIR}/libexec/amahi-dfree"


  add_operations(
    # A Linux account for a web user: primary group users, no shell, password locked
    # (Samba has its own password, set with users.set_password), and no home folder: users
    # keep their files in shares (there's no [homes] share).
    'users.create' => {
      params: %w[login name],
      validate: ->(a) { { login: new_login(a['login']), name: gecos(a['name']) } },
      plan: ->(v) { [['/usr/sbin/useradd', '--no-create-home', '-g', USERS_GROUP, '-s', NOLOGIN, '-c', v[:name], v[:login]]] }
    },
    # The Samba password. pdbedit adds the Samba user or changes its password; -t reads
    # the password twice from stdin.
    'users.set_password' => {
      params: %w[login password],
      validate: ->(a) { { login: app_login(a['login']), password: password(a['password']) } },
      plan: ->(v) { [['/usr/bin/pdbedit', '-d0', '-t', '-a', '-u', v[:login], { stdin: "#{v[:password]}\n" * 2 }]] }
    },
    'users.set_name' => {
      params: %w[login name],
      validate: ->(a) { { login: app_login(a['login']), name: gecos(a['name']) } },
      plan: ->(v) { [['/usr/sbin/usermod', '-c', v[:name], v[:login]]] }
    },
    # Brings an account the app created to the standard: no login shell and no extra
    # groups (older versions gave /bin/sh, and admins the sudo group).
    'users.normalize' => {
      params: %w[login],
      validate: ->(a) { { login: app_login(a['login']) } },
      plan: ->(v) { normal_account?(v[:login]) ? [] : [['/usr/sbin/usermod', '-s', NOLOGIN, '-G', '', v[:login]]] }
    },
    # Removes the Samba user (if any), so they can't connect again, then ends what still runs as
    # them (their SMB sessions: userdel refuses an account in use), then the Linux account, with
    # the home folder an older version made for it if it has one; but only an account the app
    # created: one that existed before is left alone.
    'users.delete' => {
      params: %w[login],
      validate: ->(a) { deletable_login(a['login']) },
      plan: lambda { |v|
        steps = [['/usr/bin/pdbedit', '-d0', '-x', '-u', v[:login], { allow_failure: true }]]
        if v[:linux_account]
          steps << [:end_user_processes, v[:login]]
          steps << ['/usr/sbin/userdel', *(v[:home] ? ['-r'] : []), v[:login]]
        end
        steps
      }
    },
    # Installed only if testparm loads it and it passes the checks in samba_problems.
    'samba.write_config' => {
      params: %w[content],
      validate: ->(a) { { content: smb_conf(a['content']) } },
      plan: ->(v) { [[:install, SMB_CONF, v[:content], :smb_conf], [:refresh_greyhole_pool], [:stop_greyhole_stats]] }
    },
    'samba.write_lmhosts' => {
      params: %w[content],
      validate: ->(a) { { content: lmhosts(a['content']) } },
      plan: ->(v) { [[:install, LMHOSTS, v[:content], nil]] }
    },
    # Reloads running Samba services; a stopped one stays stopped.
    'samba.reload' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [['/usr/bin/systemctl', 'try-reload-or-restart', 'smbd.service', 'nmbd.service']] }
    },
    # A share folder: amahi:users, setgid so new files keep the users group, 2775.
    'shares.create_dir' => {
      params: %w[path],
      validate: ->(a) { { path: share_path(a['path']) } },
      plan: ->(v) { [[:mkdir_p, v[:path]], [:own_dir, v[:path], APP_USER, USERS_GROUP, '2775']] }
    },
    # Removes a share folder only if it is empty.
    'shares.remove_dir' => {
      params: %w[path],
      validate: ->(a) { { path: share_path(a['path']) } },
      plan: ->(v) { [[:rmdir, v[:path]]] }
    },
    # Guest write access to the share folder itself (o+w / o-w), not the files in it.
    'shares.set_guest_write' => {
      params: %w[path writable],
      validate: ->(a) { { path: share_path(a['path']), writable: boolean(a, 'writable') } },
      plan: ->(v) { [[:guest_write, v[:path], v[:writable]]] }
    },
    # How many days the Trash keeps deleted files (0: until it's emptied), for trash.expire.
    'trash.set_days' => {
      params: %w[days],
      validate: ->(a) { { days: integer(a, 'days', 0..3650) } },
      plan: ->(v) { [[:install, TRASH_DAYS, "#{v[:days]}\n", nil, '0644']] }
    },
    # Deletes files that have been in the Trash longer than it keeps them: Greyhole's on each
    # pool drive, and each other share's recycle bin. Run daily by amahi-kai-trash.timer.
    'trash.expire' => {
      params: [],
      validate: ->(_a) { {} },
      plan: ->(_v) { [[:expire_trash]] }
    },
  )

  class << self
    def new_login(value)
      value = login(value)
      raise Refused, "#{value} already exists on this system" if passwd(value)
      value
    end

    # Deleting a web user whose Linux account is gone still removes its Samba user.
    def deletable_login(value)
      value = login(value)
      pw = passwd(value)
      raise Refused, "#{value} is not an account Amahi created" if pw && !app_account?(pw)
      { login: value, linux_account: !pw.nil?, home: !pw.nil? && old_home?(pw) }
    end

    # Ends the processes running as an app account being deleted (its SMB sessions): asked to
    # stop, then made to after USER_STOP_SECONDS.
    def do_end_user_processes(login)
      uid = passwd(login)&.uid or return nil
      return nil if uid < UID_MIN # never a system account's

      signal_user_processes(uid, 'TERM')
      deadline = monotonic_now + USER_STOP_SECONDS
      pause(0.2) while user_process_ids(uid).any? && monotonic_now < deadline
      signal_user_processes(uid, 'KILL')
      nil
    end

    # The processes with +uid+ as any of their ids (real, effective, saved, filesystem), as
    # userdel counts them: a Samba session may run as the user only as its effective id.
    def user_process_ids(uid)
      Dir.glob('/proc/[0-9]*/status').filter_map do |status|
        ids = File.read(status)[/^Uid:\s+(.+)$/, 1].to_s.split
        File.basename(File.dirname(status)).to_i if ids.include?(uid.to_s)
      rescue SystemCallError
        nil # gone meanwhile
      end
    end

    def signal_user_processes(uid, signal)
      user_process_ids(uid).each do |pid|
        Process.kill(signal, pid)
      rescue SystemCallError
        nil # gone meanwhile
      end
    end

    # A home folder an older version made with the account (useradd -m), under /home.
    def old_home?(pw)
      pw.dir.to_s.start_with?('/home/') && File.directory?(pw.dir) && !File.symlink?(pw.dir)
    end

    def normal_account?(login)
      passwd(login)&.shell == NOLOGIN && Etc.enum_for(:group).none? { |g| g.mem.include?(login) }
    end

    # The full name (GECOS) field: printable, no colon, at most 64 characters.
    def gecos(value)
      value = string(value, 'name', max: 64)
      raise Refused, 'name contains a control character or a colon' if value.match?(/[[:cntrl:]:]/)
      value
    end

    # { 'movies' => { name: 'Movies', path: '/var/lib/amahi-kai/files/movies', pooled: false } }:
    # the shares in smb.conf (names keep their case: Greyhole's folders on the drives use it).
    def samba_shares
      shares = {}
      current = nil
      File.read(SMB_CONF).gsub(/\\\r?\n/, ' ').each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#', ';')
        if (header = line[/\A\[([^\]]*)\]/, 1])
          name = header.strip
          current = SAMBA_SPECIAL_SECTIONS.include?(name.downcase) ? nil : (shares[name.downcase] = { name: name, path: nil, pooled: false })
          next
        end
        key, sep, value = line.partition('=')
        next if current.nil? || sep.empty?
        case key.downcase.delete(" \t")
        when 'path' then current[:path] = value.strip
        when 'vfsobjects' then current[:pooled] ||= value.downcase.split.include?('greyhole')
        end
      end
      shares.select { |_name, share| share[:path] }
    rescue SystemCallError
      {}
    end

    # A share folder: an absolute, normalized path strictly inside the share root or a
    # mounted data drive under /mnt. Checked against the real filesystem, so a symlink
    # can't stand in for a root.
    def share_path(value)
      value = string(value, 'path', max: 4096)
      raise Refused, "path #{value.inspect} must be absolute, without . or .. or //" unless normalized_path?(value)
      raise Refused, "path #{value} contains a line break" if value.match?(/[\r\n]/)
      share_root_of(value) or raise Refused, "path #{value} is not inside #{SHARE_ROOT}, a data drive under #{DRIVES_ROOT} or a ZFS pool's shares folder"
      value
    end

    # The root +path+ sits in (the share root, a data drive's mount point, or a ZFS pool's shares
    # dataset), or nil.
    def share_root_of(path)
      roots = [share_root]
      drive = path.delete_prefix("#{drives_root}/").split('/').first
      roots << "#{drives_root}/#{drive}" if path.start_with?("#{drives_root}/") && drive
      pool = path.delete_prefix("#{pool_root}/").split('/').first
      roots << pool_shares_root(pool) if path.start_with?("#{pool_root}/") && pool&.match?(POOL_NAME)
      roots.find { |root| path.start_with?("#{root}/") && real_root?(root) }
    end

    # A root must be a real directory at its own path (no symlink anywhere in it), and a
    # data drive must be mounted: an unmounted /mnt/<name> is just a folder on the OS disk. A
    # pool's shares folder must be its shares dataset, mounted there.
    def real_root?(root)
      return false unless File.realpath(root) == root && File.lstat(root).directory?
      return pool_shares_mounted?(root) if root.start_with?("#{pool_root}/")

      root == share_root || File.stat(root).dev != File.stat(drives_root).dev
    rescue SystemCallError
      false
    end

    def share_root
      SHARE_ROOT
    end

    def smb_conf(value)
      value = string(value, 'content', max: 1024 * 1024)
      problems = samba_problems(value)
      raise Refused, "smb.conf refused: #{problems.join('; ')}" if problems.any?
      value
    end

    def lmhosts(value)
      value = string(value, 'content', max: 64 * 1024)
      value.each_line do |line|
        line = line.strip
        next if line.empty?
        next if line.start_with?('#') && !line.match?(/\A#\s*(include|begin_alternate|end_alternate)/i)
        raise Refused, "lmhosts line #{line.inspect} is not an address and a name" unless line.match?(/\A[0-9A-Fa-f.:]+\s+[^\s#]+\z/)
      end
      value
    end

    # Problems with a Samba config (raw text, or testparm's canonical output): a parameter
    # that isn't listed, or a listed one with a value that points somewhere it shouldn't.
    def samba_problems(text)
      params = samba_params(text)
      problems = params.filter_map do |section, name, value|
        key = name.downcase.delete(" \t")
        if !samba_param_allowed?(section, key)
          "[#{section}] #{name} is not allowed"
        elsif (pinned = SAMBA_PINNED[key]) && !samba_value?(value, pinned)
          "[#{section}] #{name} must be #{pinned}"
        else
          samba_value_problem(section, key, value)
        end
      end
      return problems unless text.match?(/^\s*\[global\]/i) # a whole config, not one share's section
      written = params.filter_map { |section, name, _value| name.downcase.delete(" \t") if section == 'global' }
      SAMBA_REQUIRED.each { |line, keys| problems << "[global] #{line} is missing" if (keys & written).empty? }
      problems.concat(samba_reach_problems(params))
      problems
    end

    # Amahi-kai has Samba listen on every address (bind interfaces only = no) only with an allow
    # list deciding who connects, so a config saying no without one is refused; and the list
    # itself mustn't let everyone in.
    def samba_reach_problems(params)
      global = params.select { |section, _name, _value| section == 'global' }.to_h { |_s, name, value| [name.downcase.delete(" \t"), value] }
      allow = global['hostsallow'].to_s.split(/[\s,]+/)
      problems = []
      if allow.any? { |entry| %w[all 0.0.0.0/0 0.0.0.0/0.0.0.0 ::/0 *].include?(entry.downcase) }
        problems << '[global] hosts allow lets everyone in'
      end
      if allow.empty? && global.key?('bindinterfacesonly') && samba_value?(global['bindinterfacesonly'], 'no')
        problems << '[global] bind interfaces only = no needs hosts allow to say who connects'
      end
      problems
    end

    # Whether +value+ says +wanted+ the way Samba reads it: yes, true and 1 are one value, no,
    # false and 0 another, and case doesn't count.
    def samba_value?(value, wanted)
      v = value.strip.downcase
      v = 'yes' if %w[yes true 1].include?(v)
      v = 'no' if %w[no false 0].include?(v)
      v == wanted
    end

    # Share parameters are accepted in any section (in [global] Samba takes them as defaults);
    # global ones only in [global].
    def samba_param_allowed?(section, key)
      SAMBA_SHARE_PARAMS.include?(key) || SAMBA_MODULE_PARAMS.any? { |prefix| key.start_with?(prefix) } ||
        (section == 'global' && SAMBA_GLOBAL_PARAMS.include?(key))
    end

    def samba_value_problem(section, key, value)
      case key
      when 'path', 'directory'
        "[#{section}] path #{value} is outside the share folders" unless config_share_path?(value)
      when 'logfile'
        "[#{section}] log file must be in /var/log/samba" unless value.start_with?('/var/log/samba/') && !value.include?('..')
      when 'vfsobjects'
        unknown = value.split(/[\s,]+/) - SAMBA_VFS_MODULES
        "[#{section}] vfs objects #{unknown.join(', ')} not allowed" if unknown.any?
      when 'dfreecommand'
        "[#{section}] dfree command must be #{GREYHOLE_DFREE}" unless value == GREYHOLE_DFREE
      end
    end

    # Share paths in a config are text, so only their form is checked here; folders
    # themselves are created with shares.create_dir. A data drive's mount point itself is a share
    # too when the drive is shared as it is (Disks → Devices' Mount as Share, and the setup
    # wizard's FAT, exFAT and NTFS drives), its files where they were.
    def config_share_path?(value)
      normalized_path?(value) && !value.include?('%') &&
        (value.start_with?("#{share_root}/") || value.match?(%r{\A#{Regexp.escape(drives_root)}/[^/]+(?:/|\z)}) ||
         value.match?(%r{\A#{Regexp.escape(pool_root)}/[a-z][a-z0-9_-]{0,31}/shares/[^/]+}))
    end

    # [section, name, value] for each parameter. Samba joins a line ending in a
    # backslash with the next one.
    def samba_params(text)
      section = 'global'
      text.gsub(/\\\r?\n/, ' ').each_line.filter_map do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#', ';')
        if (header = line[/\A\[([^\]]*)\]/, 1])
          section = header.strip.downcase
          next
        end
        name, sep, value = line.partition('=')
        [section, name.strip, value.strip] unless sep.empty?
      end
    end

    def do_guest_write(path, writable)
      with_dir(path) do |dir|
        mode = dir.stat.mode & 0o7777
        wanted = writable ? mode | 0o002 : mode & ~0o002
        dir.chmod(wanted) unless wanted == mode
      end
      nil
    end

    def do_rmdir(path)
      stat = File.lstat(path)
      raise Failed, "#{path} is not a folder" unless stat.directory?
      Dir.rmdir(path)
      nil
    rescue Errno::ENOENT
      "#{path} doesn't exist"
    rescue Errno::ENOTEMPTY, Errno::EEXIST
      "#{path} isn't empty; left in place"
    end

    # testparm loads the file the way smbd would, and prints what it understood with
    # canonical parameter names; that is checked again (the raw text was checked first).
    def check_smb_conf(path)
      out, err, status = Open3.capture3(ENV_MIN, [TESTPARM, TESTPARM], '-s', path, unsetenv_others: true, chdir: '/')
      raise Refused, "testparm rejected smb.conf: #{last_lines(err.gsub(/^Load smb config files.*$/, ''), 2)}" unless status.success?
      problems = samba_problems(out)
      raise Refused, "smb.conf refused: #{problems.join('; ')}" if problems.any?
    rescue Errno::ENOENT
      raise Failed, "#{TESTPARM} is missing; is Samba installed?"
    end

    # One computer's SMB session: an smbd started by Samba's own smbd, never that one (whose
    # parent is init).
    def samba_session?(holder)
      holder[:comm] == 'smbd' && holder[:ppid] > 1
    end

    # The pooled shares' free space (amahi-dfree) follows greyhole.conf: written again with
    # Samba's config, so a System Update brings it to a NAS whose greyhole.conf came before it.
    def do_refresh_greyhole_pool
      return nil unless File.exist?(GREYHOLE_CONF)
      do_install(GREYHOLE_POOL_CONF, greyhole_pool_lines(File.read(GREYHOLE_CONF)), nil, '0644')
    end

    # The files in the Trash longer than it keeps them, deleted (find, which doesn't follow
    # links, by when each went in: a move into the trash sets its change time), and the
    # folders left empty. Nothing when it keeps them until it's emptied.
    def do_expire_trash
      days = File.exist?(TRASH_DAYS) ? File.read(TRASH_DAYS).strip : TRASH_DEFAULT_DAYS.to_s
      days = days.match?(/\A\d{1,4}\z/) ? days.to_i : TRASH_DEFAULT_DAYS
      return nil if days.zero?
      bins = greyhole_drives.map { |drive| "#{drive}/#{GREYHOLE_TRASH}" } +
             samba_shares.values.reject { |share| share[:pooled] }.map { |share| "#{share[:path]}/#{RECYCLE_BIN}" }
      bins.select { |bin| File.directory?(bin) && !File.symlink?(bin) }.each do |bin|
        run_command(['/usr/bin/find', bin, '-type', 'f', '-cmin', "+#{days * 1440}", '-delete'])
        run_command(['/usr/bin/find', bin, '-mindepth', '1', '-type', 'd', '-empty', '-delete'])
      end
      nil
    end

    # Greyhole's weekly job without the report of its usage stats to greyhole.net (the
    # package's own line and its comments), keeping the file check. Run with Samba's config,
    # so a System Update, Greyhole's install and every share change see to it. The job is a
    # dpkg conffile, so Greyhole's updates keep this version (they keep changed config files).
    def do_stop_greyhole_stats
      return nil unless File.file?(GREYHOLE_WEEKLY_CRON) && !File.symlink?(GREYHOLE_WEEKLY_CRON)
      content = File.read(GREYHOLE_WEEKLY_CRON)
      return nil unless content.include?('usage_stats')
      kept = content.lines.reject do |line|
        line.include?('usage_stats') || line.match?(/\A#.*(calls home|greyhole --stats|leave this here)/i)
      end
      kept = kept.join.rstrip
      do_install(GREYHOLE_WEEKLY_CRON, "#{kept}\n\n# Amahi-kai took out the weekly report of Greyhole's usage stats to greyhole.net.\n", nil, '0755')
    end
  end
end
