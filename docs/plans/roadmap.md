# Fix plan and roadmap

Status as of 2026-10-04. Each phase came from a full code review (October 2026; the detailed
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
| Fix. Times that stay current | "… ago" times (update check, System Status, pool health, snapshots, Jobs) are worked out again every minute and when a dialog opens (time_ago.js), instead of only when the page loaded; the update check shows its time of day | #61 |
| Phase 4 P4.4. Shares for apps | Shares chosen at install and changed later, at `/shares/<name>`, found by name in smb.conf by the helper; read only unless the app writes shares and Greyhole doesn't pool the share (pooled shares bring their copy folders, read only); default ACLs keep what apps write editable over SMB; images aren't downloaded again. ZFS datasets for apps moved to P4.6. Not yet tested on the NAS | #60 |

## Next: Phase 3

Decisions already made: Ruby stays on Ubuntu 24.04's patched 3.2; `main` stays the release until
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
  pixel for pixel, live numbers aside. Theme sources are rebuilt by hand with Dart Sass
  (`public/themes/README.md`). Sprockets stays; Propshaft can come later.
- [ ] **Content-Security-Policy**: today it's report-only. Enforcing it needs the inline
  scripts and `onclick` handlers moved into the JavaScript files first; its own PR.

## Open, not yet scheduled

Smaller findings from the review that no PR covers yet. Fold them into a nearby PR when it
touches the same code.

- Several features staged files at fixed `/tmp` paths before a root copy. Samba (L), dnsmasq
  (M1), Greyhole (M2), the tunnel and Tailscale (M3) no longer do: the helper writes the files.
  The Docker app installer did until P4.1 (#58), which replaced it with the helper.
- Duplicates: share toggles live in both `SharesController` and `ShareAccessManager`.
- Data drives mount with PR #13's `defaults,nofail,...` options. `nosuid,nodev` would be safer for
  drives brought from another machine; share storage stays ext4 ([`storage.md`](storage.md)), so
  this can be decided now.
- Per-request overhead: 4–5 `Setting` queries in `before_action_hook`.
- Long jobs (package installs, docker pull) run inside web requests and hold Puma threads.
  System Update moved to its own job in #31; the others could follow the same way (a systemd
  unit started by the helper, with its log streamed to the page).
- Anonymous SMB browsing shows a `nobody` home folder (cosmetic; needs a guest account with no home
  directory).
- Not yet tried in the UI because no shares or apps exist: file upload, raw preview, the app proxy.

## Test on real drives (when the NAS hardware arrives)

All the hardware tests are in one checklist, to run once the SSDs are in the Jonsbo and passed
through to the NAS VM: [`docs/testing/storage-on-real-drives.md`](../testing/storage-on-real-drives.md).
It covers the disk-safety work (PR #13: fstab `nofail`, a drive missing at boot, the OS-disk
guard), Greyhole, and every storage PR (S1–S5): drive health, pools, scrubs, snapshots, a failing
drive, deleting a pool, then building the real pool.

## Next: Storage (ZFS pools for bitShare)

Decided 2026-10-04, in [`storage.md`](storage.md): SMB shares stay on simple drives and Greyhole;
new ZFS pools, with the layout the user chooses, hold bitShare's data, on other drives; Greyhole
is basic SMB storage, changed only through Samba (the web file browser only views). Built now in five PRs (S1–S5,
listed there; S1 is #44, S2 #46, S3 #50, S4 #51, S5 #53), then Phase 4, then bitShare. Tested on the physical drives once
they're connected.

## Phase 4: Docker apps

Planned with Troy (2026-10-05) in [`apps.md`](apps.md): Docker only through the root helper,
apps defined by our own manifest (one container each), each app on its own port with an optional
Cloudflare Tunnel hostname (remote use required), one user and folder per app, ZFS datasets for big
data, shares read-only or read-write as chosen (never a pooled share read-write), uninstall keeps
data, a curated catalog of five apps, bitShare as an ordinary app. PRs P4.1–P4.6; P4.1 (apps through
the root helper) and P4.2 (reaching apps) are done (#58, #59), to be tested on the NAS with
[`docs/testing/apps.md`](../testing/apps.md). Tailscale is the default way to reach apps from outside (Troy,
2026-10-04), so P4.3 (Cloudflare per app) is optional and later. P4.4 (shares for apps, #60) and P4.5
(app updates, #62) are done; P4.6 (bitShare, with ZFS datasets for apps) is next.

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
