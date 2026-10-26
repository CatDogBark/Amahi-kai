# Amahi-kai 1.0: what's left, in order

Status 2026-10-25: 0.10.2 is out; networking (§1, §2b–2f) is done, Tailscale included. The code
review (§5) and the docs review (§6) are done: seven fix batches on `dev`, each checked on the test
VM. The real pool's checks with bitShare (§2), signed updates (§3) and backups (§4) are after 1.0.
Next: the release candidate (§7).

**What 1.0 means** (CatDogBark, 2026-10-23): a release for other people to install and trust:
updates can't be faked, the NAS's own state is backed up and restorable, and the code and the
docs have had a full pass (signed updates and backups were both deferred on 2026-10-24: §3, §4).
His own NAS isn't the point: it's a development machine that switches between the `development`
and `releases` channels to try features before they reach `main`. bitShare is its own project with
its own roadmap and doesn't hold 1.0; Amahi-kai only has to install, store, update and roll back
apps correctly. bitShare is the app that proves the storage part, after 1.0 (§2).

## 1. Networking's last check

Everything in 0.9.2's networking was tried on the island except one path: DNS answering Tailscale
devices, which only a NAS on Tailscale can try (step 3 of
[`testing/networking.md`](../testing/networking.md)). The rest of that list (the house, the days
after) is use, at CatDogBark's pace.

Done 2026-10-24 on the test VM: after a rewrite of Unbound's settings, its DNS answered the laptop
over Tailscale (`100.100.32.46`): local names and blocked names, from a device on the tailnet. The
rewrite was the gap: Unbound listens on the Tailscale address only when its settings name it, and
the address arrives after the sign-in is approved, so nothing set it up. Now
`amahi-kai-tailscale.path` watches Tailscale's state file, and `bin/amahi-follow-tailscale` (as
the app user) has `TailscaleService.follow!` write DNS's and Samba's settings again once the
addresses settle and differ from the last seen. Shares needed more: Samba can't be bound to
Tailscale's IPv4 address at all (it skips an interface with one address and no broadcast), so
since 0.10.2 it listens on every address and its allow list decides. A reboot of the test VM the
same day needed nothing from the watch: Tailscale had its address within seconds, and DNS and the
shares answered over it, because Unbound may listen on an address that isn't up yet
(`ip-freebind`) and Samba listens everywhere. Found on the way: a second DNS server behind the NAS
router (the test VM's own Unbound) can't use DNS over TLS, because the router keeps port 853 from
every LAN device (§2c, by design). A per-device exemption is on the roadmap, not in 1.0
(CatDogBark: not needed).

## 2. The real pool, and apps on it (after 1.0)

**After 1.0** (CatDogBark, 2026-10-24): this is bitShare's work in tandem with Amahi-kai, so it
doesn't hold 1.0. It stays here as written for when it's picked up.

The four SSDs are in and healthy (SMART and long self-tests passed 2026-10-21). The pool was made
on 2026-10-24, all four in one RAIDZ1 as the checklist planned, and holds real data since: the old
NAS's files, copied into the share Vault. From
[`testing/storage-on-real-drives.md`](../testing/storage-on-real-drives.md):

- The failure tests, once, before any real data: a drive missing at boot (§5), snapshots (§8), a
  failing drive (§9). Using the NAS never exercises failure; these are the ones that matter.
- The real pool (§11).
- Then [`testing/apps.md`](../testing/apps.md) §7b with bitShare's image: install onto the pool,
  the pool refuses to go offline while an app keeps data there, a rollback stops and restarts the
  app, a reboot brings it back. That's Amahi-kai's app storage proven; bitShare's own features are
  bitShare's business.

**The drive layout** was CatDogBark's decision: all four SSDs in one RAIDZ1 pool (about 2.7 TB,
one drive may fail), with shares on the pool, made on 2026-10-24. The failure tests above run on
the real pool with its data in place (CatDogBark, 2026-10-24: his files are backed up elsewhere,
so nothing can be lost).

## 2b. Router mode

