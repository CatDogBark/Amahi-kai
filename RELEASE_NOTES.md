# v0.1.2 — Ocean 🌊

*Released: 2026-02-26*

The UI comes alive. Native file browsing, ocean-themed animations, modern auth, and a polished dashboard. 84 commits since v0.1.1.

---

## ✨ New Features

### Native File Browser
Browse, upload, download, rename, and delete files directly in the web UI — no Samba/Windows explorer needed.
- Per-share browsing with breadcrumb navigation
- Drag-and-drop upload with progress
- Multi-select and bulk delete
- File preview (images, video, audio, PDF)
- Rename, new folder, download
- Replaces the FileBrowser Docker app

### 🌊 Ocean UI
A living, breathing interface inspired by the ocean:
- **Breathing gradient** — background slowly shifts between deep navy and dark teal
- **SVG waves** — three layered wave shapes gently bob along the top
- **Floating particles** — tiny glowing dots rise from the bottom like bubbles
- **Ripple theme transition** — switching themes radiates outward from your click point using the View Transition API, with trailing water ripple rings
- **Glassmorphism cards** — translucent with backdrop blur so the ocean shows through

### Theme Toggle
Three-state theme switcher in the header: ☀️ Light / 🌙 Dark / 💻 System
- Sliding pill indicator
- Persists via localStorage across all pages
- Instant application with no flash of wrong theme (FOUC prevention)
- Respects `prefers-reduced-motion` — animations disabled for accessibility

### Toast Notifications
Fixed-position toast notifications replace the old flash banners:
- Top-right, no layout shift
- Auto-dismiss after 5 seconds, pause on hover
- Color-coded by type (success, error, warning, info)
- Works across all layouts including the setup wizard

### Enhanced Setup Wizard
- Drive detection: formatted, unformatted, and unsupported filesystems
- Drive preview: temp-mount and browse contents before committing
- NTFS/FAT drives auto-mount as standalone shares
- Format option for drives with existing filesystems
- Greyhole install with configurable copy count
- Hostname change via `hostnamectl`

---

## 🔧 Improvements

### Auth Modernization
- **Authlogic + SCrypt → `has_secure_password` (bcrypt)** — Rails built-in auth, no external dependencies
- Plain Ruby `UserSession` class using `session[:user_id]`
- Login rate limiting via rack-attack (throttle + auto-ban)

### Dashboard Rework
- Shares at the top (it's a NAS — shares are the point)
- Per-drive storage bars for all mounted drives
- Compact services sidebar
- Quick-action buttons replace oversized count cards

### CI Overhaul
- Split into 5 parallel jobs: Models, Requests, Lib, Features → Lint & Security
- RuboCop (lint cops) + Brakeman (security scan) as warnings
- Tabs → spaces across 33 legacy files
- 211 specs passing ✅

### Samba & Storage
- Samba password sync on user password changes
- NTFS mount support (`ntfs-3g` in installer)
- Stale fstab auto-cleanup for removed drives
- `mount -a` after updates to restore FUSE mounts
- Swap file auto-creation on systems < 8GB RAM
- Greyhole: fixed config format, re-inject Samba globals after install

### Model & Controller Fixes
- `Share#to_param` returns name for clean URLs (`/files/Storage/browse`)
- Plugin `SharesController` updated for name-based lookups
- `push_shares` moved to `after_commit` — Samba config failures can't roll back saves
- Share controller: JSON responses for all toggle actions

---

## 🐛 Bug Fixes

- Scrollbar layout shift between pages (forced `overflow-y: scroll`)
- Dashboard width misalignment with settings pages
- Theme indicator sliding on page load (now snaps to position)
- NTFS drives failing to mount silently (now captures stderr)
- Setup wizard hostname change failing (added to sudo allowlist)
- `assume_ssl` breaking LAN HTTP access (disabled)
- Disk action buttons missing spinner feedback
- Shares location column staggering
- Flash banners causing layout shift on every page

---

## 📊 Stats

- **84 commits** since v0.1.1
- **211 specs** passing (37% line coverage)
- **14 Stimulus controllers** (zero jQuery)
- **0 external JS dependencies** for the UI

---

*Next up: Legacy plugin consolidation — merging all 6 plugin engines into the main app.*
