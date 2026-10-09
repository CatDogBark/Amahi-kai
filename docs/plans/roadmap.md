# Fix plan and roadmap

Status as of 2026-10-08. Each phase came from a full code review (October 2026; the detailed
review is a Claude Doc Troy owns, linked from `CLAUDE.md`). Every PR below was deployed with
System Update and checked on the NAS, with one exception: from #21 to #24 System Update stopped
at its migration step (json 3 broke Sprockets 4.2, fixed in #25) and the old app kept running,
so #21–#24 reached the NAS together on 2026-10-04 and were checked then.

## Done

| Phase | What it covered | PRs |
| --- | --- | --- |
| 0. Confirm on the NAS | Read-only checks; removed a leftover first-run endpoint; fixed `useradd`/`pdbedit` so web users get Linux and Samba accounts; CI fails on spec failures again | #2–#6 |
| 1. Close the takeover paths | Per-request sessions (`Current`); POST-only system actions; streams carry the CSRF token; setup wizard closes after setup; sandboxed raw previews; theme name allowlist; proxy strips the Amahi cookie; production host allowlist | #7–#12 |
| 2. Silent failures and data safety | Seeds never delete; `nofail` fstab entries; NVMe/LVM-aware OS-disk guard; Samba bound to LAN + Tailscale and regenerated with Greyhole settings; uploads write directly; tunnel token by POST into a root-only file; log redaction; 7-day session expiry; updater re-execs itself; failures reported | #13–#17 |
| 3. I. CI hardening | Blocking RuboCop/Brakeman (pinned, baseline + noted ignore file), MariaDB CI job, bundle-audit | #19 |
| 3. Servers tab | Settings → Servers lists services live from systemd (`lib/system_services.rb`) with Start/Stop/Restart | #20 |
| 3. J. Rails 8.1.4 | `load_defaults 8.1`, 13 gems with advisories updated, bundle-audit blocking | #21 |
| 3. K. Dead code | PDC mode, printer shares, 8 legacy tables, the unused Docker API wrapper and gems, stale stubs and files | #22 |
| 3. L. Privileged helper, part 1 | `libexec/amahi-helper`: users, Samba config and share folders, validated and logged; web users get no shell; 34 sudo rules gone | #24 |
| 3. Fix | Sprockets 4.3: production boots with compiled assets again (System Update had stopped at migrations since #21) | #25 |
| 3. M1. Privileged helper, part 2a | Settings → Servers, reboot/power off, hostname, dnsmasq and DNS aliases, swap through the helper; 24 sudo rules gone | #26 |
| 3. M2. Privileged helper, part 2b | Data drives (format, mount, fstab, preview) and Greyhole (config, database, one install path, pinned key) through the helper; 26 sudo rules gone | #27 |
| 3. M3 + P. Privileged helper, part 2c | Package installs (pinned apt repositories, fixed list), Cloudflare Tunnel, Tailscale, Docker's install and the security audit's fixes through the helper; audit reads `sshd -T`, server-side tunnel gate; 42 sudo rules gone, 10 left | #28 |
| 3. N. Root-owned install | `/opt/amahi-kai` is root's except the app's own folders; installer and updater run every Rails and bundle step as `amahi`; privilege model doc rewritten | #30 |
| 3. O. Update rollback | System Update runs as its own job, backs up the database, and rolls back to the running commit if a step or the restarted app fails; updater sudo rules gone (6 left) | #31 |
| 3. Q. Plain CSS | Sass compiler gone: the app's stylesheets are plain CSS and Bootstrap is its official 5.3.8 build (`vendor/assets`); System Status shows the deployed commit | #32 |
| 3. Fix | System Update's restart no longer waits 90 seconds: the update page's stream ends when Puma stops, and Puma gives open requests 10 seconds | #33 |
| 3. Fix | The setup wizard can't finish while the seeded admin password still works | #34 |
| 3. Fix | Drive temperatures through the helper; `smartctl`'s open-ended sudo rule removed (5 rules left: the helper and Docker's) | #35 |
| 3. Fix | Update and install windows keep their size: a status bar with a timer and the result; System Update's button just reloads | #36 |
| 3. Update check | The helper checks for an update every 6 hours (timer) and on Check now; System Status shows it, with Update now or Repair; an update with nothing new stops after the pull | #37 |
| 3. Small fixes | Login throttle by the real client address; static DHCP hosts written to dnsmasq; Gateway checkboxes saved; setup storage step keeps the pool; Users JSON create; Apps page survives a failed Docker check | #38 |
| 3. Repo cleanup | Unused files, scripts, initializers, classes, partials, images and archived browser tests removed (with Capybara and the Feature Specs job); README, install guide and CONTRIBUTING refreshed | #39 |
| 3. English only | 25 translations, the language picker, the language cookie and right-to-left styling removed (Troy's decision) | #40 |
| 3. Update notice | A dot on the header's update button and a dashboard line when an update is waiting; the button opens a What's new window (changelog, pull requests, Update now or Later; else Check now and Repair) | #43 |
| Storage S1. ZFS pools | Disks → ZFS Pools: install ZFS (cache capped), create a pool in the chosen layout, pool status; every drive's use shown; ZFS drives kept away from share storage. Not yet tested on real drives | #44 |
| Storage fix. lsblk tree | The helper's drive checks and ZFS Pools read lsblk as a tree (NAME first; a flat list is refused), so the system disk is recognised again; specs on the real lsblk; What's new without the dash | #45 |
| Storage S2. Health | Health check every 15 minutes (pools + SMART, sleeping drives left asleep); alerts on the dashboard and Disks pages; drive health on ZFS Pools and Devices; Scrub now and Ubuntu's monthly scrub shown; smartmontools installed. Not yet tested on real drives | #46 |
| Storage fix. Services and labels | ZFS's event daemon, smartd, Fail2ban and the VM guest agent in the services lists; drives without SMART data say why (virtual disk, none given, no smartmontools, not checked) | #47 |
| Scheduled jobs | Jobs card on the dashboard (System, Services and Jobs in one row) and Settings → Jobs: Amahi-kai's timers, security updates and the pool scrub with last run, result and next run; smartd shown as Idle when there's nothing to watch | #48 |
| Tooltips | Bootstrap tooltips after 150 ms (data-tip, tooltips.js) instead of the browser's title; extra information marked (ⓘ, dotted underline, help cursor); needed information moved onto the page; a spec keeps title tooltips out | #49 |
| Storage S3. Manage pools | Replace a drive (resilver, page refreshes while it runs), add a group shaped like the pool's, delete a pool behind its typed name (drives freed); autoexpand on new pools. Not yet tested on real drives | #50 |
| Storage S4. Snapshots | Hourly and daily snapshots kept per pool (24 and 30 by default), taken and pruned by amahi-kai-snapshots.timer; take now, delete, roll back behind the pool's name; only Amahi-kai's own snapshots are touched. Datasets moved to Phase 4. Not yet tested on real drives | #51 |
| Fix. Update window | A status check killed by the app's restart no longer reads as a finished (failed) update; the window waits for the restarted version | #52 |
| Storage S5. Read-only file browser | The web file browser views and downloads only (upload, new folder, rename, delete removed), so shares change only through Samba; pooled files preview and download; folder zips work (the zip gem was missing), stream, and leave out links outside the share | #53 |
| Remove dummy mode | No AMAHI_DUMMY_MODE setting or System Status row: outside production commands and the root helper are only recorded (Shell.simulated?), production always runs them; specs simulate by default | #55 |
| Phase 4 P4.1. Apps through the root helper | The helper installs, starts, stops and uninstalls apps from manifests in `config/apps` (five apps, tag and digest pinned): a system user and folder per app, generated secrets shown to admins, memory limits, own ports, uninstall keeps data. The `docker` and `/opt/amahi` sudo rules and the `docker` group are gone: the helper is the only sudo rule. Not yet tested on the NAS ([`apps.md`](../testing/apps.md)) | #58 |
| Phase 4 P4.2. Reaching apps | App ports reachable from the LAN and Tailscale only (the helper's `AMAHI-APPS` chain in Docker's `DOCKER-USER`, rebuilt each time Docker starts); ports automatic (catalog port, or the next free one, kept) and shown on the Apps page; `/app/<id>` proxy removed; no Open links through the Cloudflare Tunnel. Not yet tested on the NAS | #59 |
| Phase 4 P4.5. App updates | Update to the catalog's version from the app's row (manual), with What's new; the helper copies the app's data (room checked, caches left out), starts the new version and rolls back if it isn't healthy in 5 minutes (Docker's health check, or the web page answering); one copy kept 30 days for Undo update, pruned daily; `script/app-versions` finds newer releases for a person to apply. Not yet tested on the NAS | #62 |
| bitTube in the catalog | bitTube (`ghcr.io/catdogbark/bittube:0.1.0`, pinned by digest) is the catalog's sixth app, on port 8484, writing downloads into a share; `script/app-versions` reads GitHub's registry too. Not yet tested on the NAS | #63 |
| Fix. Times that stay current | "… ago" times (update check, System Status, pool health, snapshots, Jobs) are worked out again every minute and when a dialog opens (time_ago.js), instead of only when the page loaded; the update check shows its time of day | #61 |
| Phase 4 P4.4. Shares for apps | Shares chosen at install and changed later, at `/shares/<name>`, found by name in smb.conf by the helper; read only unless the app writes shares and Greyhole doesn't pool the share (pooled shares bring their copy folders, read only); default ACLs keep what apps write editable over SMB; images aren't downloaded again. ZFS datasets for apps moved to P4.6. Not yet tested on the NAS | #60 |
| Apps: the catalog | bitTube 0.1.1–0.1.4 and its logo (installed apps show the catalog's logos); the dashboard says which apps have an update; P4.5b: the catalog is its own repo ([CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps)), fetched by the one update check for Amahi-kai and its apps; P4.5c: installed apps announced on the LAN (mDNS, with Avahi on Settings → Servers) | #64–#73 |
| Docs. Making apps | The wiki's Making Apps page; the wiki and README catch up with the catalog repo | #74 |
| Addresses in one place | Every link to an app or to Amahi-kai is made in one place (for HTTPS later); apps whose own page is HTTPS (`web_tls`) open with https | #75, #76 |
| Fixes | An app's passwords open again; the footer no longer covers the bottom of long pages | #77, #78 |
| Storage on the NAS (virtual drives) | Found testing Greyhole and shares on the NAS: Greyhole installs again, with install, uninstall, start and stop for Greyhole and ZFS; small drives; a fixed 10 GB free; Disks' confirmations ask; Greyhole gets every share and drive; taking a drive out, or turning a share's copies Off, moves its files first; copying into a pooled share works (Amahi-kai's own dfree command); no usage reports to greyhole.net | #79–#87, #90, #91, #94 |
| System Dependencies | Settings → System Dependencies: versions and the updates waiting, Update, Update all, Hold, and automatic updates off unless switched on | #88, #89 |
| The Trash and the file browser | Every share has a Trash (Greyhole's on pooled shares, Samba's recycle bin on others), in the file browser below the shares, kept 30 days; folder zips stream, with a notice until they start; a Shares page in the header | #92, #93, #95–#97 |
| Share settings | A share's settings laid out by what they decide, each explained; the Features toggles and tags gone | #99 |
| The October look | Dark for everyone, mint on near-black glass, Space Grotesk; a new header and Setup's tabs as pills; the file browser redone (whole-row links, a panel for the selected file, list or grid); the theme system and light theme gone | #101, #102 |
| Cleanup | Only the parts of Rails it uses, no Turbo; dead code, routes, translations, templates and styles; the themes table, tags' and users' SSH-key columns dropped; one disk library; every command run as an argument list (no shell strings outside the debug pages); `Shell` trimmed; specs CI skipped run; RuboCop's old-offense list empty and gone; drive temperatures in °F | #103–#107, #109–#112 |
| Fix. Update dialog | System Update's dialog stays current on a page left open | #106 |
| Docs. The wiki catches up | File Sharing, Storage Pooling and Updating describe the share settings, the file browser, the Trash and System Dependencies as they are | #108 |

## Phase 3

Done. Decisions made: Ruby stays on Ubuntu 24.04's patched 3.2; `main` stays the release until
shares are tested on real drives, then tagged releases and an updater change; the codebase
becomes root-owned (in N); Docker app work moves to Phase 4.

- [x] **M. Privileged helper, part 2**, in three PRs (Troy, 2026-10-04); design in
  [`privileged-helper.md`](privileged-helper.md):
  - [x] **M1.** Settings → Servers, reboot and power off, hostname, dnsmasq and DNS aliases,
    swap (#26).
  - [x] **M2.** Data drives and fstab (keeping the PR #13 rules exactly), Greyhole config,
    database and install (one install path instead of three); 26 sudo rules gone (#27).
  - [x] **M3.** Package installs from pinned apt repositories and a fixed list, Cloudflare
    Tunnel, Tailscale (its apt repository instead of a downloaded install script run as root),
    Docker's install, and the security audit's fixes with P below; 42 sudo rules gone, leaving
    the helper, the updater and Docker (#28).
- [x] **N. Root-owned install**: `/opt/amahi-kai` owned by root (`bin/amahi-set-ownership`; the
  `amahi` user keeps `tmp/`, `log/`, `public/assets/`, `vendor/bundle/`); the installer and
  `amahi-update` run every Rails and bundle step as `amahi`; root's `git pull` runs without hooks;
  `production.log` is rotated as `amahi`; `docs/security/PRIVILEGE-ESCALATION-MITIGATION.md`
  rewritten to describe the helper and this model (#30).
- [x] **O. Update rollback** (designed with Troy, 2026-10-04: in place, database backups, its own
  job; #31): System Update runs as `amahi-kai-update.service` (started by the helper's
  `system.update`; the page follows `/var/log/amahi-kai/update.log` and reconnects through the
  restart). It remembers the running commit and its compiled assets, dumps the database before
  migrating (the last 3 kept), and if gems, migrations, the asset build or the restarted app
  fail, puts the previous commit back and says so. The database isn't rolled back, so
  migrations must work with the previous version's code. The updater's 4 sudo rules are gone.
- [x] **P. Security audit fixes** (in M3, #28; `lib/security_audit.rb`): read effective SSH settings with
  `sshd -T` (drop-ins in `sshd_config.d` win over `sshd_config`); warn that Docker-published ports
  bypass UFW; make the "tunnel blocked until the audit passes" rule a server-side check, not just
  a hidden button. The firewall fix also opens DNS and DHCP once dnsmasq is configured, and the
  SSH password fix needs a key first.
- [x] **Q. Replace `sassc`** (LibSass is unmaintained; #32). Troy chose plain CSS (2026-10-04): Bootstrap
  5.3.8's official CSS and JS are vendored (`vendor/assets`), the app's four Sass files are plain
  CSS, and `sassc`, `sass-rails` and the `bootstrap` gem are gone (`sprockets-rails` is now in
  the Gemfile itself). Screenshots of 14 pages in light and dark mode match the Sass build
  pixel for pixel, live numbers aside. (The themes went in #102, and with them their Sass
  sources.) Sprockets stays; Propshaft can come later.
- [x] **Content-Security-Policy**: enforced (scripts only from Amahi-kai itself, no inline
  scripts), once the inline handlers (#121) and the pages' own scripts (#122) had moved into
  the JavaScript files. Inline styles are still allowed; taking them out is a later pass.

## Next: shelf-stable

Troy (2026-10-08): Amahi-kai's major code work is finished first, then everything is tested, then
bitShare (P4.6). In this order:

1. The security fixes from the 2026-10-08 audit (details in the private review doc that
   `CLAUDE.md` links), with the Open item on `nosuid,nodev` below.
2. Share toggles in one place (`SharesController` and `ShareAccessManager` duplicate them).
3. Fewer `Setting` queries per request (`before_action_hook`).
4. System Status and the dashboard read the server's details through `SystemInfo` alike.
5. The inline `onclick` handlers and scripts move into the JavaScript files, then
   Content-Security-Policy is enforced (Phase 3's last item). Done: #121, #122 and the CSP PR.

## Next: before shelf-stable

After the audit's fixes and the inline-script work (2026-10-09), in this order:

1. **Browser tests** in CI ([`browser-tests.md`](browser-tests.md)): done (#127, #129); the
   setup wizard's spec waits for the wizard's redo.
2. **Backups**, planned when Troy decides where they go (2026-10-09). The shape: a daily dump
   of the database (users, shares, settings) and `/etc/amahi-kai` (its configuration, minus the
   secrets that stay root-only) into a folder of Troy's choice, kept for a set number of days.
   Decisions for later: the destination (a share, so it's reachable over SMB and copied by
   whatever backs the shares up, or a pool once there is one), how many to keep, and whether
   restoring is a page or a command.
3. **Signed updates:** tagged releases, verified by the updater against a key pinned in the
   installed copy, so control of the GitHub account alone can't put code on a NAS.

HTTPS stays later and optional (see below); Cloudflare Access in front of the tunnel is a
setting on Cloudflare's side, for when anyone but Troy gets the link.

## Open, not yet scheduled

Smaller findings from the review that no PR covers yet. Fold them into a nearby PR when it
touches the same code.

- Several features staged files at fixed `/tmp` paths before a root copy. Samba (L), dnsmasq
  (M1), Greyhole (M2), the tunnel and Tailscale (M3) no longer do: the helper writes the files.
  The Docker app installer did until P4.1 (#58), which replaced it with the helper.
- Data drives mount with PR #13's `defaults,nofail,...` options. `nosuid,nodev` would be safer for
  drives brought from another machine; share storage stays ext4 ([`storage.md`](storage.md)), so
  this can be decided now.

## Long-term (not soon)

Troy (2026-10-08): none of these are coming soon; they wait until Amahi-kai is shelf-stable and
tested.

### The phone layout

Troy will use Amahi-kai on his phone (2026-10-08). The October refresh (dark, mint, Space Grotesk)
stacks at phone width: the header's sections fold into a menu, cards and panels go one column,
and the file browser's list drops its dates. It hasn't been designed for a phone yet. To do:

- Mock up the phone screens first (the refresh's mockup is the [UI refresh canvas](https://claude.ai/artifact/1HcudH31cvF9dUzqrGGXQk)):
  the header and its menu, Setup's tab bar (it wraps), the file browser's folder view (the
  selected file's panel likely becomes a sheet from the bottom) and the share card.
- Touch: rows and buttons at least 44 px, the row's download button always shown (no hover).
- Check the water background's cost on a phone (it has a battery saver setting).

### The debug pages as a Settings tab

The debug pages (`/tab/debug`: App Logs, Logs and System Info) are from the original Amahi. They
have their own old layout, outside the October look, read logs through shell strings, and their
"Submit for Debug" button only counts log lines (the report service it sent to is gone). Troy
wants them rebuilt as a tab in Settings (2026-10-08); until then they stay as they are. To do:

- A tab on Settings in the current look, for admins, replacing `/tab/debug` and
  `layouts/debug.html.slim`.
- Amahi-kai's log, the helper's log and the system journal, read without a shell (the Logs page
  reads `/var/log/syslog`, which a journald-only system doesn't have).
- System info from System Status's sources rather than raw `/proc/cpuinfo` and `/proc/meminfo`.
- Drop Submit for Debug, or make it a download of the logs to attach to an issue.

### Long jobs in their own units

Package installs, Docker pulls and Greyhole's install run inside web requests and hold a Puma
thread while they run. System Update moved to its own job in #31; the others could follow the
same way (a systemd unit started by the helper, with its log streamed to the page). With one admin
on the NAS this costs nothing today.

### The `nobody` folder

Anonymous SMB browsing shows a `nobody` home folder (cosmetic; needs a guest account with no home
directory).

## Later: HTTPS on the LAN

Troy (2026-10-06): the web UI and every app's page are plain HTTP on the LAN, so anyone on the
network can read or change what passes (bitTube Desktop's updates come from the NAS this way:
its installers are checked against hashes from the same server). To plan as its own phase,
for Amahi-kai and its apps at once. The options:

- **A real certificate for a real name**, Let's Encrypt through a DNS challenge (amahi-kai.com is
  on Cloudflare), for a name like `nas.amahi-kai.com` that dnsmasq points at the NAS's LAN
  address: trusted by every device with nothing to install; it needs a domain per NAS, or names
  under amahi-kai.com handed out.
- **Tailscale's certificates** (`tailscale cert`, for the NAS's `*.ts.net` name): free and
  trusted, but only where Tailscale's name is used.
- **A certificate authority of the NAS's own**: works offline, but each device has to install
  and trust its root certificate.

Then: a reverse proxy in front of the web UI and the apps' ports (one place for the
certificate), and the apps (bitTube Desktop included) told the HTTPS address.

Decided (Troy, 2026-10-06): **not now**, and when it comes, **optional**. Nothing on the NAS needs
it yet (remote access is already encrypted: the Cloudflare Tunnel and Tailscale), and users mustn't
need a domain for Amahi-kai to work. So HTTPS will be a toggle that adds a front door, with plain
HTTP staying fully working underneath (it's also the way in when the internet is down and the
names don't resolve). Apps don't change; the proxy's config is generated from the installed apps;
apps that need their own address (Vaultwarden, Gitea) get it from a placeholder. To keep that
cheap, every address of Amahi-kai or an app is made in one place (`DockerApp#url`, `amahi_url`;
`spec/lib/addresses_spec.rb`). Do it when an app needs HTTPS (Vaultwarden's web vault) or other
people's networks call for it. A token for the DNS challenge mustn't be able to change
amahi-kai.com: a separate zone, or a delegated `_acme-challenge` record.

## Test on real drives (when the NAS hardware arrives)

All the hardware tests are in one checklist, to run once the SSDs are in the Jonsbo and passed
through to the NAS VM: [`docs/testing/storage-on-real-drives.md`](../testing/storage-on-real-drives.md).
It covers the disk-safety work (PR #13: fstab `nofail`, a drive missing at boot, the OS-disk
guard), Greyhole, and every storage PR (S1–S5): drive health, pools, scrubs, snapshots, a failing
drive, deleting a pool, then building the real pool.

## Storage (ZFS pools for bitShare)

Decided 2026-10-04, in [`storage.md`](storage.md): SMB shares stay on simple drives and Greyhole;
new ZFS pools, with the layout the user chooses, hold bitShare's data, on other drives; Greyhole
is basic SMB storage, changed only through Samba (the web file browser only views). Built in five
PRs (S1–S5, listed there; S1 is #44, S2 #46, S3 #50, S4 #51, S5 #53). Greyhole and shares have
been tested on the NAS's virtual drives (#79–#97); ZFS waits for the physical drives.

## Phase 4: Docker apps

Planned with Troy (2026-10-05) in [`apps.md`](apps.md): Docker only through the root helper,
apps defined by our own manifest (one container each), each app on its own port with an optional
Cloudflare Tunnel hostname (remote use required), one user and folder per app, ZFS datasets for big
data, shares read-only or read-write as chosen (never a pooled share read-write), uninstall keeps
data, a curated catalog of five apps, bitShare as an ordinary app. PRs P4.1–P4.6; P4.1 (apps through
the root helper) and P4.2 (reaching apps) are done (#58, #59), to be tested on the NAS with
[`docs/testing/apps.md`](../testing/apps.md). Tailscale is the default way to reach apps from outside (Troy,
2026-10-04), so P4.3 (Cloudflare per app) is optional and later. P4.4 (shares for apps, #60) and P4.5
(app updates, #62), P4.5b (the catalog's own repo, #70, #73) and P4.5c (apps on the LAN over mDNS,
#71, #72) are done. P4.6 (bitShare, with ZFS datasets for apps) comes after all of Amahi-kai: first
its major code work is finished (shelf-stable), then everything is tested (Troy, 2026-10-08).

## Direction

Troy's long-term aim is a self-hosted personal platform: storage, identity, permissions, apps and
eventually local AI, with system actions exposed as narrow, audited capabilities rather than root
access. That is why the helper's operations are named like an API (`users.create`,
`shares.grant`) and log every call. Build the boring, reliable pieces first.

**Router, for those who want it** (Troy, 2026-10-05): Amahi-kai can optionally act as the network's
router. Part of it exists: Network → Gateway runs DHCP and DNS (dnsmasq). The rest (the internet
connection on its own port, NAT, the firewall facing the internet) is its own feature, designed
later. Until then, other work (Phase 4's networking above all) mustn't assume the NAS is only ever a
host on someone else's LAN.
