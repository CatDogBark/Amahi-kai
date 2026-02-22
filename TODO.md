# TODO — Amahi-kai

*Updated: 2026-02-22*

---

## Done ✅

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
- ~~Search results fix~~ ✅
- ~~Greyhole integration~~ ✅ (service, storage pool UI, live terminal install)
- ~~First-Run Setup Wizard~~ ✅ (6-step wizard + `--headless` mode)
- ~~Reusable install terminal modal~~ ✅ (shared partial for SSE streaming)
- ~~Cloudflare Tunnel integration~~ ✅ (Remote Access subtab, token setup, streaming install)
- ~~Security Audit system~~ ✅ (8 checks, auto-fix, streaming terminal, gates tunnel)
- ~~Dashboard homepage~~ ✅ (system overview, resources, services, stats, storage, apps)
- ~~Dark mode~~ ✅ (`prefers-color-scheme: dark`, CSS variable overrides)
- ~~Themes page redesign~~ ✅ (card gallery with previews, active badge)
- ~~UI polish pass~~ ✅ (settings spacing, network spacing, shares spacing, tabs fix)
- ~~`bin/amahi-update`~~ ✅ (pull, bundle, migrate, restart, cache clear)
- ~~Carlos Puchol blessed the fork~~ 🎉

---

## In Progress 🔨

### Advanced Settings Rework
- Remove Guest Dashboard (dead feature)
- Rework simple/advanced mode split: simple = safe daily ops, advanced = system config
- Hide Network tab entirely in simple mode
- Mark Docker Apps, Servers, Themes, System Status, Share Settings as advanced
- Add 🔧 toggle to header bar for quick switching

---

## P0 — Next Up

### Test Coverage (57% → 70%+)
Edge cases, error paths, integration tests for sudo-based workflows.
~603 specs, ~6 real failures remaining (docker_apps 500s in test).

### Cloudflare Tunnel on .111 box
Tunnel not routing to Puma — needs config fix on host. Troy will handle.

### Samba Integration Smoke Test
Create share via UI → verify smb.conf → verify smbd restarts.

### User Management Smoke Test
Create user via UI → verify useradd → verify pdbedit.

### dnsmasq Integration Verification
DNS alias → `/etc/dnsmasq.d/` → service reload → resolution works.

---

## P1 — Polish

### SSL / Production HTTPS
Cloudflare handles edge TLS. Enforce HTTPS-only in app config (`force_ssl`).

### Login Rate Limiting
Add `rack-attack` to throttle login attempts. Quick security win.

### Docker App System — Production Ready
Model/catalog/UI exist but need:
1. Reverse proxy for app traffic through Cloudflare Tunnel (per-app ingress rules instead)
2. Share integration — app volumes auto-map to Amahi share paths
3. Streaming install terminal for pulling/creating containers
4. Container logs/stats UI
5. More apps in catalog

---

## P2 — Future

### Auth Modernization
Evaluate replacing Authlogic with Devise or Rails 8 native auth.

### Disk/Storage Management
Detect drives, format, mount, present in UI. mdadm RAID as advanced option.

### Web Terminal
Browser-based shell (xterm.js + WebSocket). Admin-only.

### Firewall Plugin
UFW management through the web UI.

### Propshaft Migration
Blocked by Bootstrap gem's Sprockets dependency. Low priority.
