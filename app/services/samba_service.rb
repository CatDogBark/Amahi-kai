# Handles Samba configuration generation and deployment.
#
# Extracted from Share model class methods to:
# - Separate config generation (pure logic, testable) from deployment (side effects)
# - Make the push_shares flow explicit and mockable
#
# Config generation methods remain on Share for now (they need share data),
# but this service orchestrates the write-and-reload cycle.

require 'command'
require 'temp_cache'
require 'platform'

class SambaService
  # Generate and deploy Samba configuration, then reload services.
  # This is the main entry point called after share changes.
  def self.push_config
    domain = Setting.value_by_name("domain")
    debug = Setting.shares.value_by_name('debug') == '1'

    write_smb_conf(Share.samba_conf(domain), debug: debug)
    write_lmhosts(Share.samba_lmhosts(domain), debug: debug)

    Platform.reload(:nmb)
  end

  # Write smb.conf atomically via temp file + copy
  def self.write_smb_conf(content, debug: false)
    tmpfile = TempCache.unique_filename("smbconf")
    File.open(tmpfile, "w") { |f| f.write(content) }

    c = Command.new
    if debug
      time = Time.now
      c.submit("cp /etc/samba/smb.conf \"/tmp/smb.conf.#{time}\"")
    end
    c.submit("cp #{tmpfile} /etc/samba/smb.conf")
    c.submit("rm -f #{tmpfile}")
    c.execute
  end

  # Write lmhosts atomically via temp file + copy
  def self.write_lmhosts(content, debug: false)
    tmpfile = TempCache.unique_filename("lmhosts")
    File.open(tmpfile, "w") { |f| f.write(content) }

    c = Command.new
    if debug
      time = Time.now
      c.submit("cp /etc/samba/lmhosts \"/tmp/lmhosts.#{time}\"")
    end
    c.submit("cp #{tmpfile} /etc/samba/lmhosts")
    c.submit("rm -f #{tmpfile}")
    c.execute
  end
end
