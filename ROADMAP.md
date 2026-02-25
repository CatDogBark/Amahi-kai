# Roadmap — Amahi-kai

*Updated: 2026-02-24*

---

## ✅ Completed

- Rails 3 → 8.0.4 (7 major upgrades)
- Ruby 2.4 → 3.2.10
- jQuery → Stimulus + Turbo (zero jQuery)
- CoffeeScript → vanilla JS
- Bootstrap 4 → 5.3
- Docker App System (14-app catalog, one-click install, reverse proxy)
- Native installer (`curl -fsSL https://amahi-kai.com/install.sh | sudo bash`)
- File sharing with Greyhole storage pooling
- Cloudflare Tunnel integration (remote access)
- System dashboard (CPU, memory, disk, network, services)
- Security audit with auto-fix
- Setup wizard (6-step guided + headless mode)
- Dark mode (automatic)
- One-click updates from browser

---

## 🔨 In Progress

### App Catalog Testing
Verify all 14 catalog apps install and function through the reverse proxy.

### Test Coverage
Expanding toward 70%+. Focus on edge cases, error paths, and integration tests.

---

## 🗓 Planned

### Cloudflare Subdomain Integration
Automatic subdomain setup for apps that need their own domain (Nextcloud, Home Assistant, etc.)

### SSL / HTTPS Production Config
Enforce HTTPS-only in production.

### Docker Compose Apps
Multi-container app support for complex apps like Immich and Paperless-ngx.

### Auth Modernization
Evaluate Devise or Rails 8 native auth as replacement for Authlogic.

### Disk & Storage Management
Detect, format, and mount drives from the UI. RAID support.

### Web Terminal
Browser-based shell (xterm.js + WebSocket). Admin-only.

### Firewall Plugin
UFW management through the web UI.

### Network Management (OpenWrt)
Optional OpenWrt container for full router/firewall/DHCP/DNS — turn your NAS into a router too.

### Propshaft Migration
Replace Sprockets with Propshaft for the asset pipeline.

---

## 🔮 Long-Term

### Reticulum Out-of-Band Management
Optional mesh networking layer using [Reticulum](https://reticulum.network/) for encrypted push alerts and remote management over LoRa — works without internet.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.
Have an idea? [Open an issue](https://github.com/CatDogBark/Amahi-kai/issues).
