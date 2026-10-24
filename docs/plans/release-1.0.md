# Amahi-kai 1.0: what's left, in order

Status 2026-10-23: planned, nothing started. 0.9.2 is out (DNS and DHCP for the network).

**What 1.0 means** (CatDogBark, 2026-10-23): a release for other people to install and trust:
updates can't be faked, the NAS's own state is backed up and restorable, and the code and the
docs have had a full pass. His own NAS isn't the point: it's a development machine that switches
between the `development` and `releases` channels to try features before they reach `main`.
bitShare is its own project with its own roadmap and doesn't hold 1.0; Amahi-kai only has to
install, store, update and roll back apps correctly, and bitShare is the app that proves the
storage part.

## 1. Networking's last check

Everything in 0.9.2's networking was tried on the island except one path: DNS answering Tailscale
devices, which only a NAS on Tailscale can try (step 3 of
[`testing/networking.md`](../testing/networking.md)). The rest of that list (the house, the days
after) is use, at CatDogBark's pace.

## 2. The real pool, and apps on it

The four SSDs are in and healthy (SMART and long self-tests passed 2026-10-21); nothing is built on
them yet. From [`testing/storage-on-real-drives.md`](../testing/storage-on-real-drives.md):

- The failure tests, once, before any real data: a drive missing at boot (§5), snapshots (§8), a
  failing drive (§9). Using the NAS never exercises failure; these are the ones that matter.
- The real pool (§11).
- Then [`testing/apps.md`](../testing/apps.md) §7b with bitShare's image: install onto the pool,
  the pool refuses to go offline while an app keeps data there, a rollback stops and restarts the
  app, a reboot brings it back. That's Amahi-kai's app storage proven; bitShare's own features are
  bitShare's business.

Decision for CatDogBark: **the drive layout.** The checklist ends with all four SSDs in one RAIDZ1
pool (about 2.7 TB, one drive may fail), with shares on the pool and Greyhole only tried along
the way. Confirm that's still the plan before §11, since the pool's layout can't be changed after.

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

## 4. Backups of the NAS's own state

The biggest missing piece. Today the only copies are the database dump System Update makes before
it runs (the last three, on the system disk) and Proxmox's backups of the VM, which someone
installing on bare metal doesn't have.

- **What:** the database (users, shares, settings, apps), `/etc/amahi-kai`, Samba's password
  database, and what the helper keeps in `/var/lib/amahi-kai` that can't be rebuilt (the app
  records, the catalog can). Not the files in shares: those are what the pool's redundancy and
  snapshots are for, and off-site copies of them are later (the roadmap's Proton Drive app).
- **When:** daily, by a timer, kept for a set number of days; and a backup before every System
  Update, in place of the bare database dump.
- **Where and how:** the archive holds secrets (the session key, the tunnel token), so it's
  encrypted with a passphrase the owner sets once, and can then sit on a share or a pool dataset
  where other people can reach it. A dataset of its own (`<pool>/backups`) is the natural home;
  a share works for a NAS without a pool.
- **A Backups tab, for admins** (CatDogBark, 2026-10-23: backup and restore both in the UI):
  on or off, where, how many to keep, the passphrase, Back up now, the list of backups with each
  one's time and size, and **Restore** from any of them (or from an uploaded archive): the
  passphrase, a plain warning that it replaces the users, shares and settings there now, then
  the restore, with the services stopped and started around it. On a fresh install, Restore is
  the way to bring a NAS back: sign in as the seeded admin, restore, and the wizard is skipped.
- **Tested once** on the test VM from its Initial snapshot: fresh install, restore, everything
  back, apps included.

Decisions for CatDogBark (the roadmap has had them since 2026-10-09): the destination and how
many to keep. Three to four days of work.

## 5. The code review

A full pass, the way the 2026-10-02 review was done, over everything since: the helper (108
operations now), storage, apps, networking, the release machinery. Not now; its own session, with
the private review doc. Already on its list:

- **Times are the server's clock, in UTC** (roadmap, Open): show them in the browser's zone.
- The remaining low items on the review doc's security audit tab.
- The anonymous `nobody` share leftover; the roadmap's `nosuid,nodev` entry is done and stale.
- The four specs that need root (`pending` in CI) and whether the island or a container can run
  them.
- Dependencies: Rails 8.1.4 is current; Ruby is Ubuntu's 3.2, maintained with 24.04 through 2029.
- What the review finds goes out as fix batches on `dev`, the usual way.

## 6. The docs review

Everything a new person reads, checked against what 1.0 does: the README, CONTRIBUTING, CLAUDE.md
(its "current work" is from 2026-10-08), the roadmap (the shelf-stable lists are done; rewrite it
around what's after 1.0), the website and its wiki (the index still says dnsmasq does local DNS),
the installer's and the setup wizard's own words, and the changelog's 1.0 entry written for
someone who's never seen Amahi-kai.

## 7. The release

1. `1.0.0rc1` on `main`, published as a pre-release. A fresh install of it on the test VM from
   its Initial snapshot through the website's installer, the public path, then a restore of a
   backup onto it.
2. Whatever that finds, fixed; `1.0.0`.
3. The NAS and the test VM are development machines and switch channels as the work needs.
   One caution for switching back from `development` to `releases`: an update never goes to a
   lower version, so the switch takes effect at the next release, and if `dev` ran a migration
   the release doesn't have, the database is ahead of the code (migrations are written to work
   with the previous version's code, so this is survivable, but a backup first is the habit).
4. The five v0.1–v0.2 pre-releases on the Releases page: keep or delete, his call.

## Not in 1.0

So it doesn't creep in: HTTPS on the LAN, the debug pages as a Settings tab, quotas, the phone
layout, private folders per user, P4.6b (Greyhole shares through Samba, which is bitTube's need),
one sign-in for apps (the capability API), and off-site backups of the files. All on the roadmap
for after.

**Router mode** is out too, unless CatDogBark says otherwise (2026-10-23). 0.9.2 has the LAN half
(DNS and DHCP for the devices); the internet half doesn't exist yet:

- A second network interface for the internet, and getting an address on it (DHCP from the
  provider, or PPPoE for providers that use it).
- Forwarding and NAT between the LAN and that interface, so devices reach the internet through
  the NAS.
- A firewall facing the internet: nothing in from outside except replies, and the NAS's own
  services (SSH, the web UI, Samba, DNS, DHCP) never offered on the internet side.
- IPv6 for the house: a prefix delegated by the provider, and the NAS announcing a real default
  route on the LAN (today it announces itself with a router lifetime of 0, "not a router", on
  purpose).
- A port forwarding page, and the way back: the NAS down means the house is offline, and a
  System Update's restart is a minute without internet.

A few days for the IPv4 half, more with IPv6 delegation and PPPoE. The island is the test bed
for it: the test VM already has a LAN leg and an island leg, so the client can be routed out
through it without touching the house.