Original Amahi could be the house's router, so Amahi-kai carries it over (CatDogBark, 2026-10-23:
in 1.0). 0.9.2 has the LAN half; this adds the internet half as a fourth mode, **Router**, on
Network → DNS & DHCP: a second interface takes the provider's connection (DHCP for now; PPPoE
and a static address later), the NAS forwards and NATs the LAN out through it, the firewall lets
nothing in from the internet except the port forwards the page lists, and DHCP hands out the NAS
as the router. It needs the firewall on, and refuses to turn the interface the admin is connected
through into the internet side. IPv6 for the house (a delegated prefix, a real default route
announced) is a slice of its own after.

Built and tried on the island on 2026-10-23, with a third leg: `vmbr8` with a fake-ISP container on
it (DHCP and DNS on its island side, NAT out through the house), the test VM's `ens20` as the WAN,
the client routed out through the test VM; the forward, the sealed WAN side, the way back and a
reboot all passed. What's left is the house: the Linksys in its Bridge Mode (an access point and
switch, its two SSIDs kept, the OpenWrt bridge still connecting to it), the modem's cable run to
forge for the test, and later forge, the Linksys and the modem side by side
([`testing/networking.md`](../testing/networking.md) §5b), with CatDogBark's laptop tethered to his phone so the
session survives whatever the NAS does, and the provider's cable moved from his router to a spare
port on forge (it's an ISP gateway, so its bridge mode is part of that day).

## 2c. Security at the routing layer

CatDogBark (2026-10-23): a home router today should keep devices from spying as far as a
network can, layered with the encrypted DNS, without breaking the devices or the tunnels.
Switches in router mode, in this order:

1. **Every device uses the NAS's DNS** (on by default in router mode): lookups a device sends
   elsewhere (Roku, Google devices and some TVs ask 8.8.8.8 directly) are redirected to the NAS,
   devices' own encrypted DNS over port 853 is blocked (the NAS's own lookups aren't: they
   start on the NAS), and the known DoH providers are blocked by name through Blocking
   (HaGeZi's list, about 3,300 domains), so a device that can't resolve `dns.google` falls back
   to the NAS. Only a hardcoded DoH address gets past, which is rare.
2. **Vendor tracker lists** as tickboxes in Blocking: HaGeZi's per-vendor lists, curated to block
   the telemetry hosts and keep the service ones (Samsung, LG webOS, Roku, Amazon, Apple,
   Windows/Office, TikTok, Xiaomi; 57 to a few hundred domains each).
3. **Tailscale's port let in on the WAN** (UDP 41641) when Tailscale is installed, so its
   connections stay direct instead of relayed. Cloudflare's tunnel needs nothing: it's outbound.
4. **Per-device "LAN only"** on the devices page: a camera or printer gets no internet.
5. **Anti-spoofing on the WAN**, and a count of connection attempts from the internet dropped.
6. Later: per-device DNS strictness (Unbound views), and opt-in per-device counts of blocked
   lookups.

What the router can't do, said plainly on the page: inspect encrypted traffic, separate
telemetry from the service on the same host (the curated lists are the limit), or keep devices
from each other on one flat network (the access point's or VLANs' job).

Done 2026-10-24, items 4 and 5: **LAN only** on a fixed device's row (Network → Devices; a
`hosts.lan_only` flag, a `ufw route deny in on <lan> out on <wan> from <address>` ahead of the
LAN's allow, by address because a wireless relay rewrites frames' MACs; rewritten whenever the
flag, the address or the device changes while the NAS is the router, and waiting for router
mode otherwise). **Anti-spoofing**: strict reverse-path filtering on the internet side
(`net.ipv4.conf.all.rp_filter = 1` and the WAN's own; the kernel takes the stricter of the two,
so the LAN's own 2 keeps it loose there), put back on the way out; the kernel's
`IPReversePathFilter` counter is the count of forged packets. **Dropped attempts**: the
`deny in on <wan>` rule's packet counter, read by the helper (`network.wan_drops`), shown on the
Internet page with the time the rules were loaded (every router-mode save and boot zero it).
Also, from the "is it a household router yet" comparison: ICMP redirects off and martians
logged on the internet side (the same sysctl drop-in), and Ubuntu's automatic security updates
stated on the Internet page with a link to the one switch on Settings → System Dependencies
(the security audit warns while the NAS is the router without them). What a consumer router has that this doesn't, for the roadmap: signed updates (§3), a
WAN-side log, IPv6 with its firewall, HTTPS for the admin UI, hairpin NAT, UPnP as an opt-in.

## 2d. The Network tab, split

DNS & DHCP holds DNS, DHCP, router, blocking, IPv6, forwards and totals already, and 2c adds
switches. Before 1.0 it becomes: **Devices** (one row per device seen, from the leases: a fixed
address, LAN only, later DNS strictness; replaces Leases and Hosts), **DNS** (provider, blocking
and its lists, allowlist, aliases, totals; replaces DNS Aliases), **DHCP** (range, lease time, the
router option), **Internet** (the WAN interface, forwards, the shield switches, IPv6 later), with
Remote Access and Security as they are, and a **Wireless** tab beside Internet when the NAS
manages access points (after 1.0: OpenWrt APs over their API; the NAS hosts no radio). The
four-way mode becomes a switch on each tab, with the dependencies kept (the router needs DHCP).
Views move; the logic doesn't. Items 1–3 of 2c land on the page as it is, then the split, then
items 4–5 on their new tabs.

Done 2026-10-23: Devices (leases and fixed addresses in one list, with *Fix this address* on any
device seen), DNS (with Blocking and the Names card), DHCP and Internet (the router, forwards,
IPv6); the switches with their dependency chain (DHCP needs DNS, the router needs DHCP, turning
one off turns off what builds on it); the old addresses redirect. The old pages' JavaScript
forms (hosts, aliases) became plain forms.

## 2e. This NAS: its own address

The pages read the NAS's address off its interfaces but never set one, so a fresh install kept
whatever Ubuntu's installer left (DHCP from the router, which can change), and Samba's
`hosts allow` kept the `net` the installer copied once. Network → Devices gets a **This NAS** card:
each port's address and how it got it, changed from the page (automatic, or fixed with its
network size, router and DNS servers), through the helper (`network.set_address`), which rewrites
the port's netplan entry and checks it with `netplan generate`. A change to the port the admin is
connected through is applied after the reply and kept only once a request reaches the NAS at the
new address (`network.keep_address`, from the moving page's probe or the admin arriving);
otherwise the helper's timer puts the old settings back after 90 s. The `net` and `self-address`
settings, DNS, DHCP, the router and Samba follow the new address. The internet side in router mode
stays the Internet page's. Built 2026-10-24, island-tested on the test VM's LAN leg. The same
day: each port says what it is (model or virtual), its link and MAC, takes a name of the admin's
shown wherever it comes up, and a real port's light can be blinked to find it.

## 2f. The network follows an update

An update never touches the network: Unbound, dnsmasq, UFW and the kernel run off the files the
helper wrote, and only the web UI restarts. So a change to how a config is *generated* that
ships in an update does nothing until the next Save of that page (the NAT-chain fix of
2026-10-24 reached the test VM only when the Internet page was saved again), and someone on
`releases` has no reason to Save. Before 1.0, `bin/amahi-update` ends with a resync: while DNS is
on, regenerate every network config (Unbound, the blocklist choice, dnsmasq, radvd, the router's
netplan and NAT block, the UFW rules) and apply only what differs from what's installed, each
through the helper as the pages do. A normal update stays a no-op for the network; one that
changes Unbound's config restarts it (about two seconds of DNS), one that changes the NAT block
reloads UFW. Decided 2026-10-24 (CatDogBark).

Built 2026-10-24: `DnsService.resync!`, run by `bin/amahi-update` after Samba's push
(`rails runner 'puts DnsService.resync_report'`, as the app user). Unbound's config, the lists
chosen for blocking (`chosen.json`), dnsmasq's and radvd's configs are compared with the files
as the helper left them (all readable by the app; one that can't be read is written again, to
be safe); the router's rules are compared as the helper's `router.json` against the settings
(interfaces, forwards, forced DNS, LAN-only devices, Tailscale) and against the shape of the
rules, a number the helper stamps in the state (`ROUTER_RULES_VERSION`, bumped whenever the
rules change shape, as the NAT chains did). Only what differs is applied, through the same
calls the pages make.

## 3. Signed updates

**Deferred, not in 1.0** (CatDogBark, 2026-10-24): see *Not in 1.0*. The design below is kept
for when other people run Amahi-kai.

Today the updater installs whatever the GitHub Release tag points at, and the helper fetches the
app catalog's `main` the same way. Nothing is checked against a key the NAS holds, so control of
the GitHub account (or of GitHub) alone puts code on every NAS. Fine with one user; not for 1.0.

The shape:

- **Releases are signed with a key that never leaves CatDogBark's machine**: git's SSH signing
  (`git tag -s` with an ed25519 key, `gpg.format=ssh`), no GPG to set up. The key is never in the
  repo or in GitHub Actions.
- **The NAS pins the public key** (an `allowed_signers` file installed with the code) and the
  updater runs `git verify-tag` against it before checking anything out. A release whose tag isn't
  signed by a pinned key is refused, and System Status says so. The `development` channel is
  exempt (it follows a branch, not a tag), which is what makes it a development channel.
- **The catalog too:** the helper verifies the fetched commit's signature the same way, so an
  app manifest can't be slipped in through the catalog repo either. Images are already pinned by
  digest in the manifests.
- **release.yml refuses an unsigned tag**, so a release can't be published by mistake.
- **First install trusts GitHub over HTTPS once** (the installer fetches the code and the key
  together); from then on only signed updates. **Rotation:** the pinned file can hold two keys,
  and a signed release updates it.

Decisions for CatDogBark: the key is made on his laptop (the key ceremony is his, with a copy
somewhere safe); what the page says when a release is refused. About a day of work, plus a
CONTRIBUTING step.

## 4. Backups (after 1.0)

Moved to after 1.0 (CatDogBark, 2026-10-24): there are no users yet, and his own NAS has
Proxmox's backups of its VM. The plan, made for bare metal the same day, is
[`backups.md`](backups.md): a backup of Amahi-kai's own state (not the files, which ZFS and
Greyhole keep) and a restore onto a fresh install. Until then the docs say plainly that a NAS's own
settings aren't backed up (§6).

