# MEMORY.md — Kai's Long-Term Memory

*Load this only in direct sessions with Troy. Last updated: 2026-02-24.*

---

## Branding

- **Logo:** Ocean wave mark (SVG at `public/favicon.svg`)
  - Teal rounded square with two wave lines (white)
  - Gradient: `#0a6e8a` → `#0d8aa8`
  - Emoji stand-in: 🌊 (NOT 🐙 — octopus was retired)
- **Use 🌊 consistently** for branding in UI, setup wizard, anywhere Amahi-kai identity appears
- Favicon served as SVG (modern browsers) with .ico fallback
- All layouts have favicon link tags: application, login, setup

## Identity

- **Name:** Kai (ocean in Hawaiian — fits Amahi-kai)
- **Role:** AI agent modernizing the Amahi-kai home server platform
- **Human:** Troy
- **VM:** amahi-kai (Ubuntu 24.04, 11GB RAM)
- **Test server:** 192.168.1.111 (NOT .102 — old notes were wrong)
- **User:** `claw` (UID 1001, sandbox-restricted)
- **Workspace:** `/workspace` → `/home/claw/Amahi-kai`
- **Repo:** `git@github.com:CatDogBark/Amahi-kai.git` (branch: main)

---

## Project: Amahi-kai

Amahi is a home server platform (NAS, media, apps). Our fork is bringing it from Rails 3/Ruby 2.4
to a modern, maintainable stack.

### Current Stack
- **Ruby:** 3.2.10
- **Rails:** 8.0.4
- **Frontend:** Bootstrap 5, Stimulus/Turbo (zero jQuery)
- **DB:** MariaDB (native install + tests)
- **Asset pipeline:** Sprockets (Propshaft migration pending)
- **Tests:** RSpec (request specs, model specs — no Selenium)
- **Deployment:** Native install only (`bin/amahi-install`). Docker stack is retired.
- **App Proxy:** Built-in reverse proxy for Docker apps at `/app/{identifier}`

### Major Milestones Completed
- Rails 5.2 → 8.0.4 (7 major upgrades)
- Ruby 2.7 → 3.2.10
- jQuery UJS → Stimulus/Turbo (full migration, all 6 plugins)
- CoffeeScript → vanilla JS
- Bootstrap 4 → 5
- Security hardening (SQL injection, shell injection, crypto, CSRF, CSP)
- Docker stack (Dockerfile + docker-compose.yml)
- Docker App System (14-app catalog, ContainerService, DockerApp model)
- **Native install working** (bin/amahi-install — idempotent, full stack)
- **All CRUD working in browser** (users, shares, DNS aliases)
- **Database-backed file indexer** (replaced locate hack)
- **System Status dashboard** (Settings subtab)
- **Carlos Puchol blessed the fork** 🎉
- 386+ specs

---

## Sandbox Constraints

- **No network** — sandbox is air-gapped
- **Can git commit** — host auto-pushes every 2 min
- **MariaDB** — run `start-mariadb` before DB work; socket at `/tmp/mysqld.sock`
- **Memory** — limited; run rspec in batches if OOM occurs
- **Testing on host** — Claude runs specs at `/opt/amahi-kai` on the native install. Sync workspace → host with rsync.

## Docker Log Files (live, in your workspace)

Troy set up real-time log streaming from the running Docker stack into your workspace:

- `tmp/logs/web.log` — Rails app (requests, errors, asset issues)
- `tmp/logs/db.log` — MariaDB (connections, query errors)

These update instantly — no polling. Check them whenever debugging UI issues or anything Docker-related. They rotate daily, 7 days kept.

---

## Recent History

### 2026-02-24 (Going Public + Greyhole fixes)
- **Repo went public!** GitHub Pages live at amahi-kai.com
- **Git history scrubbed** — MEMORY.md, HEARTBEAT.md, .claude/, .config/, .npm/, .gemrc, memory/ all removed from history via filter-branch
- **v0.1.0 tagged** (pre-release) — first public release
- **CI green ✅** — fixed stale Gemfile.lock, tagged Docker/integration specs to skip
- **Website:** static site in `site/` folder, deployed via GitHub Actions Pages workflow
- **Greyhole config bug fixed:** was writing INI sections `[share]\n\tnum_copies=1`, correct format is `num_copies[share] = 1`
- **Greyhole UI bug fixed:** `toggle_disk_pool_enabled` and `update_disk_pool_copies` weren't calling `Greyhole.configure!`
- **Samba VFS fix:** `wide links = yes` requires `samba-vfs-modules` package (not default on Ubuntu 24.04). Removed hardcoded setting from share.rb — belongs in global smb.conf only
- **Samba symlink following:** needs `wide links = yes` + `follow symlinks = yes` + `allow insecure wide links = yes` in `[global]` section + `samba-vfs-modules` installed
- **Lesson:** Branch protection blocks force push — must temporarily disable in GitHub Settings → Branches
- **Lesson:** `samba-vfs-modules` is a MUST for `bin/amahi-install` — without it, `wide links` crashes all Samba connections

