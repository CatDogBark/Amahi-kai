# Amahi Platform

[![Build Status](https://secure.travis-ci.org/amahi/platform.png)](http://travis-ci.org/amahi/platform)

The Amahi Platform is a web-based app that allows management of users, shares,
apps, networking and other settings in a Linux-based PC, VM or ARM-based system.

This is a modernized fork of the [original Amahi Platform](https://github.com/amahi/platform),
updated to run on Ubuntu/Debian with modern Ruby and dependencies.

## What's Changed

- **Platform**: Ubuntu 24.04 / Debian 12 (was Fedora)
- **Database**: MariaDB (was MySQL)
- **Ruby**: 3.2.10 (was 2.4.3 → 2.7.8 → 3.2.10)
- **Rails**: 7.0.10 (was 5.2.8 → 6.0 → 6.1 → 7.0)
- **Services**: systemd (removed upstart/init.d support)
- **Auth**: SCrypt password hashing (migrated from Sha512)
- **Assets**: Plain JavaScript (migrated from CoffeeScript)

## Quick Start with Docker

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
docker-compose up
```

Visit `http://localhost:3000/`, login with username `admin` and password `secretpassword`.

## Development Setup (Manual)

### Prerequisites

- Ruby 2.7+
- MariaDB or MySQL
- Node.js (for asset compilation)
- Bundler

### Setup

```bash
bundle install
# Configure config/database.yml for your MariaDB/MySQL setup
rake db:create
rake db:migrate
rake db:seed
rails s
```

### Running Tests

```bash
# All non-JS specs (no browser needed)
bundle exec rspec --tag ~js

# Model specs only
bundle exec rspec spec/models/

# All specs including JS (requires chromium + chromedriver)
bundle exec rspec
```

### Default Credentials

- **Username**: `admin`
- **Password**: `secretpassword`

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b my-feature`)
3. Write tests for your changes
4. Run the test suite (`bundle exec rspec --tag ~js`)
5. Commit your changes
6. Create a pull request

## Architecture

The platform is organized as a Rails app with a plugin system:

- `app/` — Core application (controllers, models, views, helpers)
- `plugins/` — Feature modules:
  - `010-users` — User management
  - `020-shares` — Samba file shares
  - `030-disks` — Disk monitoring
  - `040-apps` — Application installer (Docker-based)
  - `050-network` — DNS, DHCP, fixed IPs
  - `080-settings` — System settings, themes

## Credits

- **Original Amahi Platform**: Copyright (C) 2007-2013, [Amahi](http://www.amahi.org)
- **Modernization**: Kai 🌊 (AI Agent) + Troy — revived for Ubuntu/Debian, 2026

## License

Licensed under the GNU AGPL v3. See [COPYING](COPYING) for full license text and [NOTICE.md](NOTICE.md) for attribution and fork details.