## 5. The code review

A full pass, the way the 2026-10-02 review was done, over everything since: the helper (108
operations now), storage, apps, networking, the release machinery. Next (CatDogBark, 2026-10-24),
with the private review doc.

Read 2026-10-24, area by area; the findings and the order of the fix batches are in the private
review doc's "1.0 review" tab (unfixed details stay there). The batches go out on `dev` in that
order, the first being the router's rules during a save, MariaDB's update and the web page, and
This NAS over the tunnel. Already on its list before the read:

- **Times are the server's clock, in UTC** (roadmap, Open): show them in the browser's zone. Done in
  the web app's batch: the browser writes dates and times of day in its own zone (time_ago.js).
- The remaining low items on the review doc's security audit tab.
- The anonymous `nobody` share leftover; the roadmap's `nosuid,nodev` entry is done and stale.
- The four specs that need root (`pending` in CI) and whether the island or a container can run
  them.
- Dependencies: Rails 8.1.4 is current; Ruby is Ubuntu's 3.2, maintained with 24.04 through 2029.
- What the review finds goes out as fix batches on `dev`, the usual way.

Done 2026-10-24 to 2026-10-25: six fix batches (the router's rules and the NAS's address, the
updater and installer, storage, apps, the rest of networking, the web app), each pushed to `dev`,
green in CI and checked on the test VM, several with a before-and-after on the island. What the
review left for after 1.0 is in the roadmap and the private review doc.

