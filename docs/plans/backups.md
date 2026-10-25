# Backups: bringing a NAS back

**Status: after 1.0** (CatDogBark, 2026-10-24: there are no users yet, and his own NAS has
Proxmox's backups of its VM). This was §4 of [`release-1.0.md`](release-1.0.md), planned for bare
metal the same day; it moved here whole, with two corrections from the same discussion (what's
backed up, and Greyhole's check). See also the roadmap's "Backups after 1.0".

This plan is for someone running Amahi-kai on bare metal, with nothing underneath it (CatDogBark,
2026-10-24: his own NAS's Proxmox isn't the case to plan for). It backs up **Amahi-kai's own
state, not the files**: ZFS and Greyhole keep those on their drives, and a restore reconnects them
(it imports the pool and mounts the drives again) without copying any. The one exception is the
apps' folders on the system disk, which nothing else covers (below). When the system disk dies,
Amahi-kai's own backup is the only way back, so **restoring onto a fresh install is the main
feature**. The rule for what comes back (CatDogBark, 2026-10-24): the restore brings
the NAS back; whatever is easy to bring back comes back, and whatever is hard is left out and said
so. Today the only copies are the database dumps System Update makes before it runs (the last
three, on the system disk).

## What a backup is

One file per backup, `amahi-kai-<host>-<date>.tar.zst.gpg`: a tar archive, compressed with zstd and
encrypted with GnuPG (AES-256) using a passphrase the admin sets. All three tools are on every
install already (zstd comes with Ubuntu, GnuPG with Amahi-kai's installer), and anyone with the
passphrase can open a backup by hand (`gpg -d <file> | zstd -d | tar -x`). Each backup stands
alone, so a damaged file costs one day, not all of them.

Not restic, though it was weighed. restic keeps backups in a repository of chunks, each backup
storing only what changed: the right shape for terabytes of shares going off-site, so it fits the
file copies after 1.0 (roadmap, "Backups after 1.0"). For this it would be a new package, a folder
of many files where a download or an upload wants one file, and a damaged chunk spoils every backup
that shares it. What goes in here is small: megabytes of settings, plus the apps' folders on the
system disk, which the catalog already trims (Jellyfin's cache and Transmission's downloads are
`backup: false`).

Inside:

- `manifest.json`: the Amahi-kai version, when, which kind (daily, before an update, by hand), and
  what the restore needs before it starts: each account's name and number, the drives (UUID, mount
  point, model, serial), the pools (name, GUID, drives), the network (mode, each port's name, label
  and address), the apps (image, where their data lives) and the packages in use.
- The database (`mysqldump --single-transaction`).
- From `/etc/amahi-kai`: the tunnel token, `trash-days`, `greyhole-pool.conf`, and the update
  channel's line of `amahi.env`. The rest of `amahi.env` stays the new install's: its database
  password, and its session key (nothing in the database is encrypted with that key; a new one only
  means signing in again).
- Samba's passwords (`pdbedit -e smbpasswd:`), so nobody has to set theirs again.
- Tailscale's state, so the NAS comes back as the same device with the same address and no new
  sign-in; and SSH's host keys, so computers that connect over SSH don't warn about a changed key.
- Each app's folders on the system disk that its manifest backs up (the list the copy before an app
  update uses, `app_backup_folders`), read with the app stopped. An app on a pool keeps its data in
  its dataset there, which the pool's snapshots cover and which outlives the system disk.

## Where, when, how many

- **Where:** a folder, `amahi-kai-backups`, at the top of a pool or a data drive, the admin's choice
  (proposed default: the first pool). Never the system disk, the one the backups are for: a NAS with
  no data drive still makes them, and the tab says plainly that they won't survive that disk and to
  download them. Never inside a Greyhole share either: Greyhole only spreads files that come in
  through Samba. The folder is shared read-only, to admins only, as **Backups**, so any computer can
  copy backups off the box (to a USB drive, a cloud folder) and nothing on the network can delete or
  encrypt them.
- **When:** daily by a timer (at the next boot if the server was off), before every System Update,
  and on **Back up now**. System Update keeps its own database dump for its rollback, which has to
  work with backups off. Each backup is read back after it's written: it decrypts, its file list
  reads, and the database dump is whole.
- **How many:** proposed default 30 days, the admin's to change. The tab shows the total size, and
  there must be room first, checked the way an app update's copy checks it (`app_backup_room!`).
- **The passphrase:** at least 12 characters, kept on the NAS where only root can read it so the
  timer can run, never inside a backup. A lost passphrase makes every backup useless, so the tab
  says to keep it in a password manager and has **Check passphrase**. Changing it makes a backup
  straight away; the older ones still open with the old one, and the list marks them.

## The Backups tab, for admins

Backup and restore both in the UI (CatDogBark, 2026-10-23): on or off, where, how many, the
passphrase, Back up now, and the list (time, kind, version, size), each with Download and Restore.
The setup wizard's last step asks for the passphrase, so a new NAS has backups from its first night
(it can be skipped; the dashboard then warns). System Status lists the timer with the other
scheduled jobs, and the dashboard warns while backups are off or the newest good one is more than
two days old.

A **recovery sheet** to print or save, made from the settings as they are: the steps below, which
pool or drive holds the backups, the data drives' models and serials (so the Ubuntu installer isn't
pointed at one of them), the network (mode, each port's name and address, the router, the DHCP
range), and a reminder of where the passphrase is kept. It matters most for a NAS that is the
router: while it's down, there's no internet to look anything up.

