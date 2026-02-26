# TODO — Amahi-kai

*Updated: 2026-02-26*

---

## P0 — Next Up

### Kill Tab/Subtab System
Plugins are consolidated but navigation still uses the old Tab/Subtab registration system.
Replace with simple route-based nav — hardcoded header links, no dynamic tab registry.
- Delete `app/models/tab.rb`, `app/models/subtab.rb` if they exist
- Remove `config/initializers/*_tab.rb` files (6 of them)
- Simplify header partial — direct links instead of tab iteration
- Retire `basic.html.slim` layout — everything uses `application.html.slim`

### Test Coverage Push
44% → 70%+ with quality specs. Focus on:
- New consolidated controllers (shares, settings, network have zero coverage on some actions)
- Error paths and edge cases
- File browser (no specs yet)
- Setup wizard (no specs yet)

### Tech Debt Review
Periodic review of `TECH_DEBT.md` — tackle items when touching nearby code.
Top items: Share model callbacks (extract service object), Command class consistency.

### Setup Wizard Testing
Verify enhanced wizard end-to-end on real hardware:
- Drive detection, formatting, mounting
- Greyhole install flow
- Swap file creation (new)
- Hostname change
- Share creation with pool copies

---

## P1 — Polish

### Mobile Responsive Pass
Full mobile optimization — test every page on phone screens, fix what's broken:
- Header nav → hamburger menu collapse
- Dashboard cards stacking
- Tab bar scrollable on small screens
- File browser: bigger tap targets, touch-friendly actions
- Setup wizard mobile-friendly
- Share/user forms sized for thumbs
- Theme toggle accessible on mobile

### Backup/Snapshot Scheduling
The #1 reason people buy a NAS. Scope TBD — rsync-based, scheduling, retention, restore UI.

### Storage Management Enhancements
- **Add existing drive to pool without formatting** — Mount drive with data, add to Greyhole pool as-is
- **RAID support** — mdadm RAID 1/5/6 as advanced option. v0.3+ scope.

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
- v0.1.0 public release, v0.1.1, v0.1.2 "Ocean"
- **Plugin consolidation — all 6 engines merged into main app**
- ~60 sleep calls removed, 23+ bare rescues fixed, tabs→spaces
- Plugin engine loading disabled, amahi_plugin_routes no-op
- Auth modernization: Authlogic → has_secure_password (bcrypt)
- Login rate limiting (rack-attack)
- Toast notification system (replaced flash banners)
- Native file browser (browse, upload, download, rename, delete, preview)
- Dashboard rework (shares prominent, per-drive bars, compact services)
- 🌊 Ocean UI (breathing gradient, SVG waves, particles, glassmorphism)
- Theme toggle (light/dark/system) with circle-wipe transition
- Ocean background on GitHub Pages site + wiki
- CI overhaul (5 parallel jobs, 211 specs green)
- nmbd WINS database fix in installer
- NTFS mount support + stale fstab auto-cleanup
- Samba password sync on user password changes
- Agent relay system (Kai ↔ Root Claude async comms)
- Wiki/docs at amahi-kai.com/wiki (9 pages)
