# Amahi-kai

[![CI](https://github.com/CatDogBark/Amahi-kai/actions/workflows/ci.yml/badge.svg)](https://github.com/CatDogBark/Amahi-kai/actions/workflows/ci.yml)

A web-based home server management platform for Ubuntu/Debian. Manage users, file shares, apps, networking, and system settings from your browser.

Modernized fork of the [original Amahi Platform](https://github.com/amahi/platform), revived for modern Linux.

## Stack

- **Ruby** 3.2 / **Rails** 8.0
- **Bootstrap** 5.3 / **Stimulus** + vanilla JS (jQuery-free)
- **MariaDB** (production) / SQLite (test)
- **Ubuntu** 24.04 / Debian 12
- **systemd** service management

## Install

One command on a dedicated Ubuntu 24.04 or Debian 12+ server:

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash
```

That's it. The installer handles Ruby, MariaDB, Samba, systemd, asset compilation, and all dependencies.

### Manual Install

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

### After Install

- **Web UI:** `http://<your-server-ip>:3000`
- **Setup Wizard** runs on first login — creates admin account, detects drives, configures storage
- **Logs:** `journalctl -u amahi-kai -f`
- **Config:** `/etc/amahi-kai/amahi.env`
- **Update:** `curl -fsSL https://amahi-kai.com/install.sh | sudo bash` (same command, idempotent)

## Features

- **📁 File Sharing** — Samba shares with built-in file browser, Greyhole storage pooling across multiple drives
- **🐳 Docker Apps** — One-click install for Jellyfin, Nextcloud, Syncthing, Grafana, Gitea, and more
- **🌐 Remote Access** — Cloudflare Tunnel integration (no port forwarding needed)
- **📊 Dashboard** — Real-time CPU, memory, per-drive storage, services, and app quick-launch
- **🔒 Security Audit** — Built-in scanner with auto-fix for SSH, firewall, updates
- **🔧 Setup Wizard** — 7-step guided setup with drive detection, swap creation, and Greyhole pooling
- **🌊 Ocean UI** — Animated ambient background, glassmorphism cards, light/dark/system theme toggle
- **🔄 One-Click Updates** — Update from the browser or re-run the installer

## Development

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails s
```

### Tests

```bash
bundle exec rspec spec/models/    # Model specs
bundle exec rspec spec/requests/  # Request specs
bundle exec rspec spec/lib/       # Library specs
bundle exec rspec                 # Full suite
```

## Architecture

Monolithic Rails app — clean, no plugins.

| Directory | Purpose |
|-----------|---------|
| `app/controllers/` | Users, shares, disks, apps, network, settings, file browser, setup |
| `app/services/` | ShareFileSystem, SambaService, ShareAccessManager |
| `lib/` | Shell, DiskManager, Greyhole, CloudflareService, SecurityAudit, DashboardStats |
| `config/docker_apps/` | Docker app catalog (YAML) |

## Security

- **bcrypt** password hashing via `has_secure_password`
- **Rack::Attack** rate limiting on login
- **Content Security Policy** headers
- **Shell module** with automatic sudo and Shellwords escaping
- **AES-256-GCM** encryption for stored credentials
- **Parameterized SQL** everywhere
- **Security audit** with auto-fix (SSH hardening, firewall, unattended upgrades)

## Credits

- **Original**: [Amahi](http://www.amahi.org) by Carlos Puchol (2007-2013)
- **Modernization**: Kai 🌊 + Troy (2026)

## License

GNU AGPL v3 — see [COPYING](COPYING) and [NOTICE.md](NOTICE.md).
