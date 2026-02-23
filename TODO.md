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

### ~~Advanced Settings Rework~~ ✅
### ~~Docker Apps 500 fix~~ ✅ (Slim/ERB partial conflict)

---

## P0 — Next Up

### ~~Fix Apps "Open" Button~~ ✅
Reverse proxy working — FileBrowser, Nextcloud, Jellyfin confirmed.

### 🔥 Test All Catalog Apps Through Proxy
Verify each app in the catalog installs, opens, and functions through the reverse proxy.

**Proxy-compatible (proxy_mode: proxy):** FileBrowser ✅, Jellyfin ✅, Pi-hole, Gitea, Syncthing, Uptime Kuma, Transmission, Grafana, Audiobookshelf
**Needs Cloudflare subdomain (proxy_mode: subdomain):** Nextcloud, Portainer, Home Assistant, Vaultwarden, Paperless-ngx, Immich

**Known issues:**
- **Pi-hole** — needs DNS configuration UX. Port 53 removed from catalog to prevent hijacking host DNS. Need a setup flow that lets users opt-in to DNS takeover with proper warnings.
- **Home Assistant** — trusted_proxies config added but SPA uses absolute JS paths. Requires subdomain.

### 🔥 Cloudflare Tunnel App Integration
Build the UI flow for connecting apps that need their own subdomain:
1. User installs app → catalog shows it needs a Cloudflare subdomain
2. User clicks "Configure Remote Access" → enters subdomain (e.g., `ha.mydomain.com`)
3. System adds ingress rule to Cloudflare Tunnel config → restarts tunnel
4. Open button uses the subdomain URL instead of `/app/{identifier}`

**Dependencies:** Cloudflare Tunnel must be configured first (existing Remote Access setup flow).
**Catalog field:** `proxy_mode: subdomain` flags apps that need this.
**Also needed:** UI indicator on app cards showing proxy vs subdomain status.

### Test Coverage (57% → 70%+)
Edge cases, error paths, integration tests for sudo-based workflows.
~603 specs, ~6 real failures remaining (docker_apps 500s in test).

### Greyhole Testing
Real drives, real files. Verify storage pooling, file duplication, and share integration end-to-end.

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

### Multi-Container App Support (Docker Compose)
Apps like Immich, Paperless-ngx (with Redis), and others need 2-3 containers. Build support for:
- Per-app `docker-compose.yml` (generated from catalog or stored in config)
- `docker compose -p amahi-{id} up/down` for lifecycle instead of individual container commands
- Proxy only needs main service port — companion containers are internal
- Single-container apps still work (compose with one service = same thing)
- Re-enable Immich once this lands

### Propshaft Migration
Blocked by Bootstrap gem's Sprockets dependency. Low priority.

---

## Phase 2 — Long-Term Vision

### 🔮 Reticulum Out-of-Band Management Layer
Optional low-bandwidth management and notification channel for the NAS using [Reticulum](https://reticulum.network/). **Control plane only** — not for file serving or media (bandwidth too low).

**Use cases:**
- Encrypted push alerts (backup failures, disk health warnings, service status) delivered over LoRa or other Reticulum transports when user has no internet or cell service
- Remote command/control for basic service management (restart a container, trigger a backup, check system status) over Reticulum from a mobile device running Sideband
- Resilient local communication independent of Wi-Fi/internet infrastructure

**Hardware:** USB LoRa radio (RNode) attached to the NAS. Reticulum is Python — N100 handles it fine. Constraint is purely transport bandwidth, which is why this stays management-only.

**Why it matters:** No other consumer NAS platform has a decentralized mesh fallback channel. Aligns with self-sovereign infrastructure philosophy. Especially relevant for rural/off-grid deployments (Big Island, remote sites, disaster scenarios).

**Priority:** After public release stabilization. Document and revisit.
