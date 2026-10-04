---
layout: default
title: "Storage Pooling"
---

# Storage Pooling

Amahi-kai uses [Greyhole](https://www.greyhole.net/) to combine several drives into one storage
pool. Files saved to a pooled share are spread across the drives, and you can keep extra copies on
different drives so a failed drive doesn't lose them.

---

## Adding drives

Drives are prepared on **Disks > Devices** (or in the setup wizard's storage step):

- **Format** a new or empty drive as ext4.
- **Mount** it. Amahi-kai mounts data drives at `/mnt/<name>` and adds them to `/etc/fstab` by
  UUID with `nofail`, so the server still starts if a drive is missing or dead.
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
- **Disks > Storage Pool > Install Greyhole** (the progress streams as it installs)

Amahi-kai adds Greyhole's apt repository (its signing key is checked against a pinned
fingerprint), installs the package and the PHP modules it needs, creates its database and turns
on the service.

---

## Choosing pool drives

On **Disks > Storage Pool**, turn each mounted data drive on or off for the pool. Each pool drive
keeps at least 10 GB free; Greyhole stops putting files on a drive below that.

## Copies per share

On the **Shares** tab, turn pooling on for a share and set its number of copies:

| Copies | What happens |
|--------|--------------|
| 0 | Not pooled: files stay in the share's own folder |
| 1 | Pooled, one copy: files are spread across drives, without duplicates |
| 2 or more | That many copies, each on a different drive |
| max | A copy on every pool drive |

Changing copies regenerates Greyhole's configuration and restarts it.

---

## Greyhole configuration

Amahi-kai writes `/etc/greyhole.conf` (readable only by root and Amahi-kai, since it holds a
database password). Don't edit it by hand. It lists the pool drives and the copies per share:

```ini
storage_pool_drive = /mnt/data1, min_free: 10gb
storage_pool_drive = /mnt/data2, min_free: 10gb

num_copies[Movies] = 2
num_copies[Photos] = max
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

The dashboard and **Settings > Servers** show whether Greyhole is running.

### Removing a drive

1. Turn the drive off in the pool on **Disks > Storage Pool**.
2. Wait for Greyhole to move its files elsewhere (`greyhole --status` shows the queue).
3. Unmount the drive on **Disks > Devices**, then remove it.

Greyhole needs room on the other drives for the files it moves.

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
