---
layout: default
title: "Amahi-kai Documentation"
---

# Amahi-kai Documentation

Welcome to the Amahi-kai wiki — the community-built documentation for your home server.

Amahi-kai is a modern, self-hosted home server platform built on Rails 8, Ubuntu 24.04, Samba, Docker, and Greyhole. It gives you file sharing, storage pooling, a Docker app catalog, remote access, and a web-based management UI — all from a single install command.

---

## Quick Links

| Topic | Description |
|-------|-------------|
| [Getting Started](getting-started) | Installation, first-run wizard, system requirements |
| [File Sharing](file-sharing) | Creating shares, per-user permissions, Samba config |
| [Storage Pooling](storage-pooling) | Greyhole setup, adding drives, file duplication |
| [Docker Apps](docker-apps) | App catalog, installing apps, reverse proxy |
| [Remote Access](remote-access) | Cloudflare Tunnel setup, token configuration |
| [Security](security) | Security audit, auto-fix, SSH hardening, firewall |
| [Networking](networking) | DNS aliases, dnsmasq, DHCP/DNS gateway |
| [Updating](updating) | CLI updates, web UI update button |

---

## Architecture Overview

Amahi-kai runs as a systemd service (`amahi-kai.service`) powered by Puma on port 3000. It manages:

- **Samba** (`smbd`/`nmbd`) for LAN file sharing
- **MariaDB** for application data
- **Docker** (optional) for containerized apps with built-in reverse proxy
- **Greyhole** (optional) for storage pooling and file duplication
- **dnsmasq** (optional) for local DNS and DHCP
- **Cloudflare Tunnel** (optional) for secure remote access

### Key Paths

| Path | Purpose |
|------|---------|
| `/opt/amahi-kai` | Application code |
| `/etc/amahi-kai/amahi.env` | Production configuration |
| `/var/lib/amahi-kai/files` | Default share root |
| `/opt/amahi/apps` | Docker app data |
| `/etc/samba/smb.conf` | Samba config (auto-generated) |
| `/etc/dnsmasq.d/` | dnsmasq config directory |

### Default Services

```
systemctl status amahi-kai    # Rails app (Puma on :3000)
systemctl status mariadb      # Database
systemctl status smbd         # Samba file sharing
systemctl status nmbd         # NetBIOS name service
```

---

## Getting Help

- **GitHub Issues**: [github.com/CatDogBark/Amahi-kai/issues](https://github.com/CatDogBark/Amahi-kai/issues)
- **Logs**: `journalctl -u amahi-kai -f`
- **Debug Tab**: Available in the web UI at `/tab/debug`
