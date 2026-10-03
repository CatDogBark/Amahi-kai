# Changelog

All notable changes to Amahi-kai are documented here.

## [Unreleased] — v1.0.0

### 🚀 Major Features

- **Role-Based Access Control (RBAC)** — Three roles: admin (full access), user (dashboard + file browser + search), guest (Samba-only). Per-share access and write permissions.
- **Native File Browser** — Browse, upload, download, rename, delete, create folders, preview images/video/audio/PDF. Drag-and-drop, multi-select, bulk delete. Replaced Docker FileBrowser app.
- **Tailscale VPN Integration** — Install, connect, disconnect from the web UI. Auth URL parsing (no blocking `tailscale login`).
- **Cloudflare Tunnel** — Install, configure, start/stop from Remote Access page. Security audit gates tunnel activation.
- **Security Audit System** — 8 automated checks with auto-fix: SSH hardening, firewall, updates, password policy. Streaming terminal output.
- **Setup Wizard** — 7-step first-run wizard: welcome → admin password → network → storage → greyhole → shares → complete. Drive detection, format, mount. Swap check.
- **Theme System** — 3-state toggle (light/dark/system). CSS variables, localStorage persistence, smooth transitions.
- **Toast Notifications** — Fixed-position toasts replace flash banners. No layout shift.
- **Dashboard Rework** — Per-drive storage bars, CPU/memory stats, services sidebar, share cards with browse buttons, quick action buttons.
- **Ocean UI** — Living underwater background (`ocean.js`, WebGL + canvas): the surface overhead in perspective, sun and moon following the clock, caustics and light shafts, weather (clear/cloudy/rain/storm with lightning), tides, bubbles in front of and behind the cards, and sea life (fish schools, manta rays, dolphins, sea turtles, night jellyfish). The scene is computed from the clock plus the visitor's settings, so it carries across page loads. A "Water" panel in the header (a floating button on amahi-kai.com) sets time of day, weather, sea life, cycle speed and quality. Half-resolution water, 30 fps cap, 12 fps when idle, automatic quality drop on slow frames, still frames under reduced motion. Glass cards by default. Fixes invisible bubbles on the login and setup pages (their colour came from a theme stylesheet those pages don't load).

### 🔒 Security & Fixes

- **Removed the legacy first-run endpoints** (`/start`, `/user_sessions/initialize_system`). They created an admin account without logging in and never checked whether the system was already set up. The first admin comes from the seeds and the setup wizard.
- **Linux accounts for web users are created again.** `useradd` was called with `--disabled-password`, an `adduser` option it rejects, so no Linux or Samba account was made. The password stays locked by default.
- **Samba passwords reach pdbedit on stdin.** The sync used `sudo sh -c`, which the sudoers allowlist doesn't permit, and put the password in the command line and the log.
- **Existing users get their missing Linux account** the next time their password is set, so users created while `useradd` was failing (including the seeded admin) can be added to Samba.
- **Settings → Servers buttons work again.** The status template used `self.formats = ['html']`, which current Rails rejects, so refresh, start, stop and restart returned 500.
- **Share pool-copies buttons save the chosen number.** The controller read the wrong parameter, saved 0 copies, then failed rendering a stale partial.
- **Deleting a user removes their Linux account even if they had no Samba entry**, and only removes accounts the app created, so deleting a web user can't remove a pre-existing login such as the install user.
- **Glass panels on every page.** Tables, settings panels and `.bg-white` panels use the dashboard cards' translucent background; nested panels stay clear so they don't stack into an opaque block. The dashboard banner says "Amahi-kai" instead of the lowercase hostname, and shows the hostname only when the server has its own name.
- **Sessions can't cross between requests.** `UserSession` kept the current controller in one class-level variable shared by Puma's threads, so a concurrent request could read or write another request's session. It now lives in per-request `Current` attributes. Login also starts a fresh session.
- **The footer is a glass bar pinned to the bottom of the window** instead of an opaque bar that moved with the page height.
- **Actions that change the system can't be triggered by a link.** Reboot, power off, setting toggles, server controls, theme activation, language and logout are POST-only. Progress streams (system update, installs, drive preparation, security fixes) only start when the browser reports the request came from an Amahi page (`Sec-Fetch-Site: same-origin`). The setup wizard is closed once setup is complete.
- **Power off and Reboot ask for confirmation again** and are aligned buttons with labels. They were link helpers the current JavaScript ignores, so they sent a GET and skipped the prompt.
- **CI fails on spec failures again.** The gate matched "0 failures" anywhere, including in "10 failures".

