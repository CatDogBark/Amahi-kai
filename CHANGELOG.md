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
- **Actions that change the system can't be triggered by a link.** Reboot, power off, setting toggles, server controls, theme activation, language and logout are POST-only. Progress streams (system update, installs, drive preparation, security fixes) only start when the page proves it's an Amahi page: it sends its CSRF token in the stream URL, or the browser sends `Sec-Fetch-Site: same-origin` (HTTPS only). The setup wizard is closed once setup is complete.
- **Power off and Reboot ask for confirmation again** and are aligned buttons with labels. They were link helpers the current JavaScript ignores, so they sent a GET and skipped the prompt.
- **Remote Access and Security highlight the Network tab.** The tab bar fell back to the first tab with an `index` sub-tab, so those pages lit up Shares and showed its sub-tabs.
- **Files opened straight from a share can't run code on the Amahi page.** The raw-file endpoint serves HTML, JavaScript and XML as plain text and adds `Content-Security-Policy: sandbox` (except for PDFs). Previews look the same.
- **Themes:** only installed theme names are accepted, each theme's `init.rb` is loaded once instead of on every request, and the theme list no longer changes the server's working directory.
- **The app proxy no longer forwards the Amahi login cookie** to Docker apps; their own cookies still pass through.
- **Production only answers to known host names** (DNS-rebinding protection): any IP address, `localhost`, the machine's hostname and `hostname.local`, the NAS's Tailscale name, and the comma-separated `RAILS_ALLOWED_HOSTS` in `/etc/amahi-kai/amahi.env`. Requests from the NAS itself skip the check, so a Cloudflare Tunnel works with no setup. A refused request gets a plain-text explanation instead of a blank 403. The old `RAILS_ALLOWED_HOST` line only worked in development.
- **Re-running the installer no longer wipes the system.** `db/seeds.rb` started with `destroy_all` on users, shares, apps and settings (and `userdel -r` for every user); it now does nothing when the database already has users.
- **Disk safety:** new fstab entries are `nofail` so a missing data drive can't stop the NAS booting; the OS-disk guard recognises NVMe partitions and `/` on LVM; new mount points skip slots fstab still claims; and fstab entries are no longer deleted automatically.
- **Samba only answers the NAS itself, the LAN and Tailscale.** The generated `smb.conf` adds `hosts allow` (Docker's ranges are refused; apps get share folders as volumes) and binds to the LAN interface plus `tailscale0`. It keeps Greyhole's `wide links` settings when Greyhole is installed, gives the guest account no home share, and is checked with `testparm` before it's installed. `amahi-update` regenerates it and restarts Samba, and the security audit's fix regenerates it instead of editing it.
- **File browser:** uploads stream straight into the share (they went through a `sudo cp` the allowlist didn't permit); names such as `..` or ones with a slash are refused with a clear error instead of being rewritten, so `a..b.txt` is never mistaken for `ab.txt`; the share-boundary check compares whole path segments.
- **The tunnel token is root-only.** cloudflared reads it with `--token-file`; it was in the world-readable unit file and on cloudflared's command line. `amahi-update` migrates existing installs. Remote Access sends the token by POST instead of in the stream URL, and token-, secret- and key-like parameters are filtered from the logs.
- **The database password stays off command lines** during the Greyhole install (stdin and a private file instead), `/etc/greyhole.conf` becomes `root:amahi 640`, and Shell masks secret-shaped text in its log.
- **Sessions:** a login unused for 7 days ends (checked on the server), and changing a password signs out that user's other browsers.
- **System Update runs the steps it just pulled.** bash keeps executing the copy of `amahi-update` it opened, so a step added by an update only ran on the following update; the script now restarts itself as the new copy after pulling. Drives are re-mounted before the app restart, since restarting the app from the web UI also ends the script.
- **Failures are reported instead of ignored:** creating a user stops with an error when the Linux account can't be made; a password change is refused (and the old password kept) when Samba won't take it; a share whose folder can't be created isn't saved; a failed Docker pull or create ends the install with an error instead of hanging. Changing a share's path no longer skips creating the new folder when the old one has files in it.
- **The app proxy passes each Set-Cookie header separately**, so apps that set several cookies keep them.
- **Removed the PIN feature** (never used for login; setting one returned a 500) and its column.
- **Small fixes:** search paging is clamped (page 0 was a 500); the domain setting is escaped where it's used in a pattern; drive-preview file names are escaped; share indexing runs as an Active Job after commit instead of a bare thread.
- **CI fails on spec failures again.** The gate matched "0 failures" anywhere, including in "10 failures".
- **Stopping a Docker app reports the real result.** It checked `$?`, which `Shell.capture` doesn't set, so a stop succeeded or failed depending on whatever command ran before it.
- **Commands built from names run without a shell:** the dashboard's service status, drive models, server process lookup, Docker image pull and container create, and drive mounting pass argument lists, and the sudo path lookup is done in Ruby instead of a `which` subshell. Removed the unused script runner, archive unpacker and router-driver hook with its credential helpers.
- **Page HTML helpers escape what they insert** (page title, icon attributes, form error labels, the storage-pool warning).
- **Settings → Servers shows the NAS's services again**, live from systemd: status, installed version, uptime since the last start, memory, PID and whether each starts at boot, with Start, Stop and Restart for Samba, dnsmasq, Greyhole and Docker. It used to list a database table that nothing filled, so it was always empty. The dashboard, System Status and Servers now share one service list.

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
- **Rails 8.1.4** (Rails 8.0's security support ends 2026-11-07), with Rails 8.1's framework defaults. Ruby stays on Ubuntu 24.04's patched 3.2. Gems with published advisories are updated to fixed versions (rack, Puma 7.2.1, Nokogiri, Loofah, rails-html-sanitizer, concurrent-ruby, erb, addressable, excon, bcrypt, crass, sqlite3), and CI's `bundle-audit` check now blocks merges.
- **CI lint and security checks block merges.** RuboCop and Brakeman used to run with failures ignored. Tool versions are pinned; existing RuboCop offenses are recorded in `.rubocop_todo.yml` so only new ones fail, and the Brakeman warnings we reviewed are in `config/brakeman.ignore`, each with a note. A new job runs the model, service, helper and request specs on MariaDB, production's database. `bundle-audit` fails on gem advisories.

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
