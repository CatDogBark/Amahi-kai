# NOTICE - Amahi-kai Platform

This software is a modernized fork of the Amahi Home Server Platform.

## Original Work

**Amahi Home Server Platform**
Copyright (C) 2007-2013, Amahi
https://github.com/amahi/platform
Licensed under GNU AGPL v3

## Derivative Work

**Amahi-kai Platform** (modernized fork)
Copyright (C) 2026, Troy (CatDogBark)
https://github.com/CatDogBark/Amahi-kai
Licensed under GNU AGPL v3 (inherited from original)

Website: https://amahi-kai.com

## Modernization History

This fork was created in **February 2026** to modernize the Amahi Platform for current Ubuntu/Debian systems with updated dependencies.

**Modernization performed by:**
- **Kai 🌊** (OpenClaw AI Agent) - Technical implementation
- **Troy** - Project direction, infrastructure, and testing

### Key Changes from Original

- **Platform**: Migrated from Fedora to Ubuntu 24.04 / Debian 12
- **Ruby**: Upgraded from 2.4.3 → 3.2.10
- **Rails**: Upgraded from 3.x → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0.4
- **Bootstrap**: Upgraded from 3/4 → 5.3
- **Frontend**: Removed jQuery entirely, migrated to Stimulus controllers + Turbo + vanilla JS
- **Database**: MariaDB (production), native install with systemd service
- **Authentication**: Migrated to SCrypt password hashing (from Sha512)
- **Asset Pipeline**: Converted CoffeeScript to JavaScript, replaced uglifier with terser
- **Security**: SQL injection fixes, shell injection prevention (Shellwords.escape), CSP headers, CSRF protection, AES-256-GCM credential encryption, security audit system with auto-fix
- **Docker App System**: 14-app catalog with one-click install, built-in reverse proxy, lifecycle management
- **Storage**: Greyhole integration for drive pooling and file duplication
- **Remote Access**: Cloudflare Tunnel integration with streaming install UI
- **Dashboard**: System overview with real-time CPU, memory, disk, network stats
- **Setup Wizard**: 6-step guided setup + headless installer mode
- **Dark Mode**: Automatic via `prefers-color-scheme` with CSS variable overrides
- **Testing**: 603+ specs (model, request, feature, lib), ~57% coverage
- **Native Install**: Idempotent `bin/amahi-install` handles full stack setup
- **One-Click Updates**: Update button in header pulls code, installs deps, restarts service

### Docker App Catalog

Built-in reverse proxy for accessing Docker apps through Cloudflare Tunnel:
- Jellyfin, Nextcloud, FileBrowser, Syncthing, Grafana, Gitea, Transmission
- Vaultwarden, Home Assistant, Portainer, Uptime Kuma, Audiobookshelf
- Pi-hole, Paperless-ngx

All changes maintain backward compatibility with Amahi's plugin architecture and user data structures where possible.

## License Compliance

This derivative work is distributed under the **GNU AGPL v3** license as required by the original Amahi Platform license.

As required by the original license (see [COPYING](COPYING)), this software:
- ✅ Retains attribution to the original Amahi project
- ✅ Maintains references to amahi.org
- ✅ Makes source code available to all users
- ✅ Requires derivative works to be licensed under AGPL v3

For the full license text, see the [COPYING](COPYING) file.

## Attribution

The Amahi team created an excellent home server platform that served thousands of users for over a decade. This fork aims to extend that legacy by making the platform viable on modern Linux distributions.

**We are grateful to:**
- Carlos Puchol and the original Amahi team for creating and open-sourcing this platform
- The Ubuntu, Debian, Ruby, and Rails communities
- All contributors to the open-source dependencies that make this software possible

## Contact

**For questions about this fork:**
- Website: https://amahi-kai.com
- Repository: https://github.com/CatDogBark/Amahi-kai
- Issues: https://github.com/CatDogBark/Amahi-kai/issues

**For questions about the original Amahi Platform:**
- Website: http://www.amahi.org
- Contact: http://www.amahi.org/contact

## Trademark Notice

"Amahi" is a trademark of the Amahi team. This fork is **not officially endorsed by or affiliated with Amahi**, though the original creator has been informed of and acknowledged this project. The Amahi name is used in accordance with the original AGPL license terms.

---

**Last Updated**: 2026-02-24
