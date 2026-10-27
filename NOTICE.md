# NOTICE - Amahi-kai Platform

This software is a modernized fork of the Amahi Home Server Platform.

## Original Work

**Amahi Home Server Platform**
Copyright (C) 2007-2013, Amahi
https://github.com/amahi/platform
Licensed under GNU AGPL v3

## Derivative Work

**Amahi-kai Platform** (modernized fork)
Copyright (C) 2026, Enlightened Solutions LLC
https://github.com/CatDogBark/Amahi-kai
Licensed under GNU AGPL v3 (inherited from original)

Website: https://amahi-kai.com

## Modernization History

This fork was created in **February 2026** to modernize the Amahi Platform for current Ubuntu systems with updated dependencies.

**Modernization performed by:**
- **CatDogBark** - Project direction, infrastructure, and testing
- **Claude** (Anthropic) - Technical implementation

### Key Changes from Original

- **Platform**: Fedora to Ubuntu 24.04, installed natively by one command (`bin/amahi-install`)
- **Stack**: Ruby 2.4 to Ubuntu's Ruby 3.2, Rails 3 to Rails 8.1, Bootstrap 5.3 with Stimulus and plain JavaScript (no jQuery), MariaDB
- **Security**: every root action goes through one root helper that checks and logs it; bcrypt passwords; CSRF protection and a Content-Security-Policy; a security audit with fixes
- **Features since the fork**: Greyhole and ZFS storage, a Docker app catalog of its own ([amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps)), the NAS as the network's DNS, DHCP and router, remote access through a Cloudflare Tunnel or Tailscale, and System Update from published releases with rollback

What Amahi-kai does now is in the [README](README.md); what changed, release by release, in the [changelog](CHANGELOG.md).

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
- The original Amahi team for creating and open-sourcing this platform
- The Ubuntu, Debian, Ruby, and Rails communities
- All contributors to the open-source dependencies that make this software possible

## Contact

**For questions about this fork:**
- Email: catdogbark@pm.me
- Website: https://amahi-kai.com
- Repository: https://github.com/CatDogBark/Amahi-kai
- Issues: https://github.com/CatDogBark/Amahi-kai/issues

**For questions about the original Amahi Platform:**
- Website: http://www.amahi.org
- Contact: http://www.amahi.org/contact

## Trademark Notice

"Amahi" is a trademark of the Amahi team. This fork is **not officially endorsed by or affiliated with Amahi**, though the original creator has been informed of and acknowledged this project. The Amahi name is used in accordance with the original AGPL license terms.

---

**Last Updated**: 2026-10-27
