require 'shell'

class Greyhole
  class GreyholeError < StandardError; end

  CONFIG_PATH = '/etc/greyhole.conf'
  GREYHOLE_REPO_KEY = 'https://www.greyhole.net/releases/deb/greyhole-debsig.asc'
  GREYHOLE_REPO_URL = 'https://www.greyhole.net/releases/deb'
  KEYRING_PATH = '/usr/share/keyrings/greyhole-archive-keyring.asc'
  SOURCES_PATH = '/etc/apt/sources.list.d/greyhole.list'

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
      Shell.run('systemctl is-active --quiet greyhole.service')
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

    def install!(&progress)
      progress ||= proc { |_msg| } # no-op if no block given
      return true unless production?

      # Add Greyhole apt repository
      unless File.exist?(KEYRING_PATH)
        progress.call("Downloading Greyhole signing key...")
        tmpkey = '/tmp/greyhole-debsig.asc'
        unless system("curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 -o #{tmpkey} #{GREYHOLE_REPO_KEY}")
          raise GreyholeError, 'Failed to download Greyhole signing key'
        end
        result = Shell.run("cp #{tmpkey} #{KEYRING_PATH}")
        raise GreyholeError, 'Failed to install Greyhole signing key' unless result
        FileUtils.rm_f(tmpkey)
        progress.call("✓ Signing key installed")
      end

      unless File.exist?(SOURCES_PATH)
        progress.call("Adding Greyhole apt repository...")
        tmplist = '/tmp/greyhole.list'
        File.write(tmplist, "deb [signed-by=#{KEYRING_PATH}] #{GREYHOLE_REPO_URL} stable main\n")
        result = Shell.run("cp #{tmplist} #{SOURCES_PATH}")
        raise GreyholeError, 'Failed to add Greyhole apt source' unless result
        FileUtils.rm_f(tmplist)
      end

      progress.call("Updating package lists...")
      Shell.run('apt-get update')

      # Pre-configure: DB and minimal config must exist BEFORE dpkg postinst runs
      progress.call("Pre-configuring database...")
      Shell.run('mysql -u root -e "CREATE DATABASE IF NOT EXISTS greyhole"')
      Shell.run("mysql -u root -e \"GRANT ALL PRIVILEGES ON greyhole.* TO 'amahi'@'localhost'; FLUSH PRIVILEGES;\"")

      progress.call("Installing PHP dependencies...")
      Shell.run('apt-get install -y php8.3-mbstring php8.3-mysql 2>/dev/null')
      Shell.run('phpenmod mbstring 2>/dev/null')

      unless File.exist?(CONFIG_PATH)
        progress.call("Writing minimal Greyhole config...")
        Shell.run("sh -c \"echo 'db_host = localhost\ndb_user = amahi\ndb_name = greyhole' > #{CONFIG_PATH}\"")
      end

      progress.call("Installing Greyhole package (this may take a minute)...")
      result = Shell.run('DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold greyhole')
      raise GreyholeError, 'Failed to install greyhole package' unless result
      progress.call("✓ Greyhole package installed")

      # Load schema after install (schema file comes with the package)
      if File.exist?('/usr/share/greyhole/schema-mysql.sql')
        progress.call("Loading database schema...")
        Shell.run('mysql -u root greyhole < /usr/share/greyhole/schema-mysql.sql 2>/dev/null')
      end

      # Generate full config and enable service
      configure! if DiskPoolPartition.any?

      # Re-inject Samba globals — Greyhole's postinst may overwrite smb.conf
      progress.call("Configuring Samba integration...")
      reinject_samba_globals!

      progress.call("Enabling and starting services...")
      Shell.run('systemctl enable greyhole.service')
      Shell.run('systemctl restart smbd.service')
      Shell.run('systemctl restart nmbd.service')
      Shell.run('systemctl start greyhole.service')

      true
    end

    def start!
      return true unless production?
      Shell.run('systemctl start greyhole.service')
    end

    def stop!
      return true unless production?
      Shell.run('systemctl stop greyhole.service')
    end

    def restart!
      return true unless production?
      Shell.run('systemctl restart greyhole.service')
    end

    def pool_drives
      return dummy_pool_drives unless production?
      DiskPoolPartition.all.map do |part|
        usage = part.usage
        {
          path: part.path,
          minimum_free: part.minimum_free,
          total: usage[:total],
          free: usage[:free],
          used: usage[:used]
        }
      end
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

    def fsck(options = {})
      return true unless production?
      cmd = 'greyhole --fsck'
      cmd += " --dir=#{Shellwords.escape(options[:dir])}" if options[:dir]
      Shell.run(cmd)
    end

    def configure!
      return true unless production?
      config = generate_config
      tmp = File.join(AMAHI_TMP_DIR, 'greyhole.conf')
      FileUtils.mkdir_p(File.dirname(tmp))
      File.write(tmp, config)
      Shell.run("/usr/bin/cp #{Shellwords.escape(tmp)} #{CONFIG_PATH}")
      # Only restart if Greyhole is currently running; don't crash if it fails
      restart! if running?
    rescue StandardError => e
      Rails.logger.error("Greyhole configure error: #{e.message}")
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

    def reinject_samba_globals!
      return unless production?
      smb_conf = '/etc/samba/smb.conf'
      return unless File.exist?(smb_conf)

      required_settings = [
        'wide links = yes',
        'follow symlinks = yes',
        'allow insecure wide links = yes',
        'unix extensions = no'
      ]

      content = File.read(smb_conf)
      required_settings.each do |setting|
        key = setting.split('=').first.strip
        unless content.match?(/^\s*#{Regexp.escape(key)}/i)
          # Insert after [global]
          Shell.run("sed -i '/^\\[global\\]/a\\\\\\t#{setting}' #{smb_conf}")
        end
      end
    end

    def production?
      defined?(Rails) && Rails.env.production?
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
          used: 250_000_000_000
        }
      end
    end

    def parse_queue_status(output)
      pending = output.scan(/(\d+) pending/).flatten.first.to_i rescue 0
      { pending: pending, last_action: nil }
    end
  end
end
