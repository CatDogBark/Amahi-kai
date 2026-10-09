---
layout: default
title: "Storage Pooling"
---

# Storage Pooling

Amahi-kai uses [Greyhole](https://www.greyhole.net/) to combine several drives into one storage
pool. Files saved to a pooled share are spread across the drives, and you can keep extra copies on
different drives so a failed drive doesn't lose them.

---

## What Greyhole is for

Greyhole is mass storage for your SMB shares, with simple redundancy: pictures, videos, music,
documents, backups. It's good at:

- drives of any size, added one at a time
- a number of copies per share (2 copies of Photos, 1 of Downloads)
- each drive staying a normal ext4 drive you can read anywhere, even on its own

It only notices files that arrive **through Samba**: Greyhole's module in Samba tells it about each
file written, renamed or deleted. So:

- **Change files over the network share** (SMB). The web file browser only views and downloads.
- **Don't let apps write into a pooled share.** An app (a Docker container, say) that writes into
  a pooled share's folder goes around Samba: its new files only get their extra copies at
  Greyhole's weekly check, and files it deletes or renames leave their old copies behind, using
  space. Give apps that write their own data a ZFS pool, or a share that isn't pooled.

## Share storage or ZFS pools?

Amahi-kai has two kinds of storage, and each drive belongs to one of them.

| | Share storage (simple drives, Greyhole) | ZFS pools |
| --- | --- | --- |
| For | SMB shares: your files over the network | bitShare and apps' data |
| Drives | Any sizes, added one at a time | Matched drives, added a group at a time |
| Redundancy | Extra copies per share | Mirror or RAIDZ1/2/3, for the whole pool |
| Snapshots | No | Hourly and daily, to roll back to |
| Checks | Greyhole's own | Scrubs and drive health (SMART) |

ZFS pools are on **Disks → ZFS Pools**. They can't hold SMB shares, and they get their own page
here once they've been tested on real drives.

---

## Adding drives

Drives are prepared on **Disks → Devices** (or in the setup wizard's storage step):

- **Format** a new or empty drive as ext4.
- **Mount** it as share storage. Amahi-kai mounts data drives at `/mnt/<name>` and adds them to `/etc/fstab` by
  UUID with `nofail`, so the server still starts if a drive is missing or dead, and with
  `nosuid,nodev`, so nothing on a drive can run with privileges. The share folder on the system
  disk (`/var/lib/amahi-kai/files`) is mounted the same way. A drive's mount point is an empty
  folder made immutable while nothing is mounted on it, so while the drive is missing nothing
  can put files there on the system disk.
- **Preview** a drive before mounting it: Amahi-kai mounts it read-only for a moment and lists
  its top-level folders, so you can see what's on it.
- **Unmount** it before removing it.

The drive the system runs from (including NVMe and LVM setups) is never offered for formatting or
mounting.

---

## How pooling works

Greyhole works with Samba. When a file is saved to a pooled share:

1. Samba writes it to the share's folder (the landing zone).
2. Greyhole moves it onto one of the pool drives, leaving a link in its place.
3. With extra copies turned on, Greyhole keeps that many copies on different drives.
4. The file stays where you put it as far as you can see; Greyhole handles where it really lives.

---

## Installing Greyhole

Any one of:

- the installer's `--with-greyhole` option
- the setup wizard's Greyhole step
- **Disks → Storage Pool → Install Greyhole** (the progress streams as it installs)

Amahi-kai adds Greyhole's apt repository (its signing key is checked against a pinned
fingerprint), installs the package and the PHP modules it needs, creates its database and turns
on the service.

**Disks → Storage Pool** shows Greyhole's status, with **Start** and **Stop**, and **Uninstall**.
Uninstalling takes only the package, its config and its repository, and is offered once no drive is
in the pool and no share keeps copies with it (the page says which).

---

## Choosing pool drives

On **Disks → Storage Pool**, tick **In Pool** for each share-storage drive under Available
Partitions to add it. The pool drives are listed above that, with their space. Each pool drive
keeps at least 10 GB free (Min Free); Greyhole stops putting files on a drive below that.

When a drive joins the pool, or a share's copies go up, Amahi-kai has Greyhole check the pool
straight away (`greyhole --fsck`), so the copies the shares are short of are made within minutes.
Greyhole's own daily check runs only after its configuration changes, the next morning.

## Copies per share

On **Setup → Shares**, open a share and set its **Pool copies** with − and +:

| Pool copies | What happens |
|-------------|--------------|
| Off | Not pooled: files stay in the share's own folder, on the system disk |
| 1 copy | Greyhole keeps the files on the pool drives, which adds up their space, but a drive that fails loses its files |
| 2 copies | Each file is kept on two drives, so one can fail and nothing is lost |

Over the network a pooled share looks the same as one that's Off: Greyhole leaves a link in the
share's folder for each file it moves onto the pool drives. What changes is where the files are
kept, and so whose space they use. Changing copies regenerates Greyhole's configuration and
restarts it.

**Turning a pooled share Off** moves its files back: Greyhole copies them from the pool drives into
the share's folder, on the system disk, so it needs room for them there. The share says it's
turning off until that's done, and the page updates by itself.

### Free space on pooled shares

A computer connected to a pooled share sees the pool's size and free space, not the system
disk's. Samba asks Amahi-kai's free-space command (`dfree command` in `smb.conf`), which adds up
the mounted pool drives and divides their free space by the share's copies, as Greyhole's own
does: a 2-copy share on a pool with 4 TB free shows 2 TB free.

### Deleted files

What's deleted from a pooled share over the network share stays in Greyhole's trash on the pool
drives, and shows in the file browser's **Trash** with every other share's deleted files, to
restore or delete for good (see [File Sharing](file-sharing#trash)).

---

## Greyhole configuration

Amahi-kai writes `/etc/greyhole.conf` (readable only by root and Amahi-kai, since it holds a
database password). Don't edit it by hand. It lists the pool drives and the copies per share:

```ini
storage_pool_drive = /mnt/data1, min_free: 10gb
storage_pool_drive = /mnt/data2, min_free: 10gb

num_copies[Movies] = 1
num_copies[Photos] = 2
```

Samba's configuration gets the settings Greyhole needs (following its links) whenever it's
regenerated, so pooled files stay reachable after any share change.

---

## Managing Greyhole

```bash
systemctl status greyhole
sudo systemctl restart greyhole
greyhole --status     # what it's working on
greyhole --fsck       # check the pool
```

The dashboard, **Settings → Servers** and **Disks → Storage Pool** show whether Greyhole is running.

### Removing a drive

1. Click **Remove** on the drive's row under Storage Pool Drives on **Disks → Storage Pool**.
2. Greyhole first moves the files kept only on that drive to the other drives. The row says
   **Removing** until it's done, and the page updates by itself; then the drive leaves the pool.
3. Unmount the drive on **Disks → Devices**, then take it out.

Greyhole needs room on the other drives for the files it moves.

A drive that's no longer connected can be removed too. Files kept only on it are lost; files with a
copy on another drive get their second copy made again. A drive that was swapped or formatted in
the same place shows **Use this drive**, which tells Greyhole to take it.

---

## Troubleshooting

### Greyhole won't start

```bash
journalctl -u greyhole -n 50 --no-pager
```

### Files aren't spread across drives

- Is Greyhole running? `systemctl is-active greyhole`
- Is the share pooled (copies 1 or more)?
- Do the pool drives have more than 10 GB free?
- What is it doing? `greyhole --status`