### 2026-02-23 (App Proxy marathon)
- **Reverse proxy fully working** — Docker apps accessible through Cloudflare tunnel via `/app/{identifier}`
- **Proxy approach:** strip prefix before forwarding, rewrite HTML responses:
  1. Inject `<base href="/app/{id}/">` for relative asset URLs
  2. Rewrite root-absolute paths in src/href/action attributes
  3. Rewrite `window.FileBrowser.BaseURL` in JS config for API calls
- **Route fix:** `format: false` required on wildcard route — Rails was parsing .css/.js as format extensions
- **MIME fix:** `render body:, content_type:` preserves upstream MIME types through Rails
- **Docker lifecycle fixed:** all commands use `sudo docker` CLI (was mix of Docker API gem + CLI without sudo)
  - Install: sudo docker pull/create/start, cleans old containers on reinstall
  - Uninstall: sudo docker stop/rm, cleans host dirs
  - Start/Stop/Restart: sudo docker CLI
  - Sudoers rule added to installer: `amahi ALL=(root) NOPASSWD: /usr/bin/docker`
- **FileBrowser pinned to v2.28.0-amd64-s6** — `latest` has known bug where static assets 404 (Go embed issue)
- **Lesson: `curl -sI` (HEAD) returns 404 for FileBrowser assets** — only GET works. Wasted 30min on this.
- **Lesson: FileBrowser `baseURL` server config breaks static assets** on all tested versions — rewrite JS config instead

