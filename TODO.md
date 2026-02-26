# TODO — Amahi-kai

*Updated: 2026-02-26*

---

## P0 — Next Up

### Native File Browser
Browse, upload, download, rename, delete files directly in the web UI — no Samba/Windows needed.
- Integrates with existing shares model
- Per-share browsing with breadcrumb navigation
- Drag-and-drop upload, multi-file download (zip)
- Rename, delete, new folder
- File preview (images, text, video)
- Replaces FileBrowser Docker app (remove from catalog)

### Test Coverage Push
44% → 70%+ with quality specs. Focus on edge cases, error paths, real business logic.

### Setup Wizard Testing
Verify enhanced wizard end-to-end on real hardware:
- Drive detection, formatting, mounting
- Greyhole install flow
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
- Upload via phone camera shortcut
- Theme toggle accessible on mobile

### Backup/Snapshot Scheduling
The #1 reason people buy a NAS. Scope TBD — rsync-based, scheduling, retention, restore UI.

### Storage Management Enhancements
- **Add existing drive to pool without formatting** — Mount drive with data, add to Greyhole pool as-is. Greyhole uses free space around existing files. Great for migration from bare drives.
- **RAID support** — mdadm RAID 1/5/6 as advanced option in setup wizard and disk settings. Needs monitoring UI for rebuild status. v0.3+ scope.

### Cloudflare Tunnel App Integration
Build UI for connecting apps that need their own subdomain:
1. User installs app → catalog shows "Local access only"
2. User clicks "Configure Remote Access" → enters subdomain
3. System adds ingress rule → restarts tunnel
4. Open button uses subdomain URL

### Docker App System — Production Ready
- Share integration — app volumes auto-map to Amahi share paths
- Container logs/stats UI
- More apps in catalog (remove FileBrowser — native file browser replaces it)

---

## P2 — Future

### Multi-Container App Support (Docker Compose)
Apps like Immich, Paperless-ngx need 2-3 containers. Per-app docker-compose.yml.

### Network Management Plugin (OpenWrt Container)
Run OpenWrt in Docker for full router/firewall/DHCP/DNS. Troy's NAS has 4 NICs.
Big differentiator — one box replaces router + NAS. v0.3+ feature.

### Web Terminal
Browser-based shell (xterm.js + WebSocket). Admin-only.

### Propshaft Migration
Replace Sprockets with Propshaft. Blocked by Bootstrap gem's Sprockets dependency.
Not urgent — Sprockets works fine and isn't deprecated.

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
- Setup wizard (7-step: welcome, admin, network, storage, greyhole, share, complete)
- System dashboard, search, themes
- v0.1.0 public release, v0.1.1 cleanup & hardening
- Legacy app system removed (~1,650 lines), Docker dev stack removed
- Agent relay system (Kai ↔ Root Claude async comms)
- Wiki/docs at amahi-kai.com/wiki (9 pages)
- Test coverage 19% → 44% (clean, meaningful specs)
- Auth modernization: Authlogic → has_secure_password (bcrypt)
- SSL: assume_ssl for Cloudflare Tunnel (disabled — breaks LAN HTTP)
- Drive preview in disk settings + setup wizard
- "Open Direct" button for local-only Docker apps
- Login rate limiting (rack-attack: throttle + auto-ban)
- Toast notification system (replaced layout-shifting flash banners)
- NTFS mount support + stale fstab auto-cleanup
- Samba password sync on user password changes
