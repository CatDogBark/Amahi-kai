# Handles Samba configuration generation and deployment.
#
# Extracted from Share model class methods to:
# - Separate config generation (pure logic, testable) from deployment (side effects)
# - Make the push_shares flow explicit and mockable
#
# Files in /etc/samba are written by the root helper (samba.* operations), which
# checks smb.conf with testparm and refuses parameters that would run commands as root.

class SambaService
  # Generate and deploy Samba configuration, then reload services.
  # Returns whether a new smb.conf was installed.
  def self.push_config
    domain = Setting.get("domain")

    written = write_smb_conf(Share.samba_conf(domain))
    lmhosts = write_lmhosts(Share.samba_lmhosts(domain))

    # smbd re-reads smb.conf on reload; it used to pick share changes up only on its own timer.
    reload if written || lmhosts
    written
  end

  # Installs smb.conf if Samba can load it; otherwise the current one stays.
  def self.write_smb_conf(content)
    Privileged.call('samba.write_config', content: content)
    true
  rescue Privileged::Error => e
    Rails.logger.error("SambaService: smb.conf not installed; keeping the current one: #{e.message}")
    false
  end

  def self.write_lmhosts(content)
    Privileged.call('samba.write_lmhosts', content: content)
    true
  rescue Privileged::Error => e
    Rails.logger.error("SambaService: lmhosts not installed: #{e.message}")
    false
  end

  # Reloads smbd and nmbd if they're running.
  def self.reload
    Privileged.call('samba.reload')
    true
  rescue Privileged::Error => e
    Rails.logger.error("SambaService: Samba reload failed: #{e.message}")
    false
  end
end
