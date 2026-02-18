# Native Install Guide

## Requirements

- **OS:** Ubuntu 24.04 or Debian 12+
- **RAM:** 2GB minimum (4GB recommended)
- **Disk:** 10GB+ for OS + app; additional storage for file shares
- **Network:** Static IP recommended (the server manages DNS/DHCP for your LAN)

## Install

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

The installer is idempotent — run it again to update or repair.

## What It Does

1. Installs system packages (build tools, MariaDB, Samba, dnsmasq)
2. Installs Ruby 3.2 via rbenv (system-wide)
3. Creates the `amahi` system user
4. Deploys application to `/opt/amahi-kai`
5. Configures MariaDB (database + user)
6. Runs migrations and seeds the database
7. Precompiles assets
8. Installs a least-privilege sudoers allowlist
9. Creates and enables the `amahi-kai` systemd service
10. Opens port 3000 in UFW (if active)
11. Starts Samba (smbd/nmbd) for file sharing

## Post-Install

### Configuration

Edit `/etc/amahi-kai/amahi.env` for:

- `SECRET_KEY_BASE` — auto-generated, don't change unless rotating
- `DATABASE_*` — MariaDB connection details
- `RAILS_ALLOWED_HOST` — set this if accessing via a domain/tunnel
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

**Change this immediately** after first login.

### File Shares

Shares are stored under `/var/hda/files/` by default. Create and manage them from the Shares tab in the web UI.

### Cloudflare Tunnel (Optional)

To access your server remotely via a domain, set up a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) pointing to `http://localhost:3000` and add your domain to `RAILS_ALLOWED_HOST` in the env file.

## Updating

```bash
cd /opt/amahi-kai
sudo -u amahi git pull
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && bundle install && RAILS_ENV=production bin/rails db:migrate && RAILS_ENV=production bin/rails assets:precompile"
sudo systemctl restart amahi-kai
```

Or re-run the installer:

```bash
sudo bin/amahi-install
```
