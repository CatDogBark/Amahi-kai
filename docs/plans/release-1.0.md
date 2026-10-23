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
