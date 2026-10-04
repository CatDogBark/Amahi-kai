# Native Install Guide

## Requirements

- **OS:** Ubuntu 24.04 or Debian 12+
- **RAM:** 2GB minimum (4GB recommended)
- **Disk:** 10GB+ for OS + app; additional storage for file shares
- **Network:** Static IP recommended. Amahi-kai can also run DNS and DHCP for your LAN (optional, Network → Gateway)

## Install

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

The installer is idempotent — run it again to update or repair.

## What It Does

1. Installs system packages (build tools, MariaDB, Samba, dnsmasq)
2. Installs Ruby 3.2 (the system package where there is one, else built with rbenv)
3. Creates the `amahi` system user
4. Deploys application to `/opt/amahi-kai`
5. Configures MariaDB (database + user)
6. Runs migrations and seeds the database
7. Precompiles assets
8. Installs the root helper (`/usr/local/sbin/amahi-helper`) and the app's sudoers rules
9. Creates and enables the `amahi-kai` systemd service
10. Opens port 3000 in UFW (if active)
11. Starts Samba (smbd/nmbd) for file sharing

## Post-Install

### Configuration

Edit `/etc/amahi-kai/amahi.env` for:

- `SECRET_KEY_BASE` — auto-generated, don't change unless rotating
- `DATABASE_*` — MariaDB connection details
- `RAILS_ALLOWED_HOSTS` — extra host names (comma-separated) the web UI answers to, for a domain that isn't the NAS's own name. Not needed for the Cloudflare Tunnel or Tailscale
- `AMAHI_DUMMY_MODE` — `true` to stub out system commands (for testing)

### Service Management

```bash
systemctl status amahi-kai    # App status
systemctl restart amahi-kai   # Restart after config changes
journalctl -u amahi-kai -f    # Live logs

systemctl status mariadb      # Database
systemctl status smbd         # Samba file sharing
systemctl status dnsmasq      # DNS (if enabled)
```

### Default Login

- **Username:** `admin`
- **Password:** `secretpassword`

The setup wizard won't finish until you change it.

### File Shares

Shares are stored under `/var/lib/amahi-kai/files/` by default, or on a data drive mounted under `/mnt`; folders anywhere else are refused. Create and manage them from the Shares tab in the web UI.

User accounts, Samba's config and share folders are changed by the root helper, which checks every request and logs it to `/var/log/amahi-kai/helper.log`.

### Cloudflare Tunnel (Optional)

To reach your server from anywhere, set up a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) from Network → Remote Access. It points to `http://localhost:3000`; requests through it come from the NAS itself, so no host setting is needed.

## Updating

Amahi-kai checks for updates every 6 hours. **Settings → System Status** shows what's new (each change linked to its pull request) with **Update now**, or **Repair** when you're up to date. Over SSH:

```bash
sudo /opt/amahi-kai/bin/amahi-update            # update
sudo /opt/amahi-kai/bin/amahi-update --repair   # run every step again on the current version
```

An update pulls the code, installs gems, backs up the database, runs migrations, installs the root helper and sudoers rules, regenerates the Samba config and restarts the app; if a step or the restarted app fails, it rolls back to the version that was running. With nothing new it stops after the pull. (A bare `git pull` and restart skips the helper and sudoers steps.)

Or re-run the installer:

```bash
sudo bin/amahi-install
```