## Restore

On a fresh install, **Restore from a backup** is a choice on the setup wizard's first page, in place
of the wizard; on a running NAS it's on the tab. The restore runs as its own job, as System Update
does, so it outlives the app's restarts. The page follows its progress (step names only) without
needing a session, since the accounts change under it, and when it's done asks you to sign in with
the restored accounts. App code runs as the app user (`as_app`), as in the updater.

1. **Find the backups:** on every pool the server can import (ZFS is installed first if a drive is a
   ZFS member), every data drive, and any USB drive plugged in (mounted read-only to look), newest
   first; or upload a file. A backup from a newer Amahi-kai than the one running is refused (update
   first); an older one is brought forward by the migrations.
2. **The passphrase, and what will happen:** what comes back and what doesn't (below), and that the
   old NAS must be off, because two machines with one tunnel and one Tailscale identity fight over
   them. On a running NAS: a plain warning that it replaces the users, shares and settings there
   now, and a choice, off by default there, to put the apps' data back too.
3. **In order:**
   1. The services stop.
   2. The pool is imported, and the data drives are mounted at their old places by UUID.
   3. The accounts come back with their old numbers (the users' and the apps'), before the restore
      installs any package, because files on the pool and the drives are owned by number and today
      an account gets whatever number is free when it's made. Where an old number is taken (the
      `amahi` account is the installer's own), the account gets a new one, its app data is given to
      the new number, and the last page lists it; share files still work through the `users` group.
   4. The packages the backup used, from the helper's list (Docker, Unbound, dnsmasq, radvd,
      Tailscale, cloudflared, Greyhole, ZFS, Fail2ban, unattended-upgrades).
   5. The database is put back and migrated.
   6. The files above go back: the tunnel token, Samba's passwords, Tailscale's state, SSH's host
      keys, the apps' folders.
   7. Samba's, Greyhole's and DNS's configurations are made again, with the settings that describe
      this machine's own address taken from the machine, not the backup. Then Greyhole's full
      check: each Greyhole share's folder of links sits on the system disk, and Greyhole's help
      says walking the metadata stores on its drives is what re-creates missing links. The
      helper's `greyhole.fsck` skips that walk (`--dont-walk-metadata-store`, to be quick), so the
      restore runs its own, with `--find-orphaned-files` too.
   8. The apps are made again from the images they had, with their data.
   9. The firewall and Fail2ban as they were, the host name, the update channel, automatic security
      updates; the services start; backups go back on, with the passphrase just typed.
