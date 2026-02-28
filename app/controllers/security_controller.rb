# Amahi Home Server — Security Audit & Fixes
# Split from NetworkController for maintainability.

class SecurityController < ApplicationController
  include SseStreaming

  before_action :admin_required

  def index
    @page_title = t('network')
    @checks = SecurityAudit.run_all
    @has_blockers = SecurityAudit.has_blockers?
  end

  def audit_stream
    stream_sse do |sse|
      sse.send("Running security audit...")
      sse.send("")

      checks = SecurityAudit.run_all
      passed = 0
      warnings = 0
      blockers = 0
      has_fixable = false

      checks.each do |check|
        sleep 0.4 unless Rails.env.production?
        sleep 0.15 if Rails.env.production?

        sse.send("Checking #{check.description.downcase}...")

        case check.status
        when :pass
          passed += 1
          sse.send("  ✓ #{check.description}")
        when :warn
          warnings += 1
          sse.send("  ⚠ #{check.description} (recommended to fix)")
          has_fixable = true if check.fix_command && check.name != 'admin_password'
        when :fail
          if check.severity == :blocker
            blockers += 1
            sse.send("  ✗ #{check.description} (BLOCKER)")
          else
            warnings += 1
            sse.send("  ✗ #{check.description}")
          end
          has_fixable = true if check.fix_command && check.name != 'admin_password' && check.name != 'open_ports'
        end

        sse.send("")
      end

      sse.send("─── Audit Complete ───")
      sse.send("✓ #{passed} passed")
      sse.send("⚠ #{warnings} warnings") if warnings > 0
      sse.send("✗ #{blockers} blocker#{'s' if blockers != 1}") if blockers > 0

      if blockers > 0
        sse.send("")
        sse.send("✗ Blockers must be fixed before enabling remote access.")
      end

      sse.send(has_fixable.to_s, event: "has_fixable")
      sse.send("", event: "done")
    end
  end

  def fix
    check_name = params[:check_name].to_s
    result = SecurityAudit.fix!(check_name)
    render json: { status: result ? :ok : :error, check: check_name }
  end

  def fix_stream
    stream_sse do |sse|
      sse.send("Starting security fixes...")

      unless Rails.env.production?
        lines = [
          "Enabling UFW firewall...",
          "  Default incoming policy changed to 'deny'",
          "  Rule added: allow 22/tcp",
          "  Rule added: allow 3000/tcp",
          "  Firewall is active and enabled on system startup",
          "✓ UFW firewall enabled",
          "",
          "Hardening SSH configuration...",
          "  Setting PermitRootLogin no",
          "  Setting PasswordAuthentication no",
          "  Restarting sshd...",
          "✓ SSH hardened",
          "",
          "Installing fail2ban...",
          "  Reading package lists...",
          "  Setting up fail2ban...",
          "✓ Fail2ban installed",
          "",
          "Installing unattended-upgrades...",
          "  Setting up unattended-upgrades...",
          "✓ Automatic security updates enabled",
          "",
          "Configuring Samba LAN binding...",
          "  Adding interface binding to smb.conf",
          "  Restarting smbd...",
          "✓ Samba bound to LAN only",
          "",
          "✓ All security fixes applied!"
        ]
        lines.each do |line|
          sleep 0.2
          sse.send(line)
        end
        sse.send("", event: "done")
        next
      end

      begin
        results = SecurityAudit.fix_all!
        results.each do |r|
          if r[:fixed]
            sse.send("✓ Fixed: #{r[:name]}")
          else
            sse.send("✗ Failed to fix: #{r[:name]}")
          end
        end
        sse.send("✓ Security fix-all complete!")
      rescue Shell::CommandError, Errno::ENOENT, Errno::EACCES, IOError => e
        sse.send("✗ Error: #{e.message}")
      end
      sse.send("", event: "done")
    end
  end
end
