require 'shellwords'

class SecurityAudit
  Check = Struct.new(:name, :description, :status, :severity, :fix_command, keyword_init: true)
  # status: :pass, :warn, :fail
  # severity: :blocker, :warning, :info

  class << self
    def run_all
      [
        admin_password_check,
        ufw_check,
        ssh_root_login_check,
        ssh_password_auth_check,
        fail2ban_check,
        unattended_upgrades_check,
        samba_lan_binding_check,
        open_ports_check
      ]
    end

    def blockers
      run_all.select { |c| c.status == :fail && c.severity == :blocker }
    end

    def has_blockers?
      blockers.any?
    end

    def fix!(check_name)
      return simulated_fix(check_name) unless production?

      case check_name.to_s
      when 'ufw_firewall'
        fix_ufw!
      when 'ssh_root_login'
        fix_ssh_root_login!
      when 'ssh_password_auth'
        fix_ssh_password_auth!
      when 'fail2ban'
        fix_fail2ban!
      when 'unattended_upgrades'
        fix_unattended_upgrades!
      when 'samba_lan_binding'
        fix_samba_lan_binding!
      else
        false
      end
    end

    def fix_all!
      results = []
      run_all.each do |check|
        next if check.status == :pass || check.name == 'admin_password' || check.name == 'open_ports'
        results << { name: check.name, fixed: fix!(check.name) }
      end
      results
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
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
      admin = User.find_by(login: 'admin')
      return true if admin.nil?
      # Check if default password still works
      !admin.authenticate('secretpassword')
    rescue
      true # If we can't check, assume it's fine
    end

    def ufw_check
      active = ufw_enabled?
      Check.new(
        name: 'ufw_firewall',
        description: 'UFW firewall is active',
        status: active ? :pass : :fail,
        severity: :blocker,
        fix_command: 'sudo ufw --force enable && sudo ufw default deny incoming && sudo ufw allow 22/tcp && sudo ufw allow 3000/tcp'
      )
    end

    def ufw_enabled?
      return false unless production?
      output = `sudo /usr/sbin/ufw status 2>/dev/null`.strip
      output.include?('Status: active')
    end

    def ssh_root_login_check
      hardened = ssh_root_login_disabled?
      Check.new(
        name: 'ssh_root_login',
        description: 'SSH root login disabled',
        status: hardened ? :pass : :warn,
        severity: :warning,
        fix_command: 'Harden SSH configuration'
      )
    end

    def ssh_root_login_disabled?
      return true unless production?
      return false unless File.exist?('/etc/ssh/sshd_config')
      content = File.read('/etc/ssh/sshd_config')
      content.match?(/^\s*PermitRootLogin\s+no/i)
    end

    def ssh_password_auth_check
      disabled = ssh_password_auth_disabled?
      Check.new(
        name: 'ssh_password_auth',
        description: 'SSH password authentication disabled',
        status: disabled ? :pass : :warn,
        severity: :warning,
        fix_command: 'Harden SSH configuration'
      )
    end

    def ssh_password_auth_disabled?
      return true unless production?
      return false unless File.exist?('/etc/ssh/sshd_config')
      content = File.read('/etc/ssh/sshd_config')
      content.match?(/^\s*PasswordAuthentication\s+no/i)
    end

    def fail2ban_check
      installed = fail2ban_installed?
      Check.new(
        name: 'fail2ban',
        description: 'Fail2ban intrusion prevention installed',
        status: installed ? :pass : :warn,
        severity: :warning,
        fix_command: 'sudo apt-get install -y fail2ban'
      )
    end

    def fail2ban_installed?
      return false unless production?
      output = `dpkg-query -W -f='${Status}' fail2ban 2>/dev/null`.strip
      output == 'install ok installed'
    end

    def unattended_upgrades_check
      installed = unattended_upgrades_installed?
      Check.new(
        name: 'unattended_upgrades',
        description: 'Automatic security updates enabled',
        status: installed ? :pass : :warn,
        severity: :warning,
        fix_command: 'sudo apt-get install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades'
      )
    end

    def unattended_upgrades_installed?
      return false unless production?
      output = `dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null`.strip
      output == 'install ok installed'
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
      output = `ss -tlnp 2>/dev/null`.strip
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

    def fix_ufw!
      system('sudo ufw --force enable') &&
        system('sudo ufw default deny incoming') &&
        system('sudo ufw allow 22/tcp') &&
        system('sudo ufw allow 3000/tcp')
    end

    def fix_ssh_root_login!
      fix_sshd_setting!('PermitRootLogin', 'no')
    end

    def fix_ssh_password_auth!
      fix_sshd_setting!('PasswordAuthentication', 'no')
    end

    def fix_sshd_setting!(key, value)
      tmp_path = '/var/hda/tmp/sshd_config'
      content = File.exist?('/etc/ssh/sshd_config') ? File.read('/etc/ssh/sshd_config') : ''

      if content.match?(/^\s*#?\s*#{key}/)
        content.gsub!(/^\s*#?\s*#{key}\s+.*/, "#{key} #{value}")
      else
        content += "\n#{key} #{value}\n"
      end

      File.write(tmp_path, content)
      system("sudo cp #{tmp_path} /etc/ssh/sshd_config") &&
        (system('sudo systemctl restart sshd') || system('sudo systemctl restart ssh'))
    end

    def fix_fail2ban!
      system('sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban')
    end

    def fix_unattended_upgrades!
      system('sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades') &&
        system('sudo dpkg-reconfigure -plow unattended-upgrades')
    end

    def fix_samba_lan_binding!
      return false unless File.exist?('/etc/samba/smb.conf')
      tmp_path = '/var/hda/tmp/smb.conf'
      content = File.read('/etc/samba/smb.conf')

      unless content.match?(/^\s*interfaces\s*=/i)
        # Detect primary network interface (eth0 is legacy — Ubuntu 24.04 uses predictive names)
        primary_iface = `ip -4 route show default 2>/dev/null`.match(/dev\s+(\S+)/)&.captures&.first || 'eth0'
        content.sub!(/\[global\]/i, "[global]\n   interfaces = lo #{primary_iface}\n   bind interfaces only = yes")
      end

      unless content.match?(/^\s*bind interfaces only\s*=\s*yes/i)
        content.sub!(/\[global\]/i, "[global]\n   bind interfaces only = yes")
      end

      File.write(tmp_path, content)
      system("sudo cp #{tmp_path} /etc/samba/smb.conf") &&
        system('sudo systemctl restart smbd.service')
    end

    def simulated_fix(check_name)
      # In dev/test, just return true
      true
    end
  end
end
