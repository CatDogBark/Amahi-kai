# v0.2.0 — Remote Access & Polish

142 commits since v0.1.2. Plugin consolidation, role-based access control, native file browser, remote access (Tailscale + Cloudflare), dark mode overhaul, and a mountain of fixes.

## 🌟 Major Features

### Plugin Consolidation
- All 6 legacy plugin engines (Users, Network, Shares, Disks, Apps, Settings) merged into the main app
- Deleted ~1300 lines of dead code (plugin infrastructure, sample data, tab system, Command class)
- Replaced Command class with unified Shell module (113 call sites migrated)
- Extracted Share model callbacks into service objects (ShareFileSystem, SambaService, ShareAccessManager)

### Role-Based Access Control
- Admin/user/guest roles replace binary admin flag
- Per-share access and write permissions
- File browser filtered to accessible shares only
- Dashboard hides admin-only links for non-admin users
- Search filtered to accessible shares

### Native File Browser
- Browse, upload, download, rename, delete, new folder, preview
- Drag-and-drop, multi-select, bulk delete
- Image/video/audio/PDF preview modal
- Path traversal security (realpath validation)
- Replaced Docker FileBrowser app

### Remote Access
- **Tailscale VPN** — install, authenticate, connect/disconnect from web UI
- **Cloudflare Tunnel** — install, configure with token, start/stop from web UI
- Both services shown in dashboard services list
- Security audit gates remote access activation

### Theme & UI Overhaul
- Dark mode CSS variable system (no element-level overrides)
- Ocean ambient toggle (inline with theme switcher)
- Glassmorphism setup wizard
- Toast notifications (fixed-position, no layout shift)
- All legacy icons replaced with Lucide SVGs (zero glyphicons/bootstrap-icons)
- Consistent Connect/Disconnect buttons across remote access

## 🏗 Architecture

- Plugin engines fully removed — monolithic Rails app
- Shell.run() with auto-sudo, dummy mode, logging
- SseStreaming concern for all streaming endpoints
- 3 focused controllers split from monolithic NetworkController
- Service objects handle share lifecycle
- AMAHI_DATA_DIR / AMAHI_TMP_DIR constants for all paths
- CI: 5 parallel jobs (Models, Requests, Lib, Features, Lint & Security)

## 🔐 Security

- Password security: removed DES crypt() (was truncating to 8 chars!), bcrypt for web + pdbedit for Samba
- Password maxlength 12 → 128
- Removed OpenDNS/OpenNIC, default to Cloudflare DNS
- UFW firewall rules added before enabling (prevents lockout)
- Sudoers hardened with least-privilege allowlist
- SQL injection, shell injection, XSS fixes carried forward

## 🐛 Fixes

- Tailscale: 6 iterations to fix install + connect (sudo, timeout, blocking)
- Cloudflare: signing key install, status detection without sudo
- Greyhole: install streaming, pgrep-based status check, config format fix
- Disk detection: lsblk JSON parsing for VMs
- Docker: `docker info` for running detection, service toggle
- Setup wizard: streaming drive prep, Greyhole install, swap detection
- Fixed nmbd segfault (stale wins.tdb), git dubious ownership
- 14 missing i18n translations fixed
- Share ordering: `by_name` scope replaces `default_scope`

## 📊 Stats

- **142 commits** since v0.1.2
- **386+ specs**, CI green
- **Ruby 3.2.10**, **Rails 8.0.4**
- **Zero jQuery**, full Stimulus/Turbo

## Upgrade

```bash
cd /opt/amahi-kai && sudo -u amahi git pull && sudo bin/amahi-install
```

Or update from the web UI Settings → System → Check for Updates.
