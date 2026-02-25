---
layout: default
title: "Getting Started"
---

# Getting Started

This guide walks you through installing Amahi-kai and completing the first-run setup wizard.

---

## System Requirements

- **OS**: Ubuntu 24.04 LTS or Debian 12+
- **RAM**: 2 GB minimum (4 GB recommended)
- **Disk**: 10 GB minimum for the OS + application
- **Network**: Wired Ethernet connection recommended
- **Architecture**: x86_64 (amd64)

The installer will set up everything you need: Ruby 3.2, MariaDB, Samba, and the Amahi-kai Rails application.

---

## Installation

### One-Liner Install

On a fresh Ubuntu 24.04 server, run:

```bash
curl -fsSL https://amahi-kai.com/install.sh | sudo bash
```

Or if you've cloned the repository:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

### Installer Options

| Flag | Description |
|------|-------------|
| `--headless` | Non-interactive install; generates a random admin password and skips the setup wizard |
| `--with-greyhole` | Install Greyhole storage pooling during initial setup |
| `--help` | Show usage information |

Example with all options:

```bash
sudo bin/amahi-install --headless --with-greyhole
```

### What the Installer Does

The installer is **idempotent** — you can run it again safely. It performs these steps:

1. **System packages** — Installs build tools, MariaDB, Samba, and development libraries
2. **VM detection** — Auto-installs guest agents for KVM/QEMU or VMware
3. **Greyhole** (if `--with-greyhole`) — Adds the Greyhole apt repo, installs the package and PHP dependencies
4. **Ruby** — Uses system Ruby 3.2 (Ubuntu 24.04 ships it), falls back to rbenv if needed
5. **System user** — Creates the `amahi` user and group
6. **Application code** — Deploys to `/opt/amahi-kai`
7. **Data directories** — Creates `/var/hda/files` (share root), `/var/hda/dbs`, `/var/hda/tmp`
8. **Configuration** — Generates `/etc/amahi-kai/amahi.env` with a random secret key and database password
9. **MariaDB** — Creates the `amahi_production` database and user
10. **Sudoers** — Installs a least-privilege allowlist at `/etc/sudoers.d/amahi-kai`
11. **Bundle install** — Installs Ruby gems
12. **Database setup** — Runs migrations and seeds
13. **Network detection** — Auto-configures network settings based on the host IP
14. **Assets** — Precompiles CSS/JS
15. **Systemd service** — Installs and enables `amahi-kai.service`
16. **Firewall** — Opens port 3000 in UFW if active
17. **Samba** — Enables `smbd` and `nmbd`
18. **File indexer** — Builds the initial search index and installs a 10-minute timer

### After Installation

The installer prints connection details:

```
Web UI:  http://<your-server-ip>:3000
Login:   admin / secretpassword
Config:  /etc/amahi-kai/amahi.env
Shares:  /var/hda/files
Logs:    journalctl -u amahi-kai -f
```

In headless mode, the admin password is randomly generated and printed once — **save it**.

---

## First-Run Setup Wizard

When you log in for the first time (non-headless mode), the setup wizard guides you through initial configuration. You must be logged in as `admin`.

### Step 1: Welcome

Introduction screen. Click **Next** to proceed.

### Step 2: Change Admin Password

**You must change the default password.** Requirements:
- Minimum 8 characters
- Password and confirmation must match

The default login is `admin` / `secretpassword`. Change this immediately.

### Step 3: Network Settings

Review your server's hostname and IP address. Optionally set a friendly server name (stored in settings as `server-name`).

### Step 4: Storage

Select disk partitions to include in the storage pool. The wizard shows available partitions and filters out system mounts (`/`, `/boot`, `/boot/efi`). Each partition gets a configurable minimum free space threshold (default: 10 GB, 20 GB for root).

> You can skip this step and configure storage pooling later from the Shares tab.

### Step 5: Create a Share

Optionally create your first file share. Enter a name (e.g., "Movies"), and the wizard creates the directory at `/var/hda/files/<name>` with Samba configuration.

### Step 6: Complete

Review your choices and click **Finish** to mark setup as complete. You'll be redirected to the dashboard.

---

## Post-Install Checklist

After the wizard, consider:

- [ ] **Change the admin password** (if you haven't already)
- [ ] **Create shares** for your media, documents, backups (see [File Sharing](file-sharing))
- [ ] **Run the security audit** (see [Security](security))
- [ ] **Install Docker apps** from the catalog (see [Docker Apps](docker-apps))
- [ ] **Set up remote access** with Cloudflare Tunnel (see [Remote Access](remote-access))
- [ ] **Configure storage pooling** with Greyhole (see [Storage Pooling](storage-pooling))

---

## Troubleshooting

### Service won't start

```bash
# Check the service status
systemctl status amahi-kai

# View recent logs
journalctl -u amahi-kai -n 50 --no-pager

# Check if MariaDB is running (required dependency)
systemctl status mariadb
```

### Can't access the web UI

1. Verify the service is running: `systemctl is-active amahi-kai`
2. Check if port 3000 is open: `ss -tlnp | grep 3000`
3. If using UFW: `sudo ufw status` — ensure port 3000 is allowed
4. Try accessing from the server itself: `curl http://localhost:3000`

### Database errors

```bash
# Re-run migrations
cd /opt/amahi-kai
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails db:migrate"
```

### Permission issues

```bash
# Fix file ownership
sudo chown -R amahi:amahi /opt/amahi-kai
sudo chown -R amahi:amahi /var/hda/files
```
