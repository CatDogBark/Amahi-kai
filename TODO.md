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
- ~~Ocean theme / branding~~ ✅ (wave mark favicon, login, dashboard)
- ~~Search results fix (blank search shows recent files)~~ ✅
- ~~Greyhole integration~~ ✅ (service, storage pool UI, live terminal install)
- ~~First-Run Setup Wizard~~ ✅ (6-step wizard + `--headless` mode)
- ~~Reusable install terminal modal~~ ✅ (shared partial for SSE streaming installs)

---

## In Progress 🔨

### Cloudflare Tunnel Integration
- CloudflareService (install, configure, start/stop, status)
- Remote Access subtab in Network plugin
- Token input UI with setup instructions
- Streaming install via shared terminal modal

### Security Hardening / Audit System
- SecurityAudit class — 8 checks (admin password, UFW, SSH, fail2ban, unattended upgrades, Samba binding, open ports)
- Security subtab in Network plugin
- Auto-run audit when tunnel first enabled + manual "Run Audit" button
- Auto-fix with "Fix All" button (streaming terminal)
- Blockers gate tunnel activation (must fix before enabling remote access)

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

### SSL / Production HTTPS
Cloudflare handles edge TLS, but enforce HTTPS-only in app config.

### Docker App System — Production Ready
The model/catalog/UI exist but need deployment work to be usable:
1. **Docker installation** — optional step (like Greyhole), with streaming terminal install
2. **Reverse proxy** — route app traffic through port 3000 so Docker apps work through Cloudflare Tunnel (e.g., `/nextcloud` → container:8443). Likely nginx or Caddy as a lightweight proxy in front of Puma.
3. **Share integration** — app volumes should auto-map to Amahi share paths (`/var/hda/files/...`)
4. **Streaming install terminal** — reuse shared partial for pulling/creating containers
5. **Container logs/stats** — view logs, resource usage per app
6. **More apps** — expand catalog, user docs

---

## P2 — Future

### Auth Modernization
Evaluate replacing Authlogic with Devise or Rails 8 native auth.

### Disk/Storage Management
Detect drives, format, mount, present in UI. mdadm RAID as advanced option.

### Firewall Plugin
UFW management through the web UI.

### Propshaft Migration
Blocked by Bootstrap gem's Sprockets dependency. Low priority — Sprockets works fine.
