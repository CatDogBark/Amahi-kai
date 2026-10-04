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

- The per-IP login throttle (`config/initializers/rack_attack.rb`) trusts forwarded addresses from
  private ranges, so it's weaker on the LAN than it looks. The per-username limit holds.
- Several features staged files at fixed `/tmp` paths before a root copy. Samba (L), dnsmasq
  (M1), Greyhole (M2), the tunnel and Tailscale (M3) no longer do: the helper writes the files.
  The Docker app installer still does (Phase 4).
- `spec/requests/apps_controller_spec.rb` "handles errors gracefully" fails when that file runs
  alone (on `main` too) and passes in the full suite: `docker_apps` doesn't rescue the error the
  spec raises. Fix the spec or the action.
- `UsersController#create` answers a JSON request with a template that doesn't exist (500). The
  Users page posts the form as HTML, so only API-style callers hit it.
- Static DHCP hosts (Network → Hosts) are saved and restart dnsmasq, but nothing writes them into
  dnsmasq's config (no `dhcp-host` lines), so they have no effect.
- Re-running the setup wizard's storage step clears the whole pool list
  (`lib/setup_service.rb`, `DiskPoolPartition.destroy_all`).
- Duplicates: share toggles live in both `SharesController` and `ShareAccessManager`.
- Data drives mount with PR #13's `defaults,nofail,...` options. `nosuid,nodev` would be safer for
  drives brought from another machine; decide with the filesystem (below).
- Per-request overhead: 4–5 `Setting` queries in `before_action_hook`.
- Long jobs (package installs, docker pull) run inside web requests and hold Puma threads.
  System Update moved to its own job in #31; the others could follow the same way (a systemd
  unit started by the helper, with its log streamed to the page).
- 26 locale files, but newer screens hardcode English. Troy to decide whether i18n stays a goal.
- Anonymous SMB browsing shows a `nobody` home folder (cosmetic; needs a guest account with no home
  directory).
- Not yet tried in the UI because no shares or apps exist: file upload, raw preview, the app proxy.

## Test on real drives (when the NAS hardware arrives)

VM 104's disks belong to Proxmox, so the disk-safety work (PR #13) is covered by specs only.

- [ ] Format and mount a data drive from Disks; its `/etc/fstab` line ends
  `defaults,nofail,x-systemd.device-timeout=10s 0 2`.
- [ ] Reboot with one data drive unplugged: the NAS boots normally and the other drives mount.
- [ ] Plug it back in: it mounts at its old `/mnt/storage-N`, and a new drive gets the next slot.
- [ ] Boot from NVMe: Disks marks the NVMe as the OS disk and refuses to format or mount its
  partitions.
- [ ] Re-run `bin/amahi-install`: users, shares and settings survive.
- [ ] Greyhole pool and Samba binding on the same drives.
- [ ] Preview an unmounted drive from Disks; install Greyhole from the setup wizard.

Decide the filesystem before the drives are filled: today it's ext4 + Greyhole, which can't take
snapshots. **RAID** is a future feature to decide with it: Troy wants the setup wizard to set up
either basic Greyhole pooling or RAID for a basic file NAS (2026-10-04). Nothing in the code
builds RAID today (mdadm, or a filesystem's own redundancy such as btrfs or ZFS).

## Phase 4: Docker apps

Starts with a design doc for the Docker app model, so built-in apps (bitShare first) follow it:

- each app on its own port and tunnel hostname; retire the `/app/<id>` proxy (it buffers whole
  bodies and shares the Amahi origin)
- which apps the LAN can reach and which stay local-only; Docker network access stays opt-in
- secrets generated per install (the catalog ships default passwords today); image versions pinned
- data kept on uninstall; the shares each app may see chosen per app, read-only or read-write;
  no `chmod 777`
- a clear warning that access to the Docker socket is full control of the NAS
- how bitShare authenticates (open)

## Direction

Troy's long-term aim is a self-hosted personal platform: storage, identity, permissions, apps and
eventually local AI, with system actions exposed as narrow, audited capabilities rather than root
access. That is why the helper's operations are named like an API (`users.create`,
`shares.grant`) and log every call. Build the boring, reliable pieces first.
