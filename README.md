# Amahi-kai

[![CI](https://github.com/CatDogBark/Amahi-kai/actions/workflows/ci.yml/badge.svg)](https://github.com/CatDogBark/Amahi-kai/actions/workflows/ci.yml)

A web-based home server for Ubuntu/Debian: users, file shares, storage pooling, Docker apps,
networking and remote access, managed from your browser.

A modernized fork of the [original Amahi platform](https://github.com/amahi/platform), revived for
current Linux.

## Install

On a dedicated Ubuntu 24.04 or Debian 12+ machine:

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash
```

Or from a checkout:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

Then open `http://<your-server-ip>:3000`. The setup wizard runs on first login: admin password,
network, drives, storage pool and a first share. More in [docs/NATIVE-INSTALL.md](docs/NATIVE-INSTALL.md).

- **Updates:** Amahi-kai checks every 6 hours; Settings → System Status shows what's new, with
  Update now (or Repair). A failed update rolls back.
- **Logs:** `journalctl -u amahi-kai -f`
- **Config:** `/etc/amahi-kai/amahi.env`

## Features

- **File sharing:** Samba shares with per-user access, a web file browser, and Greyhole storage
  pooling across drives
- **Docker apps:** one-click installs from a catalog of its own, [amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps)
  (Jellyfin, Vaultwarden, Gitea, Uptime Kuma, Transmission, bitTube), with updates that copy the
  app's data first and roll back by themselves; [make your own](https://amahi-kai.com/wiki/making-apps)
- **Remote access:** Cloudflare Tunnel (no port forwarding) and Tailscale
- **Dashboard:** CPU, memory, per-drive storage and services; Settings → Servers for each service's
  version, uptime and controls
- **Security audit:** checks SSH, the firewall and updates, with fixes
- **Ocean UI:** animated underwater background, glass panels, light/dark/system themes

## Security

- Root actions go through one root helper (`libexec/amahi-helper`) that validates every request
  and logs it; sudo allows only the helper and Docker. Root owns the installed code.
- bcrypt passwords; per-request sessions that expire after 7 idle days; a password change signs
  out other browsers
- CSRF protection, with system actions on POST only; login rate limiting; a host allowlist
- Secrets stay off command lines and out of logs
- Details: [docs/security/PRIVILEGE-ESCALATION-MITIGATION.md](docs/security/PRIVILEGE-ESCALATION-MITIGATION.md)

## Development

Ruby 3.2, Rails 8.1, Bootstrap 5.3 with Stimulus and plain JavaScript, MariaDB in production and
SQLite for tests.

```bash
bundle install
RAILS_ENV=test bundle exec rails db:schema:load
bundle exec rspec spec/models/ spec/services/ spec/helpers/
bundle exec rspec spec/lib/
bundle exec rspec spec/requests/
```

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for how changes are made, and
[docs/plans/roadmap.md](docs/plans/roadmap.md) for what's done and what's next.

| Folder | What's there |
| --- | --- |
| `app/` | Controllers, models, views, helpers, services, assets |
| `lib/` | System integration: disks, Samba, Greyhole, Docker, tunnel, services, update status |
| `libexec/amahi-helper` | The root helper |
| `bin/` | `amahi-install`, `amahi-update` and the scripts they run |
| `config/` | Rails config, the Docker app catalog, sudoers rules, systemd units |
| `docs/` | Install guide, security model, plans |
| `public/themes/` | Themes (plain CSS) |
| `site/` | The amahi-kai.com website and wiki |

## Credits

- **Original:** [Amahi](http://www.amahi.org) (2007-2013)
- **Modernization:** Kai 🌊 + Troy (2026)

## License

GNU AGPL v3. See [COPYING](COPYING) and [NOTICE.md](NOTICE.md).
