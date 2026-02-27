# TODO — Amahi-kai

*Updated: 2026-02-27*

---

## P0 — Next Up

### Refactor: StreamingConcern
Extract SSE streaming boilerplate from 5 controllers (10 endpoints) into a shared concern. ~300 lines of duplication.
**Status: IN PROGRESS**

### Refactor: Split NetworkController (660 lines)
Break into focused controllers:
- `NetworkController` — DHCP leases, hosts
- `SecurityController` — security audit, auto-fix
- `RemoteAccessController` — Cloudflare tunnel
- Keep gateway/DNS/settings as subtabs in NetworkController

### Refactor: Bare Rescue Cleanup
29 in app/, 11 in lib/. Narrow to specific exception classes.

### Refactor: Controller → Service Objects
Extract Shell.run calls from controllers into service objects. Priority:
- `DisksController` → `DiskService` (format, mount, unmount)
- `AppsController` → `DockerEngineService` (install, start, stop)
- `SetupController` → `SetupService` (wizard step logic)

### Test Coverage Push
44% → 70%+ with quality specs. Focus on:
- Consolidated controllers (shares, settings, network have gaps)
- Error paths and edge cases
- File browser (no specs yet)
- Setup wizard (no specs yet)

### Setup Wizard Testing
Verify enhanced wizard end-to-end on real hardware:
- Drive detection, formatting, mounting
- Greyhole install flow
- Swap file creation
- Hostname change
- Share creation with pool copies

---

## P1 — Polish

### Mobile Responsive Pass
Full mobile optimization — test every page on phone screens:
- Header nav → hamburger menu collapse
- Dashboard cards stacking
- Tab bar scrollable on small screens
- File browser: bigger tap targets, touch-friendly actions
- Setup wizard mobile-friendly

### Backup/Snapshot Scheduling
The #1 reason people buy a NAS. Scope TBD — rsync-based, scheduling, retention, restore UI.

### Storage Management Enhancements
- Add existing drive to pool without formatting
- RAID support (mdadm RAID 1/5/6) — v0.3+ scope

### Cloudflare Tunnel App Integration
Build UI for connecting apps that need their own subdomain.

### Docker App System — Production Ready
- Share integration — app volumes auto-map to Amahi share paths
- Container logs/stats UI
- More apps in catalog

---

## P2 — Future

### Multi-Container App Support (Docker Compose)
Apps like Immich, Paperless-ngx need 2-3 containers. Per-app docker-compose.yml.

### Network Management Plugin (OpenWrt Container)
Run OpenWrt in Docker for full router/firewall/DHCP/DNS. v0.3+ feature.

### Web Terminal
Browser-based shell (xterm.js + WebSocket). Admin-only.

### Propshaft Migration
Replace Sprockets with Propshaft. Blocked by Bootstrap gem's Sprockets dependency.

### Reticulum Out-of-Band Management
Optional mesh networking for encrypted push alerts and remote management over LoRa.

---

## Done ✅

- Rails 3 → 8.0.4, Ruby 2.4 → 3.2.10
- jQuery → Stimulus/Turbo (zero jQuery), CoffeeScript → vanilla JS
- Bootstrap 4 → 5, dark mode
- Docker App System (14-app catalog, reverse proxy, all tested)
- Native installer + one-liner (`curl -fsSL https://amahi-kai.com/install.sh | sudo bash`)
- File sharing with Greyhole storage pooling
- Cloudflare Tunnel integration
- Security audit with auto-fix (8 checks)
- Setup wizard (7-step + swap detection + drive preview)
- System dashboard, search, themes
- v0.1.0 public release, v0.1.1, v0.1.2 "Ocean", v0.1.3 "Consolidation"
- Plugin consolidation — all 6 engines merged into main app
- Auth modernization: Authlogic → has_secure_password (bcrypt)
- Login rate limiting (rack-attack)
- Toast notification system (replaced flash banners)
- Native file browser (browse, upload, download, rename, delete, preview)
- Dashboard rework (shares prominent, per-drive bars, compact services)
- 🌊 Ocean UI (breathing gradient, SVG waves, particles, glassmorphism)
- Theme toggle (light/dark/system) with circle-wipe transition
- **Theme system overhaul** — single amahi-kai theme, var-only dark mode, deleted Classic theme (-4,093 lines)
- **Lucide icon pack** — 34 vendored SVGs, IconHelper, replaced all emoji icons
- **CSS cache busting** — theme CSS URLs include ?v=mtime
- **Docker service toggle** — slide switch with optimistic UI, no page reload
- **Disk detection** — JSON lsblk parsing, VM/passthrough support, size column
- CI overhaul (5 parallel jobs, 211 specs green)
- Agent relay system (Kai ↔ Root Claude async comms)
- Wiki/docs at amahi-kai.com/wiki (9 pages)
