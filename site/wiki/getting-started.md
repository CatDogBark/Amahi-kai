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
- **Disk**: 10 GB for the OS and Amahi-kai, plus whatever drives you want to share
- **Network**: wired Ethernet recommended; a fixed IP address makes it easier to find
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

Running it again is safe: it keeps your users, shares and settings, pulls the latest code and
restarts Amahi-kai.

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
14. **Samba**: writes its configuration (answering on your LAN only) and turns on `smbd` and
    `nmbd`.
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
   until the default password is changed.
3. **Network**: confirm the IP address and give the server a name if you like. The name becomes
   the system's hostname and the name your computers see the server by.
4. **Storage drives**: pick the drives to use. Amahi-kai can format a new drive (ext4), mounts each
   one under `/mnt` with settings that let the server still boot if a drive goes missing, and adds
   it to the storage pool. A drive with a filesystem Greyhole can't pool (NTFS, exFAT) becomes a
   share of its own instead. The drive the system runs from is never offered.
5. **Greyhole**: install storage pooling and choose how many copies of each file new pooled
   shares keep (see [Storage Pooling](storage-pooling)). Optional.
6. **First share**: create a share such as "Movies", pooled with those copies once Greyhole is
   installed. Optional.
7. **Done**: a summary of what was set up; **Go to the dashboard** finishes the wizard.

You can skip the drive, Greyhole and share steps and do them later from the **Disks** and
**Shares** tabs. Once setup is finished, the wizard is closed for good.

---

## Next steps

- [ ] **Create shares** for media, documents and backups ([File Sharing](file-sharing))
- [ ] **Run the security audit** ([Security](security))
- [ ] **Install apps** from the catalog ([Docker Apps](docker-apps))
- [ ] **Set up remote access** with Cloudflare Tunnel or Tailscale ([Remote Access](remote-access))
- [ ] **Add drives to the storage pool** ([Storage Pooling](storage-pooling))

---

## Troubleshooting

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
