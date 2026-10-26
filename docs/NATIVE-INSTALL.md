# Native Install Guide

## Requirements

- **OS:** Ubuntu 24.04 (Server), on a dedicated machine or VM
- **RAM:** 2GB minimum (4GB recommended)
- **Disk:** a system disk of 32GB or more (64GB with apps), since the dashboard warns once less than
  10GB is free there; other drives for file shares
- **Network:** a fixed address: set one on Network → Devices (This NAS) after installing, or reserve
  it in your router. Amahi-kai can also be your LAN's DNS and DHCP server, and its router (optional,
  Network → DNS, DHCP and Internet)

## Install

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash
```

Or from a checkout (the installer clones it into `/opt/amahi-kai`, with its git history; updates
then come from GitHub):

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

Running it again is safe: it keeps users, shares, settings and the version installed, and
restarts the app. New versions come through System Update (below).

## What It Does

1. Installs system packages: build tools, Ruby 3.2 (Ubuntu's), MariaDB, Samba, Avahi, smartmontools
2. Creates the `amahi` system user
3. Deploys the application to `/opt/amahi-kai`, with its git history
4. Configures MariaDB (database + user) and installs the gems
5. Installs the root helper (`/usr/local/sbin/amahi-helper`), the app's sudoers rules and its
   systemd services and timers (from `config/systemd`)
6. Runs migrations and, on a new install, creates the admin account and shows its password
7. Precompiles assets
8. Opens port 3000 in UFW (if active)
9. Writes Samba's configuration (the server itself, the LAN and Tailscale only) and starts smbd/nmbd
10. Builds the file search index, then starts Amahi-kai and checks it answers

## Post-Install

### Configuration

Edit `/etc/amahi-kai/amahi.env` for:

- `SECRET_KEY_BASE` — auto-generated, don't change unless rotating
- `DATABASE_*` — MariaDB connection details
- `RAILS_ALLOWED_HOSTS` — extra host names (comma-separated) the web UI answers to, for a domain that isn't the NAS's own name. Not needed for the Cloudflare Tunnel or Tailscale

### Service Management

```bash
systemctl status amahi-kai    # App status
systemctl restart amahi-kai   # Restart after config changes
journalctl -u amahi-kai -f    # Live logs

systemctl status mariadb      # Database
systemctl status smbd         # Samba file sharing
systemctl status unbound      # DNS (if on)
systemctl status dnsmasq      # DHCP (if on)
```

### First Login

- **Username:** `admin`
- **Password:** a random one this install prints, as soon as it's made and again when it finishes. Save it.

The setup wizard won't finish until you choose a password of your own. If the printed one is
lost before then, set a new one on the server with `sudo /opt/amahi-kai/script/reset-user-password admin`.

### File Shares

Shares are stored under `/var/lib/amahi-kai/files/` by default, or on a data drive mounted under `/mnt`; folders anywhere else are refused. Create and manage them from the Shares tab in the web UI.

User accounts, Samba's config and share folders are changed by the root helper, which checks every request and logs it to `/var/log/amahi-kai/helper.log`.

### Cloudflare Tunnel (Optional)

To reach your server from anywhere, set up a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) from Network → Remote Access. It points to `http://localhost:3000`; requests through it come from the NAS itself, so no host setting is needed.

## Updating

Amahi-kai checks for updates every 6 hours, on its update channel: `releases` (the default), `candidates` (release candidates too) or `development` (the dev branch), chosen on **Settings → System Status** (Follows) and kept as `AMAHI_UPDATE_CHANNEL` in `/etc/amahi-kai/amahi.env` ([Updating](https://amahi-kai.com/wiki/updating)). **Settings → System Status** shows what's new (each change linked to its pull request) with **Update now**, or **Repair** when you're up to date. Over SSH:

```bash
sudo /opt/amahi-kai/bin/amahi-update            # update
sudo /opt/amahi-kai/bin/amahi-update --repair   # run every step again on the current version
```

An update checks out the channel's newest version, installs gems, backs up the database, runs migrations, installs the root helper and sudoers rules, regenerates the Samba config, makes the network's settings again where they differ (DNS, blocking, DHCP, the IPv6 announcement and the router's rules), checks the user accounts and restarts the app; if a step or the restarted app fails, it rolls back to the version that was running, with that version's Samba and network settings. With nothing new it stops after the pull. (A bare `git pull` and restart skips the helper and sudoers steps.)

Amahi-kai doesn't back the server up: see [What Amahi-kai doesn't back up](https://amahi-kai.com/wiki/getting-started#what-amahi-kai-doesnt-back-up).

Re-running the installer (`sudo /opt/amahi-kai/bin/amahi-install`) sets up the system again
around the version installed, without changing it.
