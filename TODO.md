# TODO — Amahi-kai

*Updated: 2026-02-19*

---

## Done ✅ (removed from active list)

- ~~Bootstrap 4→5~~ ✅
- ~~Hotwire/Turbo/Stimulus integration~~ ✅ (jQuery fully removed)
- ~~CoffeeScript → vanilla JS~~ ✅
- ~~Rails 5.2 → 8.0.4~~ ✅
- ~~Ruby 2.7 → 3.2.10~~ ✅
- ~~Docker stack (Dockerfile + docker-compose)~~ ✅
- ~~Docker App System (14-app catalog)~~ ✅
- ~~Native install (`bin/amahi-install`)~~ ✅
- ~~All CRUD working in browser (users, shares, DNS aliases)~~ ✅
- ~~Database-backed file indexer~~ ✅ (replaced locate hack)
- ~~System Status dashboard~~ ✅
- ~~Security hardening (SQL injection, shell injection, crypto, CSRF, CSP)~~ ✅
- ~~Ocean theme / branding~~ ✅
- ~~Search results fix (blank search shows recent files)~~ ✅

---

## P0 — Next Up

### Test Coverage (54% → 70%+)
Edge cases, error paths, integration tests for sudo-based workflows (shares, users, DNS).

### Samba Integration Smoke Test
Create share via UI → verify smb.conf written → verify smbd restarts. End-to-end on real host.

### User Management Smoke Test
Create user via UI → verify useradd → verify pdbedit. Test edge cases (duplicate user, bad input).

### dnsmasq Integration Verification
DNS alias creation via UI writes to `/etc/dnsmasq.d/`, service reloads, resolution works.

---

## P1 — Polish

### Propshaft Migration
Blocked by Bootstrap gem's Sprockets dependency. Research alternatives.

### First-Run Setup Wizard
Guide new installs: change admin password, set hostname, configure first share. Landing page on first boot.

### SSL / Production HTTPS
Needs guidance from Troy on cert strategy (Let's Encrypt, Cloudflare, etc.).

### Cloudflare Tunnel Installer Integration
Optional step in `bin/amahi-install`: prompt for tunnel token, install cloudflared, open UFW ports.

---

## P2 — Future

### Auth Modernization
Evaluate replacing Authlogic with Devise or Rails 8 native auth.

### Docker App System Polish
More apps, logs/stats UI, user docs.

### Disk/Storage Management
Update disks plugin for modern Linux. Detect drives, format, mount, present in UI.

### Firewall Plugin
New feature, large scope.
