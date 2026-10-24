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
  # Returns whether a new smb.conf was installed. With raise_refusal, a config the root helper
  # refuses raises Privileged::Error (its message says which line) instead of being logged.
  def self.push_config(raise_refusal: false)
    domain = Setting.get("domain")

    written = write_smb_conf(Share.samba_conf(domain), raise_refusal: raise_refusal)
    lmhosts = write_lmhosts(Share.samba_lmhosts(domain))

    # smbd re-reads smb.conf on reload; it used to pick share changes up only on its own timer.
    reload if written || lmhosts
    written
  end

  # Installs smb.conf if Samba can load it; otherwise the current one stays.
  def self.write_smb_conf(content, raise_refusal: false)
    Privileged.call('samba.write_config', content: content)
    true
  rescue Privileged::Error => e
    raise if raise_refusal
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

  # Samba's interfaces follow the LAN interface (Share.primary_interface), which router mode
  # changes; smbd opens its sockets only when it starts, so when the interfaces line changes, it
  # restarts. Called after router mode goes on or off.
  def self.follow_interfaces!
    before = interfaces_line
    push_config
    restart_for_new_addresses if interfaces_line != before
  end

  def self.interfaces_line(path = '/etc/samba/smb.conf')
    File.read(path)[/^\s*interfaces\s*=.*$/]&.strip
  rescue SystemCallError
    nil
  end

  # smbd opens its listening sockets when it starts; a reload doesn't open new ones. That matters
  # while Samba is bound to its interfaces (no allow list yet: Share.samba_network_lines); with
  # the list it listens on every address. So when the interfaces line changes, smbd restarts,
  # unless it isn't running (stopped on purpose). Connections open then reconnect by themselves.
  def self.restart_for_new_addresses
    return false unless Shell.success?('systemctl', 'is-active', '--quiet', 'smbd')

    Privileged.call('services.restart', service: 'smbd')
    true
  rescue Privileged::Error => e
    Rails.logger.error("SambaService: Samba restart failed: #{e.message}")
    false
  end
end
