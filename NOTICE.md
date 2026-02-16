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

## Modernization History

This fork was created in **February 2026** to modernize the Amahi Platform for current Ubuntu/Debian systems with updated dependencies.

**Modernization performed by:**
- **Kai 🌊** (OpenClaw AI Agent) - Technical implementation
- **Troy** - Project direction and infrastructure

### Key Changes

- **Platform**: Migrated from Fedora to Ubuntu 24.04 / Debian 12
- **Ruby**: Upgraded from 2.4.3 → 2.7.8 → 3.2.10
- **Rails**: Upgraded from 5.2.8 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0.4
- **Bootstrap**: Upgraded from 3/4 → 5.3
- **Database**: Migrated to MariaDB (from MySQL)
- **Services**: Modernized for systemd, replaced hda-ctl with direct execution
- **Authentication**: Migrated to SCrypt password hashing (from Sha512)
- **Asset Pipeline**: Converted CoffeeScript to JavaScript, replaced uglifier with terser
- **Security**: Shellwords.escape on shell commands, Rack::Attack rate limiting, CSP headers
- **Testing**: 160+ specs (model, request, feature), headless Chromium for JS specs
- **Dependencies**: Updated all gems for compatibility with modern Ruby/Rails

All changes maintain backward compatibility with Amahi's plugin architecture and user data structures where possible.

## License Compliance

This derivative work is distributed under the **GNU AGPL v3** license as required by the original Amahi Platform license.

As required by the original license (see [COPYING](COPYING)), this software:
- ✅ Retains all Amahi logos and branding
- ✅ Maintains URLs pointing to amahi.org resources
- ✅ Makes source code available to all users
- ✅ Requires derivative works to be licensed under AGPL v3

For the full license text, see the [COPYING](COPYING) file.

## Attribution

The Amahi team created an excellent home server platform that served thousands of users for over a decade. This fork aims to extend that legacy by making the platform viable on modern Linux distributions.

**We are grateful to:**
- The original Amahi team for creating and open-sourcing this platform
- The Fedora, Ubuntu, Debian, and Rails communities
- All contributors to the dependencies that make this software possible

## Contact

**For questions about this fork:**
- Repository: https://github.com/CatDogBark/Amahi-kai
- Issues: https://github.com/CatDogBark/Amahi-kai/issues

**For questions about the original Amahi Platform:**
- Website: http://www.amahi.org
- Contact: http://www.amahi.org/contact

## Trademark Notice

"Amahi" is a trademark of the Amahi team. This fork is **not officially endorsed by or affiliated with Amahi**. The Amahi name and logos are used in accordance with the original AGPL license terms.

---

**Generated**: 2026-02-15
**Last Updated**: 2026-02-16 (Ruby 3.2 + Rails 8.0 + Bootstrap 5 + security hardening)
