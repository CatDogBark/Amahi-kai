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

## Next: Phase 3

Decisions already made: Ruby stays on Ubuntu 24.04's patched 3.2; `main` stays the release until
shares are tested on real drives, then tagged releases and an updater change; the codebase
becomes root-owned (in N); Docker app work moves to Phase 4.

- [ ] **M. Privileged helper, part 2**, in three PRs (Troy, 2026-10-04); design in
  [`privileged-helper.md`](privileged-helper.md):
  - [x] **M1.** Settings → Servers, reboot and power off, hostname, dnsmasq and DNS aliases,
    swap (#26).
  - [x] **M2.** Data drives and fstab (keeping the PR #13 rules exactly), Greyhole config,
    database and install (one install path instead of three); 26 sudo rules gone (#27).
  - [ ] **M3.** Package installs from pinned apt repositories and a fixed list, Cloudflare
    Tunnel, Tailscale (its apt repository instead of a downloaded install script run as root),
    Docker's install, and the security audit's fixes with P below; 42 sudo rules gone, leaving
    the helper, the updater and Docker. Built; waiting for the NAS check.
- [ ] **N. Root-owned install**: sudoers down to the helper, the updater and Docker;
  `/opt/amahi-kai` owned by root; `amahi-update` runs Rails tasks (`bundle`, migrations, asset
  build) as `amahi`. Rewrite `docs/security/PRIVILEGE-ESCALATION-MITIGATION.md`, which is out of
  date, to describe the helper.
- [ ] **O. Update rollback**: keep the previous release; if migrations, the asset build or the
  health check fail, switch back and restart.
- [ ] **P. Security audit fixes** (in M3; `lib/security_audit.rb`): read effective SSH settings with
  `sshd -T` (drop-ins in `sshd_config.d` win over `sshd_config`); warn that Docker-published ports
  bypass UFW; make the "tunnel blocked until the audit passes" rule a server-side check, not just
  a hidden button. Built with M3; the firewall fix also opens DNS and DHCP once dnsmasq is
  configured, and the SSH password fix needs a key first.
- [ ] **Q. Replace `sassc`** (LibSass is unmaintained) with `dartsass-rails` or Propshaft and plain
  CSS. A real Content-Security-Policy (today it's report-only) is a stretch goal.

## Open, not yet scheduled

Smaller findings from the review that no PR covers yet. Fold them into a nearby PR when it
touches the same code.

- The seeded admin password works until someone changes it; `setup/finish` should refuse to
  complete until it's changed.
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
- Long jobs (apt, docker pull, system update) run inside web requests and hold Puma threads;
  consider a job runner or `systemd-run` with a streamed log.
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
