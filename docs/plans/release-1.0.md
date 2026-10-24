# Amahi-kai 1.0: what's left, in order

Status 2026-10-24: 0.10.2 is out; networking (§1, §2b–2f) is done, Tailscale included; §2's pool
is built, with its other checks still open; signed updates (§3) are deferred. Next is §4, Backups,
planned for bare metal.

**What 1.0 means** (CatDogBark, 2026-10-23): a release for other people to install and trust:
updates can't be faked, the NAS's own state is backed up and restorable, and the code and the
docs have had a full pass (signed updates were deferred on 2026-10-24, §3). His own NAS isn't the
point: it's a development machine that switches between the `development` and `releases` channels
to try features before they reach `main`. bitShare is its own project with its own roadmap and
doesn't hold 1.0; Amahi-kai only has to install, store, update and roll back apps correctly, and
bitShare is the app that proves the storage part.

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

## 4. Backups of the NAS's own state

The biggest missing piece. This plan is for someone running Amahi-kai on bare metal, with nothing
underneath it (CatDogBark, 2026-10-24: his own NAS's Proxmox isn't the case to plan for). When the
system disk dies, Amahi-kai's own backup is the only way back, so **restoring onto a fresh install
is the main feature**. The rule for what comes back (CatDogBark, 2026-10-24): the restore brings
the NAS back; whatever is easy to bring back comes back, and whatever is hard is left out and said
so. Today the only copies are the database dumps System Update makes before it runs (the last
three, on the system disk).

### What a backup is

One file per backup, `amahi-kai-<host>-<date>.tar.zst.gpg`: a tar archive, compressed with zstd and
encrypted with GnuPG (AES-256) using a passphrase the admin sets. All three tools are on every
install already (zstd comes with Ubuntu, GnuPG with Amahi-kai's installer), and anyone with the
passphrase can open a backup by hand (`gpg -d <file> | zstd -d | tar -x`). Each backup stands
alone, so a damaged file costs one day, not all of them.

Not restic, though it was weighed. restic keeps backups in a repository of chunks, each backup
storing only what changed: the right shape for terabytes of shares going off-site, so it fits the
file copies after 1.0 (roadmap, "Backups after 1.0"). For this it would be a new package, a folder
of many files where a download or an upload wants one file, and a damaged chunk spoils every backup
that shares it. What goes in here is small: megabytes of settings, plus the apps' folders on the
system disk, which the catalog already trims (Jellyfin's cache and Transmission's downloads are
`backup: false`).

Inside:

- `manifest.json`: the Amahi-kai version, when, which kind (daily, before an update, by hand), and
  what the restore needs before it starts: each account's name and number, the drives (UUID, mount
  point, model, serial), the pools (name, GUID, drives), the network (mode, each port's name, label
  and address), the apps (image, where their data lives) and the packages in use.
- The database (`mysqldump --single-transaction`).
- From `/etc/amahi-kai`: the tunnel token, `trash-days`, `greyhole-pool.conf`, and the update
  channel's line of `amahi.env`. The rest of `amahi.env` stays the new install's: its database
  password, and its session key (nothing in the database is encrypted with that key; a new one only
  means signing in again).
- Samba's passwords (`pdbedit -e smbpasswd:`), so nobody has to set theirs again.
- Tailscale's state, so the NAS comes back as the same device with the same address and no new
  sign-in; and SSH's host keys, so computers that connect over SSH don't warn about a changed key.
- Each app's folders on the system disk that its manifest backs up (the list the copy before an app
  update uses, `app_backup_folders`), read with the app stopped. An app on a pool keeps its data in
  its dataset there, which the pool's snapshots cover and which outlives the system disk.

### Where, when, how many

- **Where:** a folder, `amahi-kai-backups`, at the top of a pool or a data drive, the admin's choice
  (proposed default: the first pool). Never the system disk, the one the backups are for: a NAS with
  no data drive still makes them, and the tab says plainly that they won't survive that disk and to
  download them. Never inside a Greyhole share either: Greyhole only spreads files that come in
  through Samba. The folder is shared read-only, to admins only, as **Backups**, so any computer can
  copy backups off the box (to a USB drive, a cloud folder) and nothing on the network can delete or
  encrypt them.
- **When:** daily by a timer (at the next boot if the server was off), before every System Update,
  and on **Back up now**. System Update keeps its own database dump for its rollback, which has to
  work with backups off. Each backup is read back after it's written: it decrypts, its file list
  reads, and the database dump is whole.
- **How many:** proposed default 30 days, the admin's to change. The tab shows the total size, and
  there must be room first, checked the way an app update's copy checks it (`app_backup_room!`).
- **The passphrase:** at least 12 characters, kept on the NAS where only root can read it so the
  timer can run, never inside a backup. A lost passphrase makes every backup useless, so the tab
  says to keep it in a password manager and has **Check passphrase**. Changing it makes a backup
  straight away; the older ones still open with the old one, and the list marks them.

### The Backups tab, for admins

Backup and restore both in the UI (CatDogBark, 2026-10-23): on or off, where, how many, the
passphrase, Back up now, and the list (time, kind, version, size), each with Download and Restore.
The setup wizard's last step asks for the passphrase, so a new NAS has backups from its first night
(it can be skipped; the dashboard then warns). System Status lists the timer with the other
scheduled jobs, and the dashboard warns while backups are off or the newest good one is more than
two days old.

A **recovery sheet** to print or save, made from the settings as they are: the steps below, which
pool or drive holds the backups, the data drives' models and serials (so the Ubuntu installer isn't
pointed at one of them), the network (mode, each port's name and address, the router, the DHCP
range), and a reminder of where the passphrase is kept. It matters most for a NAS that is the
router: while it's down, there's no internet to look anything up.

