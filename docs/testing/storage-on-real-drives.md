# Storage tests on real drives

Everything in the storage work (share storage, Greyhole, ZFS pools, drive health, snapshots) was
built and checked with specs before the drives arrived. This is the list to run once the SSDs are
in the Jonsbo and passed through to the NAS VM. Tick each box as it passes; if one doesn't, stop
there and send Claude what the page shows plus the output of the
[commands at the end](#if-something-fails).

The order uses the 4 SSDs for everything: two for share storage with Greyhole, two for a ZFS
**test** pool next to them, then both torn down and the real 4-drive pool built. The test data
is thrown away, so use files you have copies of.

Drive names below (`/dev/sdb` and so on) are examples: use the names `lsblk` shows. Run each
command on its own.

---

## 1. Before you start

- [ ] In Proxmox, the NAS VM (104) has **8 GB of RAM** and the drive controller (HBA) is passed
  through to it.
- [ ] The VM sees the 4 SSDs (model and serial on each line):

  ```bash
  lsblk -o NAME,MODEL,SERIAL,SIZE,TYPE,MOUNTPOINTS
  ```

- [ ] **Settings → System Status** says **Up to date**.
- [ ] **Dashboard → Services**: **SMART monitoring** is **Running** (it was Idle on the VM's
  virtual disk). If it says Idle, reboot the VM once: smartd only starts at boot.

## 2. Drive health, before using the drives

- [ ] For each SSD, read its SMART data:

  ```bash
  sudo smartctl -a /dev/sdb
  ```

  Send Claude, per drive: power-on hours, `Wear_Leveling_Count` (its value column), reallocated
  sectors (`Reallocated_Sector_Ct` raw value), `Current_Pending_Sector`, `Offline_Uncorrectable`,
  and the firmware version. These are used drives: anything worn or with bad sectors gets
  replaced before it holds data.
- [ ] **Disks → ZFS Pools**: click **Check now**. Each SSD's **Health** shows **OK** with its wear,
  hours and firmware, matching `smartctl`. A drive with reallocated sectors shows **Check** and
  the dashboard shows an alert.
- [ ] **Disks → Devices**: each SSD has a **SMART OK** badge with the same details.

## 3. Share storage on two drives

Use two of the SSDs (here `/dev/sdb` and `/dev/sdc`).

- [ ] **Disks → Devices**: **Initialize** each one (ext4), then **Mount** it. They mount at
  `/mnt/storage-1` and `/mnt/storage-2`.
- [ ] Their fstab lines end `defaults,nofail,x-systemd.device-timeout=10s 0 2`:

  ```bash
  grep /mnt /etc/fstab
  ```

- [ ] **Preview** works: **Unmount** one, click **Preview** (it lists the top folders, read-only),
  then **Mount** it again. It goes back to the same `/mnt/storage-N`.
- [ ] **Disks → ZFS Pools**: both show as **Share storage (/mnt/storage-N)**, with no checkbox.

## 4. Greyhole on those two drives

- [ ] **Disks → Storage Pool → Install Greyhole**. The install window ends with ✓, and the
  dashboard's Services list Greyhole as Running.
- [ ] Turn both drives on for the pool, and make a test share with **2 copies**.
- [ ] Copy a few files into the share **over SMB** (from your PC). Within a few minutes Greyhole
  has spread them, with a copy of each on both drives:

  ```bash
  sudo greyhole --view-queue
  ```

  ```bash
  sudo ls -l /mnt/storage-1/<Share>
  ```

  ```bash
  sudo ls -l /mnt/storage-2/<Share>
  ```

- [ ] **Browse** the share in the web UI: the files list, **images, video and audio preview**,
  **Download** works, and **Download this folder** gives a zip that opens. There's no Upload,
  New Folder, Rename or Delete.
- [ ] Samba still answers on the LAN only (the security audit's **Samba bound to LAN** check
  passes), with Greyhole's settings in place.

## 5. A drive missing at boot

- [ ] Shut the VM down, pull the `/mnt/storage-2` drive, and start the VM. It boots normally
  (no emergency shell), `/mnt/storage-1` is mounted, and the pooled share still opens.
- [ ] Shut down, put the drive back, start. It mounts at `/mnt/storage-2` again.

## 6. A ZFS test pool next to share storage

Use the other two SSDs (here `/dev/sdd` and `/dev/sde`).

- [ ] **Disks → ZFS Pools**: only these two are offered. The share-storage drives and the system
  disk have no checkbox.
- [ ] Tick both. **Mirror** is the only layout offered (with about 930 GB usable). Name it `test`,
  tick **Erase everything on the chosen drives**, and **Create pool**. The card shows `test`,
  **ONLINE**, **Mirror · 2 drives**, each drive by model and serial, mounted at `/srv/pools/test`.
- [ ] ZFS made it the way Amahi-kai asked:

  ```bash
  zpool status test
  ```

  ```bash
  zpool get ashift,autoexpand,autotrim test
  ```

  ```bash
  zfs get compression,mountpoint,amahi:snapshot-hourly,amahi:snapshot-daily test
  ```

  Expect `ashift 12`, `autoexpand on`, `autotrim on`, `compression lz4`, mountpoint
  `/srv/pools/test`, snapshots `24` and `30`.
- [ ] ZFS's memory cache is capped at 2 GB (`2147483648`):

  ```bash
  cat /sys/module/zfs/parameters/zfs_arc_max
  ```

- [ ] **Disks → Devices**: the two pool drives show **ZFS pool test** and no Initialize or Mount
  buttons. The setup wizard's storage step doesn't offer them either.
- [ ] Reboot the VM: the pool comes back **ONLINE** by itself.

## 7. Scrubs and the health check

- [ ] **Scrub now**: the button says Scrubbing…, the page updates itself every 30 seconds, and the
  card ends with "Scrub repaired 0B … with 0 errors".
- [ ] The card says when the next automatic scrub is (the second Sunday of the month).
- [ ] **Settings → Jobs**: **Storage health check**, **Pool snapshots** and **Pool scrub** are
  listed, the first two **OK**.

## 8. Snapshots

- [ ] Within an hour of creating the pool, its **Snapshots** section lists an hourly and a daily
  snapshot:

  ```bash
  zfs list -t snapshot -r test
  ```

- [ ] Roll back works. Make a file, take a snapshot, make another file:

  ```bash
  sudo touch /srv/pools/test/before.txt
  ```

  Then **Take snapshot now** on the card, and:

  ```bash
  sudo touch /srv/pools/test/after.txt
  ```

  **Roll back** the snapshot you just took (type `test`): `before.txt` is still there and
  `after.txt` is gone.

  ```bash
  ls /srv/pools/test
  ```

- [ ] **Delete** a snapshot: it leaves the list.
- [ ] Set **Keep 2 hourly**, **Save**: there are never more than 2 hourly snapshots (the extras go
  at once, and after each hourly run).

## 9. A failing drive

- [ ] Pull one of the test pool's drives while the VM runs. Within 15 minutes, or at once with
  **Check now**:
  - the dashboard and every Disks page show **Pool test is DEGRADED**, with ZFS's advice
  - the drive is **UNAVAIL**, or shows as missing, with its **Replace** button highlighted
- [ ] Put the drive back. ZFS brings it back. If it doesn't within a minute, bring it online:

  ```bash
  sudo zpool online test /dev/sde
  ```

  The pool resilvers (the page updates every 30 seconds) and goes back to **ONLINE**, and the
  alert clears.

## 9a. Taking a pool offline

- [ ] **Take offline** on `test`: the card moves to an Offline card with **Bring online**, its two
  drives show as **ZFS pool test (offline)**, and they aren't offered for a new pool.
- [ ] Reboot the VM: `test` is still offline.
- [ ] **Bring online**: the pool comes back **ONLINE**, mounted at `/srv/pools/test`, with its
  files and snapshots.



- [ ] **Delete pool** on `test` (type `test`): the pool is gone, `/srv/pools/test` is gone, and its
  two drives show as **Free** on ZFS Pools and as plain drives on Devices (Initialize offered).
- [ ] Remove the Greyhole test share, turn both drives off in **Disks → Storage Pool**, and
  **Unmount** them on **Devices**. Their fstab lines are gone. Greyhole can stay installed for
  the drives you'll add later.
- [ ] Optional: with the drives out of its pool and no share keeping copies, **Uninstall** on
  Disks → Storage Pool removes Greyhole (the dashboard's Services no longer list it); Install
  Greyhole puts it back. With no pool left, **Uninstall ZFS** on ZFS Pools does the same for
  ZFS, and Install ZFS puts it back.

## 11. The real pool

- [ ] **Disks → ZFS Pools**: all 4 SSDs are **Free**. Tick them: **RAIDZ1** is **suggested**, with
  about 2.7 TB usable, and it survives one drive failing.
- [ ] Create it with the name you want to keep. It shows **ONLINE**, **RAIDZ1 · 4 drives**, keeping
  24 hourly and 30 daily snapshots.
- [ ] Reboot once more: it comes back **ONLINE**.

---

## Later, when there's more hardware

- [ ] **Replace a drive** (needs a spare drive at least as big as the SSDs): **Replace** on a pool
  drive, choose the spare, tick erase. The resilver runs with the pool still usable, and the old
  drive leaves the pool.
- [ ] **Grow the pool** (needs 4 more drives): **Add drives** offers one more 4-drive RAIDZ1 group
  and shows the space it adds. After it's added, the pool is **RAIDZ1 · 8 drives**, with about
  twice the space.
- [ ] **A server that boots from NVMe** (not the VM): Disks marks the NVMe as the OS disk, and
  refuses to format or mount its partitions or put it in a pool.
- [ ] Optional: re-running `bin/amahi-install` keeps users, shares and settings.

## If something fails

Send Claude what the page showed, and the output of these (each on its own):

```bash
sudo tail -n 40 /var/log/amahi-kai/helper.log
```

```bash
journalctl -u amahi-kai -n 50 --no-pager
```

```bash
zpool status -v
```

```bash
lsblk -o NAME,MODEL,SERIAL,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

The helper log records every root action Amahi-kai took, with passwords left out.
