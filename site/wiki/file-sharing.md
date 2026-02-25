---
layout: default
title: "File Sharing"
---

# File Sharing

Amahi-kai manages Samba file shares through its web UI. When you create, modify, or delete a share, the app regenerates `/etc/samba/smb.conf` and reloads Samba automatically.

---

## Concepts

- **Share** — A named directory under `/var/hda/files/` exposed over SMB/CIFS
- **Everyone mode** — All users have access (default for new shares)
- **Per-user access** — When "Everyone" is toggled off, you control read and write access per user
- **Guest access** — Allow unauthenticated (anonymous) access to a share
- **Tags** — Comma-separated labels for organizing shares (e.g., `movies, media`)

### Default Shares

The seed data creates these shares: **Books**, **Pictures**, **Movies**, **Videos**, **Music**, **Docs**, **Public**, **TV**. All are stored under `/var/hda/files/<name>`.

---

## Creating a Share

### From the Web UI

1. Navigate to the **Shares** tab (`/tab/shares`)
2. Enter a name in the "New Share" form
3. Click **Create**

The app will:
- Create the directory at `/var/hda/files/<name>` (lowercased)
- Set ownership to the first admin user and the `users` group
- Add the share to `smb.conf`
- Reload Samba

### Share Properties

| Property | Default | Description |
|----------|---------|-------------|
| Visible (browseable) | Yes | Whether the share appears in network browsers |
| Read-only | No | If enabled, nobody can write (overrides per-user write permissions) |
| Everyone | Yes | All users get full access |
| Guest access | No | Allow anonymous access (when Everyone is off) |
| Guest writeable | No | Allow anonymous write access |
| Tags | share name | Comma-separated labels |
| Path | `/var/hda/files/<name>` | On-disk directory |
| Extras | empty | Raw Samba config lines appended to this share's section |

---

## Managing Permissions

### Everyone Mode (Default)

When a share has **Everyone** enabled, all Amahi-kai users have read and write access. This is the simplest mode.

### Per-User Access

Toggle **Everyone** off to switch to per-user mode. You can then:

- **Toggle access** — Grant or revoke a specific user's ability to see the share
- **Toggle write** — Grant or revoke a specific user's ability to write to the share

Changes are written to `smb.conf` as `valid users` and `write list` directives.

### Guest Access

When Everyone is off, you can enable **Guest access** to allow unauthenticated users to browse the share. Guest access is read-only by default; toggle **Guest writeable** to allow writes.

### Clear Permissions

The **Clear Permissions** action runs `chmod -R a+rwx` on the share directory — useful when files become inaccessible due to ownership issues (e.g., files created by Docker containers).

---

## Samba Configuration

Amahi-kai auto-generates the entire `smb.conf`. You should **not** edit it manually — changes will be overwritten.

### Global Settings

The `[global]` section is configured with:

```ini
workgroup = WORKGROUP
netbios name = hda
security = user
guest account = nobody
map to guest = Bad User
wins support = yes
```

The workgroup name is configurable from **Shares > Settings** (in Advanced mode).

### Per-Share Section

Each share generates a config block like:

```ini
[Movies]
    comment = Movies
    path = /var/hda/files/movies
    writeable = yes
    browseable = yes
    create mask = 0775
    force create mode = 0664
    directory mask = 0775
    force directory mode = 0775
```

### Extras Field

The **Extras** field on each share lets you inject raw Samba directives. For example, to enable Apple Time Machine support:

```
vfs objects = catia fruit streams_xattr
fruit:time machine = yes
```

### PDC Mode

Amahi-kai supports Primary Domain Controller (PDC) mode for legacy Windows domain logins. This is enabled via the `pdc` shares setting and adds domain logon support, roaming profiles, and netlogon scripts.

---

## Accessing Shares

### From Windows

Open File Explorer and type in the address bar:

```
\\<server-ip>\ShareName
```

Or use the netbios name:

```
\\hda\ShareName
```

### From macOS

In Finder, press **Cmd+K** and enter:

```
smb://<server-ip>/ShareName
```

### From Linux

```bash
# Browse shares
smbclient -L //<server-ip>/ -U username

# Mount a share
sudo mount -t cifs //<server-ip>/ShareName /mnt/share -o username=youruser,uid=$(id -u),gid=$(id -g)
```

---

## File Search

Amahi-kai indexes files across all shares into a database for fast searching. The search box on the dashboard supports:

- **General search** — Searches all files by name
- **Image search** — Filters to image files
- **Audio search** — Filters to audio files
- **Video search** — Filters to video files

The index is updated automatically every 10 minutes by a systemd timer (`amahi-kai-indexer.timer`). You can trigger a full reindex manually:

```bash
cd /opt/amahi-kai
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails shares:reindex"
```

---

## Advanced: Workgroup

To change the Samba workgroup name:

1. Enable **Advanced mode** (toggle in Settings)
2. Go to **Shares > Settings**
3. Edit the workgroup name (1-15 alphanumeric characters, must start with a letter)

This regenerates `smb.conf` and reloads Samba.
