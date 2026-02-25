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

That's it. The installer handles Ruby, MariaDB, Samba, dnsmasq, systemd, asset compilation, and firewall rules.

### Manual Install

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

### After Install

- **Web UI:** `http://<your-server-ip>:3000` (port 3000)
- **Setup Wizard** runs on first visit — creates your admin account
- **Logs:** `journalctl -u amahi-kai -f`
- **Config:** `/etc/amahi-kai/amahi.env`
- **Update:** Click the update button in the header, or run `sudo bin/amahi-update`

## Features

- **📁 File Sharing** — Samba shares with Greyhole storage pooling across multiple drives
- **🐳 Docker Apps** — One-click install for Jellyfin, Nextcloud, FileBrowser, Syncthing, Grafana, Gitea, and more
- **🌐 Remote Access** — Cloudflare Tunnel integration (no port forwarding needed)
- **📊 System Dashboard** — Real-time CPU, memory, disk, network, and service monitoring
- **🔒 Security Audit** — Built-in scanner with auto-fix for SSH, firewall, updates
- **🔧 Setup Wizard** — 6-step guided setup for fresh installs (+ headless mode)
- **🌙 Dark Mode** — Automatic, based on system preference
- **🔄 One-Click Updates** — Update from the browser

## Development

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails s
```

### Tests

```bash
bundle exec rspec --tag ~js     # Fast — no browser needed
bundle exec rspec spec/models/  # Model specs only
bundle exec rspec               # Full suite (needs chromium)
```

## Architecture

Rails app with a plugin system:

| Plugin | Purpose |
|--------|---------|
| `010-users` | User management |
| `020-shares` | Samba file shares |
| `030-disks` | Disk monitoring |
| `040-apps` | Application installer |
| `050-network` | DNS, DHCP, fixed IPs |
| `080-settings` | System settings, themes |

## Security

- **Rack::Attack** rate limiting on login
- **Content Security Policy** headers
- **SCrypt** password hashing (with Sha512 transition)
- **Shellwords.escape** on all shell commands
- **AES-256-GCM** encryption for stored credentials
- **Parameterized SQL** in database management
- Direct **systemd** integration (no more hda-ctl daemon)

## Credits

- **Original**: [Amahi](http://www.amahi.org) by Carlos Puchol (2007-2013)
- **Modernization**: Kai 🌊 + Troy (2026)

## License

GNU AGPL v3 — see [COPYING](COPYING) and [NOTICE.md](NOTICE.md).