### Restore

On a fresh install, **Restore from a backup** is a choice on the setup wizard's first page, in place
of the wizard; on a running NAS it's on the tab. The restore runs as its own job, as System Update
does, so it outlives the app's restarts. The page follows its progress (step names only) without
needing a session, since the accounts change under it, and when it's done asks you to sign in with
the restored accounts. App code runs as the app user (`as_app`), as in the updater.

1. **Find the backups:** on every pool the server can import (ZFS is installed first if a drive is a
   ZFS member), every data drive, and any USB drive plugged in (mounted read-only to look), newest
   first; or upload a file. A backup from a newer Amahi-kai than the one running is refused (update
   first); an older one is brought forward by the migrations.
2. **The passphrase, and what will happen:** what comes back and what doesn't (below), and that the
   old NAS must be off, because two machines with one tunnel and one Tailscale identity fight over
   them. On a running NAS: a plain warning that it replaces the users, shares and settings there
   now, and a choice, off by default there, to put the apps' data back too.
3. **In order:**
   1. The services stop.
   2. The pool is imported, and the data drives are mounted at their old places by UUID.
   3. The accounts come back with their old numbers (the users' and the apps'), before the restore
      installs any package, because files on the pool and the drives are owned by number and today
      an account gets whatever number is free when it's made. Where an old number is taken (the
      `amahi` account is the installer's own), the account gets a new one, its app data is given to
      the new number, and the last page lists it; share files still work through the `users` group.
   4. The packages the backup used, from the helper's list (Docker, Unbound, dnsmasq, radvd,
      Tailscale, cloudflared, Greyhole, ZFS, Fail2ban, unattended-upgrades).
   5. The database is put back and migrated.
   6. The files above go back: the tunnel token, Samba's passwords, Tailscale's state, SSH's host
      keys, the apps' folders.
   7. Samba's, Greyhole's and DNS's configurations are made again (then Greyhole's fsck), with the
      settings that describe this machine's own address taken from the machine, not the backup.
   8. The apps are made again from the images they had, with their data.
   9. The firewall and Fail2ban as they were, the host name, the update channel, automatic security
      updates; the services start; backups go back on, with the passphrase just typed.
4. **The last page:** what came back, what failed (a drive missing, an image that couldn't be
   pulled), and what's left to do by hand.

**A restore never moves the network.** Router mode and the NAS's own fixed addresses stay as this
machine has them: router mode turned on behind the router standing in during a reinstall would put
two routers on one network, and an address change can cut the browser off. All their settings come
back (DNS, blocking, the DHCP range and reservations, port forwards, LAN-only devices, port names);
DNS goes on, and DHCP too unless another DHCP server answers (the DHCP page's own check). For each
port this machine has, the last page offers the rest as steps on the pages that already do them:
the NAS's address back (This NAS, with its guard), then router mode on (Internet), once the modem is
in the internet port and the other router is an access point again. A port the backup names that
this machine doesn't have, after a motherboard change, is listed and set up by hand on Devices:
matching old ports to new ones is out of 1.0 (CatDogBark, 2026-10-24).

**Not restored, and said so** on the last page and in the wiki:

- Files in shares kept on the system disk (the tab warns about those shares while they exist), and
  anything on a pool that's lost: copies of files come after 1.0.
- SSH's own settings: the security audit's fix is a click, and it needs an account with a key first,
  which a new install may not have yet.
- What's fetched again instead of kept: the apps' images, the blocklists, the catalog. Devices'
  current leases (they renew), the logs and the update history.
- Anything changed by hand outside Amahi-kai, and the Ubuntu admin account's own files.

### A NAS that was the router

While it's down the house has no internet, and a fresh install plugged straight into the modem
would sit on the internet with no firewall while it's set up. The recovery sheet's steps: put the
other router back in charge (out of access-point mode, the modem on it), install Ubuntu and
Amahi-kai behind it, restore, then the last page's steps. The router-mode wiki page says to keep a
router that can take over.

### Tested

On the test VM, standing in for bare metal (its Initial snapshot is a fresh Ubuntu, before
Amahi-kai): a pool on extra virtual disks, users with Samba passwords, apps with data on the system disk and on the pool,
Tailscale and the tunnel, router mode on the island. Back up; put the system disk back to Initial
with the data disks kept; install through the website; restore; then check the sign-ins, the shares
over SMB from the laptop, the apps and their data, the accounts' numbers, DNS, and the last page's
router steps on the island. Once more with a data drive in place of the pool. Also: a restore on a
running NAS, an uploaded file, a USB drive, a wrong passphrase, a backup from a newer version.

Decisions for CatDogBark: one file rather than restic, the default place (the first pool), and how
many to keep (30 days). About twelve days of work: the backup side about four, the restore about
five, tests and docs about three.

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
one sign-in for apps (the capability API), copies of the files in shares (to a USB drive or
off-site), and, from the Backups plan (§4), matching a backup's ports to new hardware and a restore
turning router mode back on by itself. All on the roadmap for after.

**Router mode**, listed here until 2026-10-23, came into 1.0 after all and shipped in 0.10.0
(§2b–2f); the house runs on it since 2026-10-24.

**Signed updates (§3)** are out of 1.0 too (CatDogBark, 2026-10-24): with one user, the key to
keep and back up outweighs the risk it covers. They come back when other people run
Amahi-kai; the design in §3 stands for then, with two trusted keys from the start (one on
the laptop, a spare in Proton Drive). Deferring closes nothing: the release that adds the
check is installed by whatever updater is out there, as any release is.
