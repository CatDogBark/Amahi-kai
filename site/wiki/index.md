---
layout: default
title: "Amahi-kai Documentation"
---

# Amahi-kai Documentation

Welcome to the Amahi-kai wiki, the documentation for your home server.

Amahi-kai is a self-hosted home server built on Rails 8.1, Ubuntu 24.04, Samba, Docker, Greyhole
and ZFS. It gives you file sharing, storage pools, a Docker app catalog, your network's DNS, DHCP
and router if you like, remote access, and a web UI to manage it all, from one install command.
It doesn't back itself up yet: see [what to keep copies of](getting-started#what-amahi-kai-doesnt-back-up).

---

## Quick Links

| Topic | Description |
|-------|-------------|
| [Getting Started](getting-started) | Installing, the setup wizard, system requirements |
| [File Sharing](file-sharing) | Shares, users and their roles, per-user permissions, the web file browser, Samba |
| [Storage Pooling](storage-pooling) | Adding drives safely, Greyhole, copies per share |
| [ZFS Pools](zfs-pools) | Pools across matched drives, replacing a drive, snapshots, drive health |
| [Docker Apps](docker-apps) | The app catalog, installing apps, their ports and data |
| [Making Apps](making-apps) | Packaging an app of your own for the catalog |
| [Remote Access](remote-access) | Cloudflare Tunnel and Tailscale |
| [Security](security) | The security audit and its fixes, how Amahi-kai uses root |
| [Networking](networking) | DNS, DHCP and the NAS as your router; devices and their names |
| [Updating](updating) | Update checks, Update now, Repair, automatic rollback |

---

## How it fits together

Amahi-kai runs as a systemd service (`amahi-kai.service`, Puma on port 3000) as its own user,
`amahi`. Anything that needs root goes through one root helper that checks and logs every request
(see [Security](security)). It manages:

- **Samba** (`smbd`/`nmbd`) for file sharing on your LAN
- **MariaDB** for its own data
- **Docker** (optional) for apps
- **Avahi** for announcing the apps on your LAN (mDNS)
- **Greyhole** (optional) for storage pooling
- **ZFS** (optional) for pools of matched drives, with snapshots
- **Unbound** (optional) for your network's DNS, encrypted to a provider, with blocking
- **dnsmasq** (optional) for DHCP only
- **radvd** (optional) for announcing the NAS as the IPv6 DNS server
- **UFW and netplan** for the firewall, and for router mode's internet side and NAT
- **Cloudflare Tunnel** and **Tailscale** (optional) for remote access

### Key paths

| Path | What's there |
|------|--------------|
| `/opt/amahi-kai` | The application (owned by root) |
| `/etc/amahi-kai/amahi.env` | Configuration (database, secret key) |
| `/var/lib/amahi-kai/files` | Default folder for shares |
| `/mnt/<name>` | Data drives |
| `/srv/pools/<name>` | ZFS pools |
| `/var/lib/amahi-kai/apps` | Docker app data, a folder per app |
| `/var/lib/amahi-kai/backups` | Database backups taken before each update (the last 3) |
| `/var/log/amahi-kai/helper.log` | Every root action, one line each |
| `/var/log/amahi-kai/update.log` | The last update's output |
| `/etc/samba/smb.conf` | Samba configuration (generated) |

### Services and timers

```
systemctl status amahi-kai                         # the web app
systemctl status mariadb                           # its database
systemctl status smbd nmbd                         # Samba
systemctl list-timers amahi-kai-update-check.timer # update check (Amahi-kai and its apps), every 6 hours
systemctl list-timers amahi-kai-indexer.timer      # file search index, every 10 minutes
systemctl list-timers amahi-kai-trash.timer        # the Trash: deletes what's been kept too long, daily
systemctl list-timers amahi-kai-snapshots.timer    # ZFS pool snapshots, every hour
systemctl list-timers amahi-kai-storage-check.timer # pool and drive health, every 15 minutes
```

**Settings → Servers** in the web UI shows each service's status, version and uptime, with
start, stop and restart where that's safe.

---

## Getting help

- **Report a problem**: in the web UI, **Settings → Help → Report a problem** (or **Report this
  problem** on a red flag) puts the report together for you: see
  [Reporting a problem](getting-started#reporting-a-problem).
- **GitHub Issues**: [github.com/CatDogBark/Amahi-kai/issues](https://github.com/CatDogBark/Amahi-kai/issues)
- **Email**: [catdogbark@pm.me](mailto:catdogbark@pm.me)
- **Logs**: **Settings → Help** shows Amahi-kai's, the root helper's, System Update's, the system
  journal and each app's, and **Download logs** saves them; over SSH, `journalctl -u amahi-kai -f`
