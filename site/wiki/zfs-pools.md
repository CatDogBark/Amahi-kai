---
layout: default
title: "ZFS Pools"
---

# ZFS Pools

A ZFS pool keeps data safe across several drives, like RAID: when a drive fails, the pool keeps
working and nothing is lost, and you replace the drive from the web UI. Pools also take hourly and
daily snapshots you can roll back to, and check every block of their data for damage.

Pools are on **Setup → Disks → ZFS Pools**. A share can live on one (see
[File Sharing](file-sharing#where-a-share-lives)), and bitShare keeps its data on one. Each drive
belongs either to a pool or to share storage (**Devices** and the Greyhole pool, see
[Storage Pooling](storage-pooling)), never both.

---

## Installing ZFS

ZFS isn't installed until you need it. **Install ZFS** on the ZFS Pools page installs Ubuntu's own
ZFS package, and smartmontools to watch the drives' health. ZFS uses spare memory as a cache;
Amahi-kai limits that cache to 2 GB (half the memory on a server with less than 4 GB). ZFS always
keeps a 32nd of the memory for it, so on a server with more than 64 GB the limit is just above that.

**Uninstall ZFS**, at the bottom of the page, is offered once there's no pool left, online or
offline.

---

## Creating a pool

1. Under **Create a pool**, tick the drives. Only free drives can be ticked: never the system disk,
   share storage or another pool's drives. A free drive that still has files on it says what's
   there, since the pool erases it. A drive mounted for share storage on **Disks → Devices**
   isn't free, nor is one in share storage that isn't mounted just now (it came back unmounted:
   mount it again on Devices); leave the drives for a pool unmounted there. If one is mounted and nothing is on it,
   **Free this drive** in its row here unmounts it (a pool made with it erases it). A drive in
   share storage that holds files, a share's folder or the Greyhole pool says why it can't be freed.
2. Choose a **Layout**. The page suggests one for the drives you ticked, and shows the space each
   layout gives and how many drives can fail.
3. Give it a **Name** (lowercase letters, digits, `_` and `-`). It's mounted at
   `/srv/pools/<name>`.
4. Tick **Erase everything on the chosen drives**, and click **Create pool**.

| Layout | Like | Drives | Can lose | Space |
| --- | --- | --- | --- | --- |
| Mirror | RAID 1 | 2 or more | All but one | One drive's |
| Striped mirrors | RAID 10 | 4 or more, in pairs | One per pair | Half |
| RAIDZ1 | RAID 5 | 3 or more | 1 | All but one drive's |
| RAIDZ2 | RAID 6 | 4 or more | 2 | All but two drives' |
| RAIDZ3 | | 5 or more | 3 | All but three drives' |

Use drives of the same size: a pool treats each one as the size of the smallest.

A new pool compresses its data (lz4), trims its drives when they're all SSDs, and is opened again
at every boot. Programs on it
can't run with extra privileges. Its drives are named by their model and serial, so a failed one
can be found in its bay.

---

## The pool's card

Each pool has a card with its layout, health (**ONLINE** when all is well), the space used and
free, and the last scrub. Under it, each drive's state, its health (SMART) and its read, write and
checksum errors.

**Shares on this pool** lists the shares that live on it, and **Apps keeping their data here** the
apps whose data is on it (see [Docker Apps](docker-apps#apps-that-keep-their-data-on-a-zfs-pool)).
While a share is there, or an installed app keeps its data there, the pool can't be taken offline
or deleted.

### When a drive fails or goes missing

The pool turns **DEGRADED**, and a warning at the top of the dashboard and the Disks pages names
the drive and says what to do. The pool keeps working on the drives it has left.

- **The drive is connected again** (a loose cable, a drive pulled and put back): ZFS keeps it out
  of the pool until you click **Bring online** on its row. It then copies over what changed while
  the drive was out (a resilver).
- **It was already missing when the server started:** ZFS shows it by a number, not its name.
  Connect it again and restart the server, and the pool finds it.
- **It's dead or dying:** click **Replace** on its row (below).

### Replacing a drive

**Replace** on a drive's row asks for the new drive, which must be free and at least as big, and
**Erase everything on the new drive** to be ticked, since it's wiped first. ZFS copies the pool's data onto the
new drive while the pool stays usable, and keeps using the old drive, if it's still there, until
it's done. The page updates every 30 seconds while it runs.

The old drive then leaves the pool and shows under **Create a pool** as **Free: replaced out of the
pool**. It still has an old ZFS label, which share storage won't touch: **Erase** next to it clears
the label, and the drive can go on **Devices** like any other. (A new pool erases the label itself.)
**Erase** also clears a leftover label from a pool that isn't on this server. A drive whose pool ZFS
can still find is kept for that pool instead (see [Pools found on the drives](#pools-found-on-the-drives)).

Replacing every drive with a bigger one, one at a time, grows the pool.

### Adding drives

**Add drives** grows the pool by one more group shaped like its others: a RAIDZ1 pool of 4 drives
takes 4 more for a second RAIDZ1 group. A group can't be taken out of a pool again.

### Scrubs

A scrub reads every block in the pool and repairs anything damaged from the pool's redundancy.
Ubuntu's ZFS package scrubs every pool on the second Sunday of each month; the card says when the
next one is, and **Scrub now** starts one. A warning comes up if a scrub repaired damage or found
some it couldn't repair.

### Drive health

Every 15 minutes, Amahi-kai checks the pools and each drive's SMART data (sleeping drives are left
asleep). A drive that says it's failing, has bad sectors or errors, or is worn out gets a warning
at the top of the dashboard and the Disks pages. **Check now** checks at once. Virtual disks (a
server in a virtual machine) have no SMART data.

---

## Snapshots

A snapshot is the whole pool as it was at one moment. It takes no time to make, and uses space
only for what changes after it.

- **Automatic:** one every hour and one every day. **Keep the newest** sets how many of each the
  pool keeps (24 hourly and 30 daily to begin with): the oldest goes when there are more. 0 turns
  that kind off and removes its snapshots.
- **Take snapshot now** takes one that's kept until you delete it.
- **Show the snapshots** lists them, with the space each one holds on its own. **Delete** removes
  one.
- **Roll back** puts the whole pool, and the shares and apps' data on it, back to how it was then.
  Everything changed since is lost, and so are the snapshots taken after it. The apps keeping
  their data on the pool are stopped while it rolls back, then started again. Type the pool's name
  to confirm.

The page only rolls back or deletes Amahi-kai's own snapshots. Their names give when they were
taken in UTC (the list shows the time in your time zone).

---

## Taking a pool offline, and deleting one

- **Take offline** unmounts the pool and stops using it. It stays offline after a restart, and its
  drives stay its own: nothing can format them or put them in another pool. Computers with its
  files open over the network are disconnected first. **Bring online** on its card opens it again.
- **Delete pool** destroys the pool and everything on it, snapshots included. Its drives are wiped
  and become free for share storage or a new pool. Type the pool's name to confirm. This can't be
  undone.

Neither works while shares are on the pool, or an installed app keeps its data there: delete the
shares on **Shares**, or uninstall the app on **Apps**, first.

---

## Pools found on the drives

A pool on drives connected to the server that isn't open (imported) gets a card of its own, **On
the drives, not imported**: the server's own pool after Amahi-kai was installed again, one whose
drives came too late when the server started, or a pool from another server.

- **Import** opens it again at `/srv/pools/<name>`, if it's a pool Amahi-kai made. Any other is
  left on its drives as it was: import it from the command line. ZFS can't import a pool with too
  many of its drives missing; connect them first.
- Its drives are kept for it: nothing can format them or put them in another pool. To use one for
  something else, click **Erase…** on its row and type the pool's name. With too many of its drives
  erased, the pool and everything on it are gone.

## Pools Amahi-kai didn't make

A server that runs from ZFS has pools of its own (bpool and rpool). The page shows them, marked
**Not Amahi-kai's**, with nothing that changes them: manage them from the command line. Shares
and apps can't go on them, and Amahi-kai takes no snapshots of them.

---

## From the command line

ZFS's own commands show the same thing the page does. Make changes in the web UI, so Amahi-kai
keeps track of them.

```bash
zpool status -P                      # each pool's health, drives and last scrub
zpool list                           # each pool's size and space used
zfs list -t snapshot                 # the snapshots
systemctl list-timers amahi-kai-snapshots.timer      # snapshots, every hour
systemctl list-timers amahi-kai-storage-check.timer  # pool and drive health, every 15 minutes
```