### 🔧 Architecture & Code Quality

- **Plugin Consolidation** — All 6 plugin engines (Users, Shares, Network, Disks, Apps, Settings) merged into main app. Single layout, unified routing.
- **Auth Modernization** — Authlogic → `has_secure_password` (bcrypt). Removed DES crypt (was truncating to 8 chars!). Linux users created with a locked password. Two stores: bcrypt (web) + pdbedit (Samba).
- **Login Rate Limiting** — rack-attack throttling on login attempts.
- **12 Service Objects** — SetupService, DiskService, FileBrowserService, ContainerService, CloudflareService, DockerService, TailscaleService, ShareAccessManager, ShareFileSystem, SambaService, DnsmasqService, SwapService.
- **Security Hardening** — SQL injection, shell injection, XSS, CSRF protection. CSP headers. Narrowed rescue clauses from `StandardError` to specific exceptions.
- **Installer Error Handling** — `bin/amahi-install` now detects and reports failures in bundle install, migrations, seeding, and asset compilation with actionable guidance.
- **Idempotent Migrations** — `column_exists?` guards for MariaDB (no transactional DDL).
- **Icon System** — 34 vendored Lucide SVGs via `IconHelper`. Zero glyphicons/bootstrap-icons remaining.
- **CI Pipeline** — 5 parallel jobs (models, requests, lib, features, lint+security). RuboCop + Brakeman. SimpleCov coverage report with group breakdown.

### 📊 Test Coverage

- 312+ specs across models, requests, lib, helpers, features
- 44.7% line coverage (Models 53%, Helpers 82%, Services 74%)
- Automated coverage report on every CI run

### 🏠 Infrastructure

- **Native Install** — `curl -fsSL https://amahi-kai.com/install.sh | sudo bash` — single command, full stack.
- **Samba + Greyhole** — Storage pooling with configurable copy counts per share.
- **Docker App System** — 14-app catalog, reverse proxy at `/app/{identifier}`, install/uninstall/start/stop from UI.
- **Database-backed File Indexer** — Replaced locate-based search. Automatic reindexing via systemd timer.
- **System Status Dashboard** — Settings subtab with service health, system info.

### 🔄 Migration from v0.2.0

- Fresh install recommended (no upgrade path from pre-release versions)
- `bin/amahi-install` handles everything: deps, Ruby, MariaDB, Samba, migrations, assets, systemd service

---

## [0.2.0] — 2026-02-27

### Added
- HDA purge complete — all HDA/hda references removed
- AmahiHDA → AmahiKai module rename
- DNS cleanup — Cloudflare default, OpenDNS/OpenNIC removed
- install.sh safe.directory fix for updates
- All docs updated (README, CONTRIBUTING, NOTICE, wiki, site)
- Chromium + Selenium added to sandbox

## [0.1.2] — 2026-02-26

### Added
- Native file browser, toast notifications, theme toggle
- Dashboard rework, CI overhaul (5 parallel jobs)
- Plugin consolidation (all 6 engines merged)
- Password security (bcrypt, no DES), RBAC roles

## [0.1.1] — 2026-02-25

### Added
- Setup wizard enhancements, Samba/nmbd fixes
- Drive detection improvements

## [0.1.0] — 2026-02-24

### Added
- First public release
- Rails 8.0.4, Ruby 3.2.10
- Docker app system, Greyhole integration
- Cloudflare Tunnel, security audit
- Native installer, GitHub Pages site
