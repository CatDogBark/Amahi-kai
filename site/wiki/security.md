---
layout: default
title: "Security"
---

# Security

Amahi-kai includes a built-in security audit that checks your server's configuration and can automatically fix most issues. The audit is especially important before enabling [Remote Access](remote-access).

---

## Security Audit

Navigate to **Network > Security** (requires Advanced mode) to run the audit.

The audit checks 8 items, each classified as:

| Status | Meaning |
|--------|---------|
| **Pass** | Configuration is secure |
| **Warning** | Recommended to fix, but not blocking |
| **Blocker** | Must be fixed before enabling remote access |

### Checks Performed

| Check | Severity | What It Verifies |
|-------|----------|------------------|
| Admin password changed | Blocker | Default password (`secretpassword`) has been changed |
| UFW firewall active | Blocker | UFW is enabled with deny-by-default policy |
| SSH root login disabled | Warning | `PermitRootLogin no` in sshd_config |
| SSH password auth disabled | Warning | `PasswordAuthentication no` in sshd_config |
| Fail2ban installed | Warning | `fail2ban` package is installed |
| Unattended upgrades | Warning | `unattended-upgrades` package is installed |
| Samba LAN binding | Blocker | Samba is bound to LAN interfaces only |
| Open ports | Info | Lists all externally-listening ports |

---

## Auto-Fix

Click **Fix All** in the security audit page to automatically resolve all fixable issues. The fix-all operation streams progress in real-time and performs:

### 1. Enable UFW Firewall

```bash
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 3000/tcp    # Amahi-kai web UI
```

### 2. Harden SSH

Modifies `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
```

Then restarts sshd.

> **Important**: Before disabling SSH password authentication, make sure you have SSH key access configured. Otherwise you could lock yourself out.

### 3. Install Fail2ban

```bash
sudo apt-get install -y fail2ban
```

Fail2ban monitors log files and bans IPs that show malicious activity (brute-force SSH attempts, etc.).

### 4. Enable Unattended Upgrades

```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

This configures Ubuntu to automatically install security updates.

### 5. Bind Samba to LAN

Adds to `smb.conf` under `[global]`:

```ini
interfaces = lo <your-interface>
bind interfaces only = yes
```

Then restarts Samba. This prevents Samba from listening on external/tunnel interfaces.

### What Can't Be Auto-Fixed

- **Admin password** — Must be changed manually through the web UI or setup wizard
- **Open ports** — Informational only; manually close any unexpected ports

---

## Individual Fixes

You can also fix individual items by clicking their **Fix** button. Each fix runs the same commands as the auto-fix, but only for that specific check.

---

## Sudoers Allowlist

Amahi-kai follows the principle of least privilege. The `amahi` user cannot run arbitrary commands as root. Instead, a carefully scoped sudoers file at `/etc/sudoers.d/amahi-kai` allows only specific commands:

| Category | Allowed Commands |
|----------|------------------|
| User management | `useradd`, `usermod`, `userdel` |
| Samba | `pdbedit` |
| File operations | `chmod`, `chown`, `mkdir` scoped to `/var/lib/amahi-kai/*` |
| SSH | `chmod`/`chown` scoped to `/home/*/.ssh` |
| Config staging | `cp` from staging dirs to `/etc/samba/*`, `/etc/dnsmasq.d/*` |
| Service management | `systemctl` for specific services only |
| Security hardening | `ufw`, `sshd` restart, `fail2ban` install |
| Docker | `docker` commands, Docker install packages |
| Cloudflare | `cloudflared`, apt install, service management |
| Self-update | `bin/amahi-update`, `systemctl restart amahi-kai` |

The sudoers file is validated with `visudo -cf` during installation to prevent syntax errors from locking out sudo.

---

## Firewall (UFW)

The installer opens port 3000 in UFW if it's active. The security auto-fix configures UFW with:

- Default deny incoming
- Allow SSH (22/tcp)
- Allow Amahi-kai (3000/tcp)

### Managing UFW

```bash
# Check status
sudo ufw status verbose

# Allow additional ports (e.g., for Samba)
sudo ufw allow 445/tcp comment "Samba"
sudo ufw allow 139/tcp comment "Samba (NetBIOS)"

# Allow a specific Docker app port
sudo ufw allow 8096/tcp comment "Jellyfin direct access"
```

> Note: If you only access Docker apps through Amahi-kai's reverse proxy, you don't need to open their individual ports — everything goes through port 3000.

---

## SSH Hardening

The auto-fix configures SSH with:

- **Root login disabled** — Use a regular user and `sudo` instead
- **Password authentication disabled** — Use SSH keys only

### Setting Up SSH Keys Before Disabling Passwords

```bash
# On your local machine, generate a key (if you don't have one)
ssh-keygen -t ed25519

# Copy it to the server
ssh-copy-id youruser@<server-ip>

# Verify key-based login works
ssh youruser@<server-ip>

# Now it's safe to disable password authentication
```

Amahi-kai also supports managing SSH public keys through the user model — each user can have a `public_key` field that gets written to their `~/.ssh/authorized_keys`.

---

## Best Practices

1. **Change the default admin password immediately** after installation
2. **Run the security audit** and fix all issues before enabling remote access
3. **Use SSH keys** instead of passwords for remote shell access
4. **Keep the system updated** — enable unattended upgrades or run `sudo apt update && sudo apt upgrade` regularly
5. **Review open ports** periodically with `ss -tlnp`
6. **Don't expose Samba to the internet** — keep it LAN-only with interface binding
7. **Back up regularly** — especially `/etc/amahi-kai/amahi.env` and `/opt/amahi/apps/`