## 6. The docs review

Everything a new person reads, checked against what 1.0 does: the README, CONTRIBUTING, CLAUDE.md
(its "current work" is from 2026-10-08), the roadmap (the shelf-stable lists are done; rewrite it
around what's after 1.0), the website and its wiki (the index still says dnsmasq does local DNS),
the installer's and the setup wizard's own words, and the changelog's 1.0 entry written for
someone who's never seen Amahi-kai. With backups after 1.0 (§4), the wiki also says plainly that a
NAS's own settings aren't backed up: the files are safe on a pool or Greyhole's drives, but a lost
system disk means installing again, importing the pool and setting the NAS up again by hand.

Done 2026-10-25, as the seventh batch: the README and the website (networking, ZFS pools, the apps
with bitShare marked early and Vaultwarden's HTTPS note), one CONTRIBUTING, CLAUDE.md, NOTICE, the
privilege model (the fetched catalog, the network, unsigned updates and catalog as known gaps),
the wiki (what Amahi-kai doesn't back up, users and their roles, a pool after installing again,
today's page names), the wizard's and the installer's words, this plan and the roadmap, and the
changelog's 1.0 entry.

## 7. The release

1. `1.0.0rc1` on `main`, published as a pre-release. A fresh install of it on the test VM from
   its Initial snapshot through the website's installer, the public path.
   Done 2026-10-25: published from #172; the website's installer, the setup wizard and the old
   pool's import (Disks → ZFS Pools, its snapshots with it) passed, with no errors in the app's
   log. Found: the wizard's storage step said there were no drives when the others held a ZFS
   pool, and the wiki said to leave them unticked there (it doesn't list them). Both fixed.
2. Whatever that finds, fixed; `1.0.0`.
   Done 2026-10-25: 1.0.0 from #173. The test VM's update to it found fwupd's refresh timer
   failing (the installer masked fwupd but left the timer on): 1.0.1, the same day. The NAS's
   update then showed DHCP's device names stopped (a burst of leases hit systemd's start
   limit for their job): 1.0.2. Then 1.0.3: pages whose sign-in ended take you to the sign-in
   page, sign out in the header, and the water background's clock on the real one.
3. The NAS and the test VM are development machines and switch channels as the work needs.
   One caution for switching back from `development` to `releases`: an update never goes to a
   lower version, so the switch takes effect at the next release, and if `dev` ran a migration
   the release doesn't have, the database is ahead of the code (migrations are written to work
   with the previous version's code, so this is survivable, but a backup first is the habit).
4. The five v0.1–v0.2 pre-releases on the Releases page: kept as history (CatDogBark,
   2026-10-25).

## Not in 1.0

So it doesn't creep in: HTTPS on the LAN, the debug pages as a Settings tab, quotas, the phone
layout, private folders per user, P4.6b (Greyhole shares through Samba, which is bitTube's need),
one sign-in for apps (the capability API), the real pool's checks with bitShare (§2), and backups:
the NAS's own state ([`backups.md`](backups.md)) and copies of the files in shares. All on the
roadmap for after.

**Router mode**, listed here until 2026-10-23, came into 1.0 after all and shipped in 0.10.0
(§2b–2f); the house runs on it since 2026-10-24.

**The real pool and apps on it (§2)** are out of 1.0 (CatDogBark, 2026-10-24): it's bitShare's
work alongside Amahi-kai. The pool is built and in use, and its failure tests run on it later,
data in place.

**Signed updates (§3)** are out of 1.0 too (CatDogBark, 2026-10-24): with one user, the key to
keep and back up outweighs the risk it covers. They come back when other people run
Amahi-kai; the design in §3 stands for then, with two trusted keys from the start (one on
the laptop, a spare in Proton Drive). Deferring closes nothing: the release that adds the
check is installed by whatever updater is out there, as any release is.

**Backups (§4)** are out of 1.0 as well (CatDogBark, 2026-10-24): there are no users yet, and his
NAS has Proxmox's backups of its VM. The bare-metal plan waits in [`backups.md`](backups.md).
