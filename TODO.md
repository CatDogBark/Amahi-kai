# TODO — Amahi-kai Production Features

*Updated: 2025-07-09. Infrastructure/upgrade work is done. Focus is on making features work on a real Ubuntu 24.04 host.*

---

## P0 — Core Functionality

### UI Modernization
Bootstrap 4→5, Propshaft migration (blocked by Bootstrap gem's Sprockets dep — research alternatives), Hotwire/Turbo integration. Gems already in sandbox.

### Samba Integration Smoke Test
Create a share via UI → verify smb.conf is written → verify smbd restarts. End-to-end on a real host.

### User Management Smoke Test
Create a user via UI → verify useradd runs → verify pdbedit adds Samba credentials. Test edge cases (duplicate user, bad input).

### dnsmasq Integration
DNS alias creation via UI writes to `/etc/dnsmasq.d/`, service reloads. Verify resolution works.

---

## P1 — Install & Access

### Cloudflare Tunnel Installer Integration
Optional step in `bin/amahi-install`: prompt for tunnel token, install cloudflared, open UFW 7844/tcp+udp. Skip if declined.

### First-Run Setup Wizard
Guide new installs through: change admin password, set hostname, configure first share. Should be the landing page on first boot.

---

## P2 — Quality & Security

### Test Coverage (34% → 70%+)
Focus on models and controllers that touch system commands (shares, users, DNS). Add integration tests for the sudo-based workflows.

### Auth Modernization
Evaluate replacing Authlogic with Devise or Rails 8 native authentication. Authlogic works but is maintenance baggage.

---

## P3 — Future

### Apps/Plugins System
Evaluate which legacy plugins still make sense (disks, app store). Docker app catalog exists but needs UI polish and more apps.

### Disk/Storage Management
The disks plugin needs updating for modern Linux. Detect drives, format, mount, present in UI.