### 2026-02-19 (Triple marathon — NAS + Security + Dashboard + Tests)
- **Dashboard homepage** — full system overview (resources, services, stats, storage, apps)
- **Dark mode** — `prefers-color-scheme: dark`, CSS variable overrides, multiple rounds to fix default theme inheritance
- **Logo** — "Amahi" bright ocean blue (#1a9fc2) for light+dark visibility
- **Search page** — restyled with proper tab bar
- **Test coverage push** — 603 examples, ~6 real failures remaining (docker_apps 500s), 57% coverage
- **Docker install feature** — DockerService, streaming terminal, controller actions
- **No reverse proxy** — decided to use Cloudflare Tunnel ingress per-app instead
- **Chromedriver guard** — JS specs auto-skip when Chrome not available on host

### 2026-02-19 (Earlier — NAS + Security)
- **Greyhole storage pooling** — full integration (model, service, storage pool UI, live terminal install)
- **First-Run Setup Wizard** — 6-step web wizard + `--headless` installer mode
- **Reusable install terminal modal** — SSE streaming shared partial, used for Greyhole/Cloudflare/security
- **Cloudflare Tunnel UI** — Remote Access subtab, status/controls, token setup flow with instructions
- **Security Audit system** — 8 checks, auto-fix, streaming terminal, gates tunnel activation
- **Branding** — login polished, favicon unified (3 waves), octopus retired for good
- **Claude Code collaboration** — established reply-before-acting protocol to avoid duplicate fixes
- Sudoers hardened iteratively (learned: audit ALL sudo commands before deploying)
- Greyhole install required: DB + config before dpkg postinst, php8.3-mbstring specifically, DEBIAN_FRONTEND=noninteractive

### 2026-02-18 (Massive production day)
- **Native install LIVE** — amahi-kai.service running on host, all services active
- **Carlos Puchol replied** — blessed fork name, offered to try it. Troy replied. Branding conversation deferred.
- **Root cause JS fix** — ESM export in Stimulus/Turbo killed all JS in prod. Vendored IIFE builds.
- All CRUD working in browser (users, shares, DNS aliases)
- System Status dashboard built (subtab in Settings)
- Database-backed ShareFile indexer replaced locate-based search
- README rewritten for native-first install
- Troy's pronouns for me: she/her
- Troy wants "enterprise level NAS" quality — "button it up so solid that it makes your ears bleed"

### 2026-02-17 (Session restored after memory wipe)
- Troy restored context via BOOTSTRAP.md
- Docker stack confirmed working by Troy on host/NAS
- Latest commit: `6337fc6` — tzdata fix, RAILS_ALLOWED_HOST for tunnel access

### 2026-02-16
- Security hardening: SQL injection, shell injection, XSS
- 41 new specs (334 → 375 total)
- Docker app system built (AppCatalog, ContainerService, DockerApp)
- Dead code removed, CI fixed, docker-compose polished
- Bare rescue cleanup (17 files), terser enabled in prod

### 2026-02-15 (Epic upgrade marathon)
- 7 Rails upgrades in one session (5.2 → 8.0)
- Ruby 2.7 → 3.2
- Cloudflare Tunnel set up for remote gateway access

---

## Reusable Patterns

### Shared Install Terminal (SSE Streaming)
- **Partial:** `app/views/shared/_install_terminal.html.erb`
- **Usage:** `render 'shared/install_terminal', id: 'unique-id', title: 'Title', stream_url: some_path`
- **Trigger:** `openInstallTerminal('unique-id', url)` from a button
- **Controller side:** Set SSE headers, use `Enumerator.new` with `yielder`, send lines via `"data: #{text}\n\n"`, finish with `"event: done\ndata: success\n\n"`
- **Used by:** Greyhole install, Cloudflare tunnel, security audit, system update
- **Style:** Dark terminal modal with traffic light dots, color-coded lines (step=blue, success=green, error=red, warn=yellow)
- **Always use this** instead of inlining terminal UI — keeps everything consistent

## Agent Relay System (live, tested 2026-02-25)

Async communication between Kai (sandbox) and Root Claude (host):
- **Kai → Root Claude:** Write plaintext to `tmp/cc-outbox.md` → kai-relay picks up → Root Claude acts
- **Root Claude → Kai:** Writes to `tmp/cc-inbox.md` → Kai reads on heartbeat, acts, clears
- No special tags needed. Round-trip ~2 min end-to-end.
- Claude CLI on host: symlinked to `/usr/local/bin/claude`

---

## Key Technical Notes

### MariaDB
- Socket: `/tmp/mysqld.sock`
- No auth (skip-grant-tables)
- Run `start-mariadb` each session

### App Reverse Proxy
- **Controller:** `AppProxyController` — proxies all HTTP methods to Docker app containers
- **Routes:** `/app/:app_id` and `/app/:app_id/*path` (with `format: false`)
- **Approach:** Strip prefix, forward to `127.0.0.1:{host_port}`, rewrite HTML response
- **HTML rewriting:** `<base>` tag injection + root-absolute path rewriting + JS config rewriting
- **MIME types:** Use `render body:, content_type:` — Rails overrides everything else
- **Auth:** `admin_required` — browser must have Amahi session cookie
- **FileBrowser quirk:** HEAD requests return 404 for static assets; only GET works
- **FileBrowser quirk:** Server-side `baseURL` config breaks static assets on all versions — rewrite JS config instead

### Docker App System Architecture
- `lib/app_catalog.rb` — YAML catalog at `config/docker_apps/catalog.yml`
- `lib/container_service.rb` — Docker lifecycle (stubs in dev/test)
- `app/models/docker_app.rb` — ActiveRecord model (JSON columns for SQLite compat)
- All docker commands use `sudo docker` CLI (not Docker API gem)
- Sudoers: `amahi ALL=(root) NOPASSWD: /usr/bin/docker`
- Routes: hardcoded paths (engine route helpers unreliable in views)

### Test Running
- Full suite can OOM — run in batches: `rspec spec/models`, `rspec spec/requests`, etc.
- Feature specs need Chromium: ensure sandbox is fresh if hangs occur

### Greyhole / Samba Storage Pooling
- Greyhole config: `/etc/greyhole.conf` — flat format: `num_copies[sharename] = N`
- Storage pool drives configured in greyhole.conf: `storage_pool_drive = /mnt/storage-X, min_free: 10gb`
- `samba-vfs-modules` package REQUIRED — without it `wide links = yes` causes `widelinks.so: cannot open shared object file`
- Global smb.conf needs: `wide links = yes`, `follow symlinks = yes`, `allow insecure wide links = yes`, `unix extensions = no`
- Don't put `wide links` in per-share config (share.rb template) — only in `[global]`
- Greyhole creates symlinks in share paths pointing to actual files on storage pool drives

### Website (GitHub Pages)
- Static site in `site/` folder, deployed via `.github/workflows/pages.yml`
- Domain: amahi-kai.com (Namecheap DNS → GitHub Pages)
- CNAME file in `site/CNAME`

### Known Blocked Items
- Propshaft migration blocked by Bootstrap gem's Sprockets dependency
- `config.force_ssl` disabled — needs HTTPS guidance from Troy

---

## Next Priorities (from TODO.md)

1. Test coverage: 44% → 70%+ (quality specs, not quantity)
2. Sprockets → Propshaft (unblock research)
3. Firewall plugin (new feature, large scope)

**SSL — DONE** (2026-02-25): `assume_ssl` REVERTED — broke LAN HTTP. Cloudflare handles HTTPS at the edge, LAN stays plain HTTP.
**Auth — DONE** (2026-02-25): Authlogic + SCrypt → `has_secure_password` (bcrypt). Plain Ruby UserSession class using `session[:user_id]`.

### Native File Browser (2026-02-26)
- `FileBrowserController` — browse, upload, download, rename, delete, new folder, preview, raw
- Path traversal security: realpath validation under share root
- Stimulus controller: drag-and-drop, multi-select, bulk delete, preview modal (image/video/audio/PDF)
- `Share#to_param` returns name for clean URLs (`/files/Storage/browse`)
- Share cards on dashboard link directly to file browser
- FileBrowser Docker app removed from catalog — native replaces it
- **Built in one pass, everything worked first try**

### Toast Notifications (2026-02-26)
- Replaced all flash banners with fixed-position toasts (top-right, no layout shift)
- `showToast(msg, type)` global JS function — used by all controllers
- Server flash rendered as JSON, picked up on DOMContentLoaded
- Setup wizard has inline toast JS (separate layout, no application.js)

### Theme Toggle (2026-02-26)
- 3-state: ☀️ light / 🌙 dark / 💻 system — centered in header
- Connected circles with sliding teal pill indicator
- `[data-theme]` on `<html>`, localStorage persistence, applied before CSS loads
- CSS variables for both themes in `style.css`, 0.4s transition on toggle

### Dashboard Rework (2026-02-26)
- Per-drive storage bars (all mounted drives via `DashboardStats#drive_usage`)
- CPU + Memory + drives in "System" card, Services as sidebar
- Share cards with Browse buttons at top
- Quick action buttons replace oversized count cards
- Killed redundant Storage Overview section

### CI Overhaul (2026-02-26)
- Split into 5 parallel jobs: Models, Requests, Lib, Features → Lint & Security
- RuboCop (Lint cops only) + Brakeman (security scan) as warnings
- Tabs → spaces across 33 legacy files, bare rescues fixed

### Setup Wizard (enhanced 2026-02-25)
- 7 steps: Welcome → Admin → Network → Storage → Greyhole → Share → Complete
- DiskManager detects drives via lsblk (formatted, unmounted, unformatted)
- Supported fs (ext2/3/4, xfs, btrfs) → Greyhole pool
- Unsupported fs (ntfs, fat) → mount as standalone share, auto-create network share
- Drive preview: temp-mount read-only, show file listing in modal
- Greyhole install optional, default 2 copies with 2+ drives
- `hostnamectl` needs to be in both Command.privileged_prefixes AND sudoers

### Samba/nmbd Post-Greyhole Fix
- Greyhole dpkg postinst overwrites smb.conf — drops wide links settings → nmbd segfaults
- `Greyhole.install!` now calls `reinject_samba_globals!` after install
- Required settings: `wide links = yes`, `follow symlinks = yes`, `allow insecure wide links = yes`, `unix extensions = no`

### Proxmox Passthrough
- `qm set 104 -scsi1 /dev/disk/by-id/<id>` for raw disk
- Breaks snapshots — remove before rollback, re-add after
- For wizard testing: `Setting.set('setup_completed', 'false')` in Rails console instead of reinstalling

**App catalog — DONE** (pre-memory-wipe): All 14 Docker apps tested. Apps that work through reverse proxy are working. Apps needing subdomains or multi-container builds show a notification after install explaining the limitation.
