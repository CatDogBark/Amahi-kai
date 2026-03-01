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
- **Ocean UI** — Breathing gradient background, SVG waves, glassmorphism cards.

### 🔧 Architecture & Code Quality

- **Plugin Consolidation** — All 6 plugin engines (Users, Shares, Network, Disks, Apps, Settings) merged into main app. Single layout, unified routing.
- **Auth Modernization** — Authlogic → `has_secure_password` (bcrypt). Removed DES crypt (was truncating to 8 chars!). Linux users created with `--disabled-password`. Two stores: bcrypt (web) + pdbedit (Samba).
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
