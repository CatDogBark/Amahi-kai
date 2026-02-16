# Amahi-kai

A web-based home server management platform for Ubuntu/Debian. Manage users, file shares, apps, networking, and system settings from your browser.

Modernized fork of the [original Amahi Platform](https://github.com/amahi/platform), revived for modern Linux.

## Stack

- **Ruby** 3.2 / **Rails** 8.0
- **Bootstrap** 5.3 / **Stimulus** + vanilla JS (jQuery-free)
- **MariaDB** (production) / SQLite (test)
- **Ubuntu** 24.04 / Debian 12
- **systemd** service management

## Quick Start

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
docker compose up
```

Visit `http://localhost:3000` — login: `admin` / `secretpassword`

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

- **Original**: [Amahi](http://www.amahi.org) (2007-2013)
- **Modernization**: Kai 🌊 + Troy (2026)

## License

GNU AGPL v3 — see [COPYING](COPYING) and [NOTICE.md](NOTICE.md).
