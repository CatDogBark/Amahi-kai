# v0.1.3 — Consolidation

All six legacy plugin engines merged into the main app. Legacy code purged. New service architecture.

## Highlights

- Consolidated all 6 plugin engines (Users, Network, Shares, Disks, Apps, Settings) into the main app
- Replaced Command class with unified Shell module (113 call sites migrated)
- Extracted Share model callbacks into 3 service objects (ShareFileSystem, SambaService, ShareAccessManager)
- Migrated all paths from /var/hda/ to /var/lib/amahi-kai/
- Renamed AmahiHDA module to AmahiKai throughout
- Removed all legacy Amahi references (hda-ctl, hda-platform, hda-usermap)
- Deleted ~1300 lines of dead code (plugin infrastructure, sample data, tab system, Command class)

## New Features

- Dashboard app quick-launch grid (running Docker apps as icon grid)
- Ocean ambient toggle button (inline with theme switcher)
- Setup wizard swap detection and creation
- Setup wizard glassmorphism styling

## Fixes

- Fixed git dubious ownership error in install.sh for updates
- Fixed nmbd segfault on fresh install (stale wins.tdb cleanup)
- Fixed theme toggle pill animation on page navigation
- Boosted dark mode wave opacity for better visibility
- Removed trailing ripple rings from theme transition

## Security

- Removed OpenDNS and OpenNIC as DNS providers (defaulting to Cloudflare)
- Removed hardcoded DNS server IPs (208.67.x, 173.230.x)

## Architecture

- Plugin engines fully removed — monolithic Rails app
- Shell.run() with auto-sudo, dummy mode, logging replaces Command class
- Service objects handle share lifecycle (filesystem, samba config, access control)
- AMAHI_DATA_DIR / AMAHI_TMP_DIR constants for all data paths
- CI: 5 parallel jobs, all green
