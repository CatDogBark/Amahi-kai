# Handles Samba configuration generation and deployment.
#
# Extracted from Share model class methods to:
# - Separate config generation (pure logic, testable) from deployment (side effects)
# - Make the push_shares flow explicit and mockable

require 'shell'
require 'temp_cache'
require 'platform'

class SambaService
  # Generate and deploy Samba configuration, then reload services.
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

    cmds = []
    cmds << "cp /etc/samba/smb.conf \"/tmp/smb.conf.#{Time.now}\"" if debug
    cmds << "cp #{tmpfile} /etc/samba/smb.conf"
    cmds << "rm -f #{tmpfile}"
    Shell.run(*cmds)
  end

  # Write lmhosts atomically via temp file + copy
  def self.write_lmhosts(content, debug: false)
    tmpfile = TempCache.unique_filename("lmhosts")
    File.open(tmpfile, "w") { |f| f.write(content) }

    cmds = []
    cmds << "cp /etc/samba/lmhosts \"/tmp/lmhosts.#{Time.now}\"" if debug
    cmds << "cp #{tmpfile} /etc/samba/lmhosts"
    cmds << "rm -f #{tmpfile}"
    Shell.run(*cmds)
  end
end