4. **The last page:** what came back, what failed (a drive missing, an image that couldn't be
   pulled), and what's left to do by hand.

**A restore never moves the network.** Router mode and the NAS's own fixed addresses stay as this
machine has them: router mode turned on behind the router standing in during a reinstall would put
two routers on one network, and an address change can cut the browser off. All their settings come
back (DNS, blocking, the DHCP range and reservations, port forwards, LAN-only devices, port names);
DNS goes on, and DHCP too unless another DHCP server answers (the DHCP page's own check). For each
port this machine has, the last page offers the rest as steps on the pages that already do them:
the NAS's address back (This NAS, with its guard), then router mode on (Internet), once the modem is
in the internet port and the other router is an access point again. A port the backup names that
this machine doesn't have, after a motherboard change, is listed and set up by hand on Devices:
matching old ports to new ones is out of 1.0 (CatDogBark, 2026-10-24).

**Not restored, and said so** on the last page and in the wiki:

- Files in shares kept on the system disk (the tab warns about those shares while they exist),
  files Greyhole hadn't yet moved onto its drives when the disk died, and anything on a pool that's
  lost: copies of files come after 1.0.
- SSH's own settings: the security audit's fix is a click, and it needs an account with a key first,
  which a new install may not have yet.
- What's fetched again instead of kept: the apps' images, the blocklists, the catalog. Devices'
  current leases (they renew), the logs and the update history.
- Anything changed by hand outside Amahi-kai, and the Ubuntu admin account's own files.

## A NAS that was the router

While it's down the house has no internet, and a fresh install plugged straight into the modem
would sit on the internet with no firewall while it's set up. The recovery sheet's steps: put the
other router back in charge (out of access-point mode, the modem on it), install Ubuntu and
Amahi-kai behind it, restore, then the last page's steps. The router-mode wiki page says to keep a
router that can take over.

## Considered instead

- **A backup app from the catalog** (Backrest, Kopia, Duplicati; 2026-10-24). Not for this. An
  app's container can't gain privileges and sees only its own folders and the shares it's given,
  while the state is mostly root's (the database, the tunnel token, Samba's hashes, the Tailscale
  and SSH keys, other apps' folders): opening that to a third-party image would make it the most
  powerful thing on the NAS. And an app can't restore onto a fresh install: putting files back
  doesn't make the accounts at their numbers, import the pool, install packages, load the database
  or make the apps again. Other NAS systems keep this part in the system too (TrueNAS's
  configuration file; OpenMediaVault's backup plugin, which takes the system drive and not the data
  drives). An app is right for the files after 1.0 (roadmap): Backrest, a web UI over restic, given
  shares read-only and the Backups folder, would take copies off-site, and plain restic still opens
  its backups if Backrest goes away.
- **Relax-and-Recover** (ReaR; Ubuntu 24.04 has 2.7). It copies the system disk to a USB drive or a
  share and makes a bootable rescue stick; recovering is booting it and running `rear recover`.
  Little code, everything comes back exactly, and nothing has to be added to the backup as features
  grow. Not chosen: a dedicated stick, a keyboard, a monitor and a command line at recovery, trouble
  on different hardware, and no way to put yesterday's settings back on a running NAS.

## Tested

On the test VM, standing in for bare metal (its Initial snapshot is a fresh Ubuntu, before
Amahi-kai): a pool on extra virtual disks, users with Samba passwords, apps with data on the system disk and on the pool,
Tailscale and the tunnel, router mode on the island. Back up; put the system disk back to Initial
with the data disks kept; install through the website; restore; then check the sign-ins, the shares
over SMB from the laptop, the apps and their data, the accounts' numbers, DNS, and the last page's
router steps on the island. Once more with a data drive in place of the pool. Also: a restore on a
running NAS, an uploaded file, a USB drive, a wrong passphrase, a backup from a newer version.

Decisions for CatDogBark: one file rather than restic, the default place (the first pool), and how
many to keep (30 days). About twelve days of work: the backup side about four, the restore about
five, tests and docs about three.
