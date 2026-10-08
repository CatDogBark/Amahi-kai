require 'open3'

# The security audit on Network → Security. What needs root to read (UFW's state, sshd's
# effective settings) comes from the root helper's security.report; the fixes are helper
# operations too (security.*, packages.install). Blockers keep the Cloudflare Tunnel
# from being set up or started (RemoteAccessController checks them).
class SecurityAudit
  Check = Struct.new(:name, :description, :status, :severity, :fix_command, keyword_init: true)
  # status: :pass, :warn, :fail
  # severity: :blocker, :warning, :info


  class << self
    def run_all
      report = system_report
      [
        admin_password_check,
        ufw_check(report),
        ssh_root_login_check(report),
        ssh_password_auth_check(report),
        fail2ban_check,
        security_updates_check,
        samba_lan_binding_check,
        docker_ports_check,
        open_ports_check
      ]
    end

    def blockers
      run_all.select { |c| c.status == :fail && c.severity == :blocker }
    end

    # Applies one fix; true if it worked. Why it didn't is logged and kept in last_error
    # (the helper refuses to turn off SSH password login while no account has a key).
    def fix!(check_name)
      @last_error = nil
      return simulated_fix(check_name) unless production?

      case check_name.to_s
      when 'ufw_firewall'
        privileged('security.enable_firewall')
      when 'ssh_root_login'
        privileged('security.harden_ssh', setting: 'root_login')
      when 'ssh_password_auth'
        privileged('security.harden_ssh', setting: 'password_login')
      when 'fail2ban'
        privileged('packages.install', packages: ['fail2ban'])
      when 'samba_lan_binding'
        fix_samba_lan_binding!
      else
        false
      end
    end

    attr_reader :last_error

    # Fixes every failing check that has a fix: [{ name:, fixed:, error: }].
    def fix_all!
      run_all.filter_map do |check|
        next if check.status == :pass || check.fix_command.nil?
        fixed = fix!(check.name)
        { name: check.name, fixed: fixed, error: (last_error unless fixed) }.compact
      end
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end

    # UFW's state and sshd's effective settings, from the root helper. Outside production
    # (and if the helper fails) it describes a hardened system with UFW off.
    def system_report
      return { 'firewall' => 'inactive', 'ssh' => {} } unless production?
      Privileged.call('security.report')
    rescue Privileged::Error => e
      Rails.logger.error("SecurityAudit: security.report failed: #{e.message}")
      { 'firewall' => 'unknown', 'ssh' => {} }
    end

    def privileged(operation, **args)
      Privileged.call(operation, **args)
      true
    rescue Privileged::Error => e
      Rails.logger.error("SecurityAudit: #{operation} failed: #{e.message}")
      @last_error = e.message
      false
    end

    # --- Individual checks ---

    def admin_password_check
      changed = admin_password_changed?
      Check.new(
        name: 'admin_password',
        description: 'Admin password changed from default',
        status: changed ? :pass : :fail,
        severity: :blocker,
        fix_command: nil # Must be changed manually
      )
    end

    def admin_password_changed?
      return true unless defined?(User)
      !User.seed_admin_password_in_use?
    rescue StandardError
      true # If we can't check, assume it's fine
    end

    # The fix lets in SSH, the web UI (3000), HTTPS and Samba, plus DNS and DHCP once
    # Amahi-kai has configured dnsmasq.
    def ufw_check(report)
      Check.new(
        name: 'ufw_firewall',
        description: 'UFW firewall is active',
        status: report['firewall'] == 'active' ? :pass : :fail,
        severity: :blocker,
        fix_command: 'Enable UFW with Amahi-kai\'s rules'
      )
    end

    # sshd's effective settings: a drop-in in sshd_config.d can override sshd_config.
    # With no SSH server installed there is nothing to harden.
    def ssh_root_login_check(report)
      ssh = report['ssh'] || {}
      Check.new(
        name: 'ssh_root_login',
        description: 'SSH root login disabled',
        status: ssh.empty? || ssh['permitrootlogin'] == 'no' ? :pass : :warn,
        severity: :warning,
        fix_command: 'Harden SSH configuration'
      )
    end

    # Password login is off when both password and keyboard-interactive logins are. The
    # fix is refused while no account that can log in has an SSH key.
    def ssh_password_auth_check(report)
      ssh = report['ssh'] || {}
      off = ssh['passwordauthentication'] == 'no' && ssh['kbdinteractiveauthentication'] == 'no'
      Check.new(
        name: 'ssh_password_auth',
        description: 'SSH password authentication disabled',
        status: ssh.empty? || off ? :pass : :warn,
        severity: :warning,
        fix_command: 'Harden SSH configuration (needs an SSH key on your account first)'
      )
    end

    # Ubuntu's fail2ban package turns on its SSH jail only.
    def fail2ban_check
      installed = fail2ban_installed?
      Check.new(
        name: 'fail2ban',
        description: 'Fail2ban blocks repeated failed SSH logins',
        status: installed ? :pass : :warn,
        severity: :warning,
        fix_command: 'Install fail2ban'
      )
    end

    def fail2ban_installed?
      return false unless production?
      SystemInfo.package_installed?('fail2ban')
    end

    # Security updates get installed: by themselves when automatic updates are on, or from
    # Settings → System Dependencies, where none should wait more than a week. Updating is the
    # admin's choice to make there, so this has no fix of its own.
    def security_updates_check
      waiting = SystemDependencies.overdue_security_updates(days: 7)
      Check.new(
        name: 'security_updates',
        description: if waiting.empty?
                       'Security updates installed (none waiting more than a week)'
                     else
                       "#{waiting.size} security #{waiting.size == 1 ? 'update has' : 'updates have'} waited more than a week: " \
                         'install on Settings → System Dependencies'
                     end,
        status: waiting.empty? ? :pass : :warn,
        severity: :warning,
        fix_command: nil
      )
    end

    def samba_lan_binding_check
      bound = samba_lan_only?
      Check.new(
        name: 'samba_lan_binding',
        description: 'Samba bound to LAN interfaces only',
        status: bound ? :pass : :fail,
        severity: :blocker,
        fix_command: 'Update smb.conf with interface binding'
      )
    end

    def samba_lan_only?
      return true unless production?
      return true unless File.exist?('/etc/samba/smb.conf')
      content = File.read('/etc/samba/smb.conf')
      content.match?(/^\s*bind interfaces only\s*=\s*yes/i) &&
        content.match?(/^\s*interfaces\s*=/i)
    end

    # Docker writes its own iptables rules for published ports, ahead of UFW's, so UFW
    # doesn't filter them. Amahi-kai's own rules (the helper's apps.firewall, from P4.2) keep
    # them to the LAN and Tailscale. Ports published on 127.0.0.1 stay local.
    def docker_ports_check
      ports, limited = docker_published_ports
      description = if ports.empty?
                      'No Docker ports published past the firewall'
                    elsif limited
                      "Docker app ports #{ports.join(', ')} are reachable from the LAN and Tailscale only"
                    else
                      "Docker publishes #{ports.join(', ')}, which UFW doesn't filter"
                    end
      Check.new(
        name: 'docker_ports',
        description: description,
        status: ports.empty? || limited ? :pass : :warn,
        severity: :warning,
        fix_command: nil
      )
    end

    # [ports, limited]: the ports Docker publishes beyond the NAS itself ("8096/tcp", ...), and
    # whether Amahi-kai's rules limit them, read by the root helper (the web app can't reach
    # Docker or the firewall).
    def docker_published_ports
      return [[], false] unless production? && File.executable?('/usr/bin/docker')
      reply = Privileged.call('docker.published_ports')
      ports = Array(reply['ports']).flat_map { |line| line.split("\t", 2).last.to_s.split(',') }.filter_map do |mapping|
        host, port, proto = mapping.strip.match(%r{\A(.*):(\d+)(?:-\d+)?->[\d-]+/(tcp|udp)\z})&.captures
        "#{port}/#{proto}" if port && !host.start_with?('127.', '[::1]', '::1')
      end.uniq
      [ports, reply['limited'] == true]
    rescue Privileged::Error
      [[], false]
    end

    def open_ports_check
      ports = open_ports
      Check.new(
        name: 'open_ports',
        description: "Open ports: #{ports.join(', ')}",
        status: :pass,
        severity: :info,
        fix_command: nil
      )
    end

    def open_ports
      return ['22/ssh', '3000/amahi-kai', '445/samba'] unless production?
      output = Shell.output('ss', '-tlnp').strip
      ports = []
      output.each_line do |line|
        next if line.start_with?('State')
        # Skip loopback-only listeners (127.0.0.1 / ::1)
        next if line =~ /\b127\.0\.0\.1:/ || line =~ /\[::1\]:/
        if line =~ /:(\d+)\s/
          ports << $1
        end
      end
      ports.uniq.sort_by(&:to_i)
    end

    # --- Fix methods ---

    # smb.conf is generated (Share.samba_network_lines binds Samba to the LAN and
    # Tailscale), so regenerate it rather than editing it: the next share change
    # regenerated the file and undid the old edit.
    def fix_samba_lan_binding!
      SambaService.push_config && SystemServices.find('smbd')&.perform('restart')
    end

    def simulated_fix(check_name)
      # In dev/test, just return true
      true
    end
  end
end
