# Amahi-kai

A web-based home server management platform for Ubuntu/Debian. Manage users, file shares, apps, networking, and system settings from your browser.

Modernized fork of the [original Amahi Platform](https://github.com/amahi/platform), revived for modern Linux.

## Stack

- **Ruby** 3.2 / **Rails** 8.0
- **Bootstrap** 5.3 / **Stimulus** + vanilla JS (jQuery-free)
- **MariaDB** (production) / SQLite (test)
- **Ubuntu** 24.04 / Debian 12
- **systemd** service management

## Quick Start (Native Install)

Designed for a dedicated Ubuntu 24.04 or Debian 12+ server:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

The installer handles everything: Ruby, MariaDB, Samba, dnsmasq, systemd service, asset compilation, and firewall rules. It's idempotent — safe to run again.

Once complete:

- **Web UI:** `http://<your-server-ip>:3000`
- **Login:** `admin` / `secretpassword` (change this immediately)
- **Logs:** `journalctl -u amahi-kai -f`
- **Config:** `/etc/amahi-kai/amahi.env`

### Alternative: Docker

For development or quick evaluation:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
docker compose up
```

Visit `http://localhost:3000` — login: `admin` / `secretpassword`

> **Note:** The Docker setup is for development/testing. Native install is recommended for production use — it needs direct access to Samba, dnsmasq, and systemd to manage your server.

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
