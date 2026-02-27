# Contributing to Amahi-kai

## Development Setup

### Native (recommended)

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

The installer sets up everything. The setup wizard runs on first visit.

### Local (without installer)

```bash
# Install Ruby 3.2, MariaDB, SQLite3, smbclient
bundle install
bin/rails db:create db:migrate db:seed
bin/rails s
```

### Docker (testing only)

```bash
docker compose up
```

Visit `http://localhost:3000` — Docker is for quick evaluation, not full development.

## Running Tests

Tests use SQLite (no MariaDB needed). Run specs in groups to manage memory:

```bash
bundle exec rspec spec/models/       # Model specs
bundle exec rspec spec/requests/     # Request specs
bundle exec rspec spec/lib/          # Library specs
bundle exec rspec spec/features/ --tag ~js  # Feature specs (no browser)
bundle exec rspec spec/features/     # Full feature specs (needs chromium)
```

## Architecture

### App Structure

Monolithic Rails app — no plugins. All controllers live in `app/controllers/`:

| Area | Controller | Routes |
|------|-----------|--------|
| Users | `UsersController` | `/users` |
| Shares | `SharesController` | `/shares` |
| Disks | `DisksController` | `/disks/*` |
| Apps | `AppsController` | `/apps/*` |
| Network | `NetworkController` | `/network/*` |
| Settings | `SettingsController` | `/settings/*` |
| File Browser | `FileBrowserController` | `/files/:share_id/*` |
| Setup | `SetupController` | `/setup/*` |

Service objects in `app/services/`: `ShareFileSystem`, `SambaService`, `ShareAccessManager`.

### Frontend Stack

- **Bootstrap 5.3** for CSS/components
- **Stimulus** controllers for interactivity (8 reusable controllers)
- **Turbo** installed but Drive disabled globally (`data-turbo="false"` on body)
- **Sprockets** for asset pipeline
- **No jQuery** — all JS is vanilla + Stimulus

Stimulus controllers live in `app/assets/javascripts/controllers/`.

### Key Classes

- `Shell` (lib/shell.rb) — Executes system commands with auto-sudo, dummy mode for test/dev, and logging
- `Platform` (lib/platform.rb) — OS detection, Ubuntu/Debian only
- `SetTheme` (lib/set_theme.rb) — Theme loading and switching
- `ContainerService` (lib/container_service.rb) — Docker app lifecycle management
- `AppCatalog` (lib/app_catalog.rb) — YAML-based Docker app catalog
- `AppProxyController` — Reverse proxy for Docker apps at `/app/{identifier}`

## Conventions

### Security

- **Always** use `Shellwords.escape` for shell command arguments
- **Never** interpolate user input into SQL — use parameterized queries
- All fetch requests must include CSRF tokens (use `csrfHeaders()` helper)
- Credential storage uses `AES-256-GCM` via `ActiveSupport::MessageEncryptor`

### Testing

- Use raw SQL INSERT for models that override `initialize()` (App, Webapp)
- Use `Rails.cache.delete("key")` instead of `Rails.cache.clear` (conflicts with seeds)
- Run `mkdir -p tmp/cache/tmpfiles` before model specs
- Seeds run before every test — this ensures clean state but is slow

### Code Style

- Controllers use `before_action :admin_required` for protected actions
- Return proper HTTP status codes (422 for validation failures)
- Views use Slim templates
- Locales in `config/locales/`

## License

GNU AGPL v3 — all contributions must be compatible with this license.
