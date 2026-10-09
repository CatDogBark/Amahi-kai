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
- [x] **S5.** The web file browser only views and downloads (Troy, 2026-10-05), so every change
  to a share goes through Samba and Greyhole needs no special handling; pooled files preview and
  download, and folder zips work (#53).

## Decisions

Amahi-kai has two kinds of storage, side by side. Each data drive belongs to exactly one.

1. **Share storage: simple drives and Greyhole (what exists today).** Drives with ext4, mounted at
   `/mnt/<name>`, optionally pooled with Greyhole and its copies per share. **SMB shares live only
   here.** It stays the easy home NAS that drew Troy to Amahi in the first place: mixed drive
   sizes, any device can open it. Troy keeps his general data here (pictures, videos, books,
   documents).
2. **ZFS pools (new).** Amahi-kai creates a pool on the drives the user assigns, and
   **the user chooses the layout** (below); Amahi-kai shows a recommendation but doesn't force it.
   More than one pool is allowed. bitShare's data gets a dataset of its own and is never an SMB
   share: bitShare owns its data (versions, conflicts, locks, chunk storage), and files changed
   over SMB behind its back would break that.
   - **SMB shares on a pool** (Troy, 2026-10-09): a share can live on a pool, in the pool's
     `shares` dataset (`/srv/pools/<pool>/shares/<name>`), chosen under Where when it's made. It's
     never also a Greyhole share, and it stays on its pool. The Shares list shows where each share
     lives (System disk, Greyhole, ZFS), and a pool with shares on it isn't taken offline or
     destroyed. Simple SMB access to a pool, with bitShare as the layer on top for sync.

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

- [x] **Controls** (Troy, 2026-10-07): Greyhole and ZFS install and uninstall from their own
  pages, Greyhole starts and stops there, and ZFS pools go offline and come back one at a time
  (`pools.export` records the pool's GUID in `/var/lib/amahi-kai/offline-pools.json`, which
  keeps its drives its own; `pools.import` brings back only those). Uninstalling is offered
  only once nothing uses it.

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
  `setuid=off`, `devices=off` (apps' datasets inherit them), and `autotrim=on` for SSDs, and imported at every boot. Pools mount at `/srv/pools/<name>`,
  not under `/mnt`; the helper accepts a share folder on one only in its `shares` dataset. The drives are named by
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

### Greyhole: only basic SMB storage

Greyhole only notices changes made through Samba: its Samba module drops a note in
`/var/spool/greyhole` for each file written, renamed or deleted, and the daemon turns the notes into
tasks. A file written into a share's folder any other way gets its copies only at Greyhole's weekly
`--fsck` (which queues the same write task Samba would); a delete or rename made any other way
leaves Greyhole's copies and records behind.

The first idea (2026-10-04) was to tell Greyhole about the web file browser's changes. Decided
instead (Troy, 2026-10-05): **Greyhole is basic SMB mass storage with simple redundancy, and is
treated as nothing more.**

- The web file browser only views and downloads (S5). Files change over SMB, so every change
  goes through Samba and Greyhole needs nothing special.
- Apps don't write into pooled shares: an app that writes its own data gets a ZFS dataset (Phase 4)
  or a share that isn't pooled. If an app ever needs Greyhole, that's handled with that app.
- Research kept for then: `greyhole --fsck --dir=<folder>` queues write tasks for plain files in a
  folder; `greyhole --cp` copies a file onto the pool directly (synchronously, as the caller's
  user); the spool note format (`unlink`, `rmdir`, `rename`: the action, the share, the path(s), a
  blank line) has been the same in Greyhole's Samba modules from 4.5 to 4.22.

## Tests on real drives

The checklist is [`docs/testing/storage-on-real-drives.md`](../testing/storage-on-real-drives.md):
the drives' health first, then share storage and Greyhole on two SSDs next to a ZFS test pool on
the other two, then the real 4-drive pool. Tests that need more hardware (a spare drive, 4 more
drives, a machine booting from NVMe) are listed at its end.

## Open questions

- Which drives go to the pool and which to Greyhole on the first build (the 4 SSDs, plus what
  later?).
- How bitShare gets its dataset and permissions: decided in the Phase 4 app model.
- Share-storage drives still mount with `defaults,nofail,...`; whether to add `nosuid,nodev`
  (safer for drives brought from another machine) can be decided now that share storage stays
  ext4.
