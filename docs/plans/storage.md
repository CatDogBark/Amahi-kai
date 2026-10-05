# Storage plan

Status: decided with Troy on 2026-10-04. **Built now, before the drives are connected**, then
Phase 4, then bitShare (Troy, 2026-10-04). Each PR is checked on the NAS only for not breaking
Amahi-kai; once the SSDs are in, Troy checks their health first, then the whole storage work is
tested on the physical drives ([Tests on real drives](#tests-on-real-drives)).

## Build order

- [x] **S1.** Install ZFS (and cap its cache); create a pool in the layout chosen; pool status
  on Disks → ZFS Pools; every drive's use shown, and drives with ZFS on them kept away from
  share storage (#44).
- [x] **S2.** Health: a check every 15 minutes (`storage.check_health`, `amahi-kai-storage-check.timer`)
  of the pools and every drive's SMART data, alerts on the dashboard and Disks pages, Scrub now;
  the monthly scrub is Ubuntu's own (below) (#46).
- [x] **S3.** Replace a drive (any drive, missing or failing; ZFS resilvers onto a free disk),
  grow a pool by one group shaped like its others, destroy a pool behind its typed name (its
  drives' ZFS labels are cleared, so they're free again); new pools get `autoexpand=on` (#50).
- [x] **S4.** Snapshots (Troy, 2026-10-05: datasets move to Phase 4's app model): each pool keeps its
  newest hourly and daily snapshots (24 and 30 by default, set per pool and stored in its ZFS
  properties `amahi:snapshot-hourly` and `amahi:snapshot-daily`), taken and pruned by
  `amahi-kai-snapshots.timer`; take one now, delete, and roll the whole pool back behind its
  typed name. Only Amahi-kai's own snapshots are ever deleted or pruned (#51).
- [ ] **S5.** Greyhole handles files that don't arrive through Samba.

## Decisions

Amahi-kai has two kinds of storage, side by side. Each data drive belongs to exactly one.

1. **Share storage: simple drives and Greyhole (what exists today).** Drives with ext4, mounted at
   `/mnt/<name>`, optionally pooled with Greyhole and its copies per share. **SMB shares live only
   here.** It stays the easy home NAS that drew Troy to Amahi in the first place: mixed drive
   sizes, any device can open it. Troy keeps his general data here (pictures, videos, books,
   documents).
2. **ZFS pools (new), for bitShare.** Amahi-kai creates a pool on the drives the user assigns, and
   **the user chooses the layout** (below); Amahi-kai shows a recommendation but doesn't force it.
   More than one pool is allowed. Pools are not SMB shares: bitShare owns its data (versions,
   conflicts, locks, chunk storage), and files changed over SMB behind its back would break that.

- **One RAID engine: ZFS.** It covers the RAID levels people ask for. A second engine (mdadm,
  Btrfs) would double the setup, drive-replacement and failure handling to build and test.
- **Other Docker apps' data stays on the OS disk** (`/opt/amahi/apps`) for now. Pools are plain
  ZFS, so Phase 4 can offer an app a dataset on a pool later without a redesign.
- **Backups:** the local redundancy is the main defence. Cloud backup to Proton Drive comes later
  as an app, as redundancy on top (rclone has a Proton Drive backend, still marked beta).

## Layouts offered

When a pool is created, Amahi-kai lists the layouts the chosen drives allow, each with its usable
space and how many drives may fail.

| Layout | Like | Minimum drives | Survives |
| --- | --- | --- | --- |
| Mirror | RAID 1 | 2 | All drives but one |
| Striped mirrors | RAID 10 | 4 | One drive per pair |
| RAIDZ1 | RAID 5 | 3 | 1 drive |
| RAIDZ2 | RAID 6 | 4 | 2 drives |
| RAIDZ3 | — | 5 | 3 drives |

A pool grows by adding another group of drives with the same layout (another mirror pair, or
another RAIDZ group). Ubuntu 24.04 ships OpenZFS 2.2, which can't add a single drive to an existing
RAIDZ group (that came in 2.3); the UI should say so when it matters.

## Troy's first build

- Jonsbo N3, 8 hot-swap bays, as the Proxmox host. **The drive controller (HBA) is passed through
  to the Amahi-kai VM**, so Amahi-kai sees the real disks and owns them (ZFS needs direct access
  for its health and SMART data). That needs a motherboard with IOMMU and a free slot for the HBA:
  check before buying the board.
- **4 matched SATA SSDs, about 1 TB each**, bought together; 4 bays left for later.
- Suggested pool for those 4: **RAIDZ1** (about 3 TB usable, survives one drive), grown later with
  a second 4-drive RAIDZ1 (about 6 TB). Matching how drives get bought (4 at a time) avoids the
  2.2 limit above. Striped mirrors (about 2 TB, grows in pairs) is the alternative.
- **Give the NAS VM 8 GB of RAM** (the host has 16). Cap ZFS's cache (ARC) at about 2 GB.

## What gets built

Everything that touches drives goes through the root helper (`libexec/amahi-helper`), as
operations with their own validation and logging.

- **Install ZFS** (`zfsutils-linux`) on request, like Greyhole and Docker today.
- **Create a pool:** pick unmounted data drives (never the OS disk, never a drive already used by
  share storage), pick a layout, confirm wiping them. Created with `ashift=12`, `compression=lz4`,
  and `autotrim=on` for SSDs, and imported at every boot. Pools mount at `/srv/pools/<name>`,
  not under `/mnt`, so the helper never accepts a share folder on one. The drives are named by
  their `/dev/disk/by-id` links (model and serial), so a failed one can be found in its bay.
- **Pool status:** health, capacity, each drive's state, the last scrub and its result.
- **Alerts** on the dashboard and Disks pages when a pool is degraded or faulted, a scrub found
  errors, or a drive's SMART data looks bad.
- **Scrubs:** Ubuntu's ZFS package already scrubs every healthy pool on the second Sunday of
  each month (`/etc/cron.d/zfsutils-linux`; a pool's `org.debian:periodic-scrub` property turns it
  off), so Amahi-kai shows when that runs next instead of adding a second schedule, plus "Scrub
  now".
- **Health check:** every 15 minutes the helper reads the pools and each drive's SMART data
  (`smartctl --json`, `-n standby` so sleeping drives stay asleep) into
  `/var/lib/amahi-kai/storage-health.json`; the app's alerts read that file. smartmontools comes
  with ZFS, installed without its recommends (they'd bring a mail server).
- **Replace a drive:** for a failed or failing drive, pick the new one, then show the resilver's
  progress.
- **Grow a pool:** add a group with the same layout.
- **Snapshots:** automatic, with configurable retention (hourly kept a day, daily kept a month by
  default), plus a list. Snapshots are taken with `-r`, so datasets added later are covered.
  Restoring single files, or bitShare's own data, is bitShare's job, so it is designed with
  bitShare; Amahi-kai rolls back a whole pool.
- **Datasets** (moved to Phase 4, Troy 2026-10-05): one per user of the pool (first `bitshare`),
  created by the app model when an app needs storage, so an app gets exactly its own dataset.
- **Destroy a pool:** behind a typed confirmation.
- **Drive ownership:** the Disks page shows which drives are share storage and which belong to a
  pool, and neither side can take the other's drives. A drive with any ZFS label is never
  formatted or mounted as share storage; one with a label from a pool that isn't imported here
  can go into a new pool, which erases it.

### Greyhole: files that don't arrive through Samba

Greyhole only notices files written through Samba (its Samba module logs each change). A file
uploaded with the web file browser, or written into a share folder by an app, goes straight onto
disk: Greyhole doesn't spread it across drives or make its copies, even for a share set to 2
copies.

Requirement (Troy, 2026-10-04): **Greyhole handles those files like Samba writes.** Check how
Greyhole can be told about a file it didn't see (from its own documentation and code) and use that
for every upload, or else run Greyhole's check over pooled shares on a schedule. Cover it with
specs, and test it on the real drives.

## Tests on real drives

Also in the roadmap's hardware checklist. First, check each SSD's health (`smartctl -a`: power-on
hours, wear, reallocated sectors, firmware) before it goes in a pool.

- Install ZFS from Disks → ZFS Pools; the cache limit is set (`/sys/module/zfs/parameters/zfs_arc_max`).
- The SSDs' SMART data shows on ZFS Pools (model, firmware, wear, hours), matching `smartctl -a`.
- Pulling a drive shows on the dashboard within 15 minutes (or at once with Check now).
- Create a RAIDZ1 pool from the 4 SSDs; it survives a reboot (imported at boot).
- Pull a drive: the pool shows degraded and the alert appears; replace it and watch the resilver.
- Run a scrub; take a snapshot and roll a test dataset back.
- Grow a test pool by a second group; delete a test pool, and its drives show as free and can be
  formatted for share storage.
- Share storage (Greyhole) on the other drives works next to the pool, and neither offers the
  other's drives.
- A file uploaded through the web file browser to a share with 2 copies ends up with 2 copies.

## Open questions

- Which drives go to the pool and which to Greyhole on the first build (the 4 SSDs, plus what
  later?).
- How bitShare gets its dataset and permissions: decided in the Phase 4 app model.
- Share-storage drives still mount with `defaults,nofail,...`; whether to add `nosuid,nodev`
  (safer for drives brought from another machine) can be decided now that share storage stays
  ext4.
