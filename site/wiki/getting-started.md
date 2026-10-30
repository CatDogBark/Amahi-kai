---
layout: default
title: "Getting Started"
---

# Getting Started

This guide covers installing Amahi-kai and the first-run setup wizard.

---

## System Requirements

- **OS**: Ubuntu 24.04 LTS (Server), on a dedicated machine or VM
- **RAM**: 2 GB minimum (4 GB recommended)
- **Disk**: a system disk of 32 GB or more (64 GB with apps): Ubuntu, Amahi-kai, its database and
  the apps' images live there, and the dashboard warns once less than 10 GB is free. Your files go
  on other drives.
- **Network**: wired Ethernet recommended; a fixed IP address makes it easier to find (Network →
  Devices sets one, see [This NAS](networking#this-nas-its-own-address))
- **Architecture**: x86_64 (amd64)

---

## Installation

On a fresh server:

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash
```

With options (here `--headless`), they go after `bash -s --`:

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash -s -- --headless
```

Or from a checkout of the repository (the installer clones it into `/opt/amahi-kai`, with its
git history, and later updates come from GitHub):

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

### Installer options

| Flag | Description |
|------|-------------|
| `--headless` | Non-interactive install; generates a random admin password and skips the setup wizard |
| `--help` | Show usage |

### What the installer does

Running it again is safe, the one-line command included: it keeps your users, shares, settings
and the version installed, and restarts Amahi-kai. New versions come through System Update
([Updating](updating)), which backs the database up first and goes back if a step fails.

1. **Swap**: creates a swap file if the machine has none.
2. **System packages**: build tools, Ruby 3.2 (Ubuntu's), MariaDB, Samba, Avahi, smartmontools and
   libraries. On a VM it also installs the guest agent, and it turns off a couple of services a NAS
   doesn't need (to save memory).
3. **The `amahi` user**, which the web app runs as.
4. **The code** in `/opt/amahi-kai`, with its git history, owned by root (the web app can't
   change it).
5. **Data folders**: `/var/lib/amahi-kai/files` (the share folder) and `/var/lib/amahi-kai/tmp`.
6. **Configuration**: `/etc/amahi-kai/amahi.env`, with a random secret key and database password.
7. **MariaDB**: the `amahi_production` database and its user.
8. **Gems**.
9. **The root helper, its sudo rules and the services** (see [Security](security)): Amahi-kai
   itself, the file search index (every 10 minutes), System Update's job, the check for updates
   (every 6 hours), the storage health check (every 15 minutes), pool snapshots (hourly), and the
   daily clean-ups of app update copies and the Trash. System Update installs them again, so they
   stay current.
10. **Database**: migrations, and on a new install the first admin account, whose password it
    shows straight away.
11. **Network settings** from the server's IP address, and Ubuntu's automatic updates off (on a new
    install only; turn them on under Settings → System Dependencies).
12. **Compiled styles and scripts** for the web UI.
13. **Firewall**: opens port 3000 if UFW is on.
14. **Samba**: writes its configuration (letting in only the server itself, your LAN and
    Tailscale) and turns on `smbd` and `nmbd`.
15. **File search index**: builds it.
16. **Starts Amahi-kai** and checks that it answers.

When it finishes, it prints where to go:

```
Web UI:  http://<your-server-ip>:3000
Sign in as:  admin
Password:    <a random password, shown only here>
Config:  /etc/amahi-kai/amahi.env
Shares:  /var/lib/amahi-kai/files
Logs:    journalctl -u amahi-kai -f
```

The admin password is random and printed by this install only, as soon as it's made and again at
the end: **save it**. The setup wizard then asks you to
choose one of your own (with `--headless` there's no wizard, and the printed one stays). Lost it?
On the server, `sudo /opt/amahi-kai/script/reset-user-password admin` sets a new one.

---

## First-run setup wizard

Log in as `admin` and the wizard starts:

1. **Welcome**: checks memory and swap, and can create a swap file if the server needs one.
2. **Admin password**: choose a new one (at least 8 characters). The wizard can't be finished
   while the admin account still has the first password the installer printed, and won't take
   that one back as the new one.
3. **Network**: see the IP address and give the server a name if you like. The name becomes the
   system's hostname and the name your computers see the server by. To keep the address, give
   the server a fixed one afterwards on **Network → Devices** ([This NAS](networking#this-nas-its-own-address)),
   or reserve it in your router's DHCP settings.
4. **Storage drives**: pick the drives to use. Amahi-kai can format a new drive (ext4), mounts each
   one under `/mnt` with settings that let the server still boot if a drive goes missing, and adds
   it to the storage pool. A drive with a filesystem Greyhole can't pool (NTFS, FAT, exFAT) is shared
   as it is instead, its files where they were. The drive the system runs from is never offered,
   and neither are drives that already hold a ZFS pool: import the pool afterwards (see
   [After installing Amahi-kai again](zfs-pools#after-installing-amahi-kai-again)). Leave unticked
   any drive you want for a [ZFS pool](zfs-pools) later: a pool takes whole drives with nothing on
   them.
5. **Greyhole**: install storage pooling and choose how many copies of each file new pooled
   shares keep (see [Storage Pooling](storage-pooling)). Optional.
6. **First share**: create a share such as "Movies", pooled with those copies once Greyhole is
   installed. Optional.
7. **Done**: a summary of what was set up; **Go to the dashboard** finishes the wizard.

You can skip the drive, Greyhole and share steps and do them later from the **Disks** and
**Shares** tabs. Once setup is finished, the wizard is closed for good.

---

## Next steps

- [ ] **Give the NAS a fixed address** on Network → Devices ([This NAS](networking#this-nas-its-own-address))
- [ ] **Plan your backups** ([below](#what-amahi-kai-doesnt-back-up))
- [ ] **Create shares** for media, documents and backups ([File Sharing](file-sharing))
- [ ] **Run the security audit** ([Security](security))
- [ ] **Install apps** from the catalog ([Docker Apps](docker-apps))
- [ ] **Set up remote access** with Cloudflare Tunnel or Tailscale ([Remote Access](remote-access))
- [ ] **Add drives to the storage pool** ([Storage Pooling](storage-pooling))

---

## What Amahi-kai doesn't back up

Amahi-kai doesn't make backups yet; a backup of the NAS's own state is planned for after 1.0. Until
then, keep your own copies of:

- **The NAS's settings**: its users, shares, apps and network settings, in its database and in
  `/etc/amahi-kai`. Installed again, Amahi-kai starts empty. A ZFS pool on the drives can be
  imported again ([ZFS Pools](zfs-pools#pools-found-on-the-drives)), and a share made again with
  the same name and place opens its files again.
- **Shares on the system disk** (`/var/lib/amahi-kai/files`): one disk, one copy. Greyhole's copies
  and a ZFS pool's redundancy survive a failed drive, but not a deleted file, a dead server or a
  fire; a pool's snapshots live on its own drives.
- **The house's internet, while the NAS is the router**: if the NAS is off or broken, nothing in
  the house reaches the internet until the old router is plugged back in. Keep it, and keep its
  settings.

---

## Troubleshooting

### Reporting a problem

**Settings → Help → Report a problem** puts a report together: what happened, in your words, and
this server's details and the newest lines of its logs. When something breaks, its red flag offers
**Report this problem**, and the report starts with what the flag said.

- **Names and addresses come out first.** The server's name, users, shares and what's in them,
  pools, devices, addresses and anything that looks like a key are replaced by stand-ins like
  `<share-1>`; the same name always gets the same one. A switch shows them as they are, and you
  can change any of it before you send it.
- **Nothing is sent by Amahi-kai.** **Open on GitHub** opens a new issue filled in, in your
  browser, for you to submit (a report too long for the link is also saved as a file to attach);
  **Send by email** opens your email app; **Download report** and **Copy** give you the text.
- **A security problem** goes privately instead: the repository's
  [Security tab](https://github.com/CatDogBark/Amahi-kai/security/advisories/new).

### The service won't start

```bash
systemctl status amahi-kai
journalctl -u amahi-kai -n 50 --no-pager
systemctl status mariadb        # Amahi-kai needs the database
```

### Can't reach the web UI

1. Is it running? `systemctl is-active amahi-kai`
2. Is it listening? `ss -tlnp | grep 3000`
3. If UFW is on, is port 3000 allowed? `sudo ufw status`
4. From the server itself: `curl -I http://localhost:3000/login`

### Something about the install looks broken

Run **Settings → System Status → Repair**, or over SSH:

```bash
sudo /opt/amahi-kai/bin/amahi-update --repair
```

It reinstalls gems, runs migrations, reinstalls the root helper, regenerates the Samba
configuration, puts file ownership back and restarts the app. Don't change the ownership of
`/opt/amahi-kai` by hand; root owns it on purpose.

### Forgot the admin password

Recovery needs root on the server (there's no "forgot password" link, on purpose):

```bash
cd /opt/amahi-kai && sudo script/reset-user-password admin
```

It asks for the new password twice, at a hidden prompt.
