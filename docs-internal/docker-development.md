# Docker Development Environment

*The Docker stack is for **development and CI** only. Production uses native installation via `bin/amahi-install`.*

---

## Overview

Amahi-kai ships a `docker-compose.yml` for local development. It provides:

- **MariaDB** — matches the production database
- **Rails app** — with hot reload via volume mounts
- **Consistent environment** — same Ruby, same gems, same DB across all developers

The dev stack runs with `RAILS_ENV=development` and `dummy_mode: true`, so no real system commands are executed. This is intentional — Docker is not the production target.

## Quick Start

```bash
git clone git@github.com:CatDogBark/Amahi-kai.git
cd Amahi-kai
docker compose up --build
```

Visit `http://localhost:3000`. Login: `admin` / `secretpassword`.

## What's in the Stack

### `docker-compose.yml`

- **db** — MariaDB 10.11, data persisted in a Docker volume
- **web** — Rails app built from `Dockerfile`, port 3000 exposed

### Development Defaults

| Setting | Value |
|---------|-------|
| `RAILS_ENV` | `development` |
| `dummy_mode` | `true` (no real system commands) |
| Database | MariaDB via Docker service |
| Assets | Served by Rails (no precompilation needed) |

## Volume Mounts

The dev compose mounts your local checkout into the container for hot reload. No host system paths (`/etc/passwd`, `/etc/samba`, etc.) are mounted — those are only relevant in production native installs.

## Running Tests

```bash
# Full suite
docker compose exec web bundle exec rspec

# By category
docker compose exec web bundle exec rspec spec/models
docker compose exec web bundle exec rspec spec/requests
docker compose exec web bundle exec rspec spec/features
```

## CI

The same Docker setup works in GitHub Actions. See `.github/workflows/` for the CI config, which uses SQLite for speed.

## Production

For production deployment, see `bin/amahi-install` which installs Amahi-kai natively on Ubuntu 24.04. Docker is not used in production — the app runs directly on the host with systemd, nginx, and native service management.

---

*See also: [Privilege Escalation Mitigation](security/PRIVILEGE-ESCALATION-MITIGATION.md) for the sudoers allowlist used in production.*
