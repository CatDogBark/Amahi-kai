# Handles Samba configuration generation and deployment.
#
# Extracted from Share model class methods to:
# - Separate config generation (pure logic, testable) from deployment (side effects)
# - Make the push_shares flow explicit and mockable

require 'shell'
require 'temp_cache'
require 'platform'
require 'open3'

class SambaService
  # Generate and deploy Samba configuration, then reload services.
  # Returns whether a new smb.conf was installed.
  def self.push_config
    domain = Setting.value_by_name("domain")
    debug = Setting.shares.value_by_name('debug') == '1'

    written = write_smb_conf(Share.samba_conf(domain), debug: debug)
    write_lmhosts(Share.samba_lmhosts(domain), debug: debug)

    # smbd re-reads smb.conf on reload; it used to pick share changes up only on its own timer.
    Platform.reload(:smb) if written
    Platform.reload(:nmb)
    written
  end

  # Write smb.conf atomically via temp file + copy
  def self.write_smb_conf(content, debug: false)
    tmpfile = TempCache.unique_filename("smbconf")
    File.open(tmpfile, "w") { |f| f.write(content) }

    # Never install a config Samba can't load: that would take every share offline.
    unless config_valid?(tmpfile)
      Rails.logger.error("SambaService: generated smb.conf failed testparm; keeping the current one")
      FileUtils.rm_f(tmpfile)
      return false
    end

    cmds = []
    cmds << "cp /etc/samba/smb.conf \"/tmp/smb.conf.#{Time.now}\"" if debug
    cmds << "cp #{tmpfile} /etc/samba/smb.conf"
    cmds << "rm -f #{tmpfile}"
    Shell.run(*cmds)
  end

  # testparm loads the file the way smbd would; skipped where Samba isn't installed.
  def self.config_valid?(path)
    return true unless File.executable?('/usr/bin/testparm')
    _out, _err, status = Open3.capture3('/usr/bin/testparm', '-s', path)
    status.success?
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
