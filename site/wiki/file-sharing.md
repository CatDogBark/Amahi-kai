---
layout: default
title: "File Sharing"
---

# File Sharing

Amahi-kai manages Samba file shares from the **Shares** tab, and has a file browser for using
shares from a web browser. When you create, change or delete a share, Amahi-kai regenerates
`/etc/samba/smb.conf` and reloads Samba.

---

## Concepts

- **Share**: a named folder exposed over SMB, under `/var/lib/amahi-kai/files/` or on a data drive
  mounted under `/mnt/`
- **Everyone**: all users can read and write (the default for new shares)
- **Per-user access**: with Everyone off, you choose who can see the share and who can write to it
- **Guest access**: lets people in without an account
- **Tags**: comma-separated labels for organizing shares

---

## Creating a share

1. Go to the **Shares** tab.
2. Enter a name and click **Create**.

Amahi-kai creates the folder (owner `amahi`, group `users`, so share users can write to it), adds
the share to Samba's configuration and reloads Samba. A share's folder must be inside
`/var/lib/amahi-kai/files` or on a data drive under `/mnt`; other places are refused.

### Share settings

| Setting | Default | Description |
|---------|---------|-------------|
| Visible | Yes | Whether the share shows up when browsing the network |
| Read-only | No | Nobody can write (overrides per-user write access) |
| Everyone | Yes | All users get read and write access |
| Guest access | No | Allow access without an account (when Everyone is off) |
| Guest writeable | No | Allow guests to write too |
| Tags | the share's name | Labels |
| Path | `/var/lib/amahi-kai/files/<name>` | The folder on disk |
| Extras | empty | Extra Samba lines for this share (Advanced mode) |

---

## Permissions

- **Everyone on:** every Amahi-kai user can read and write.
- **Everyone off:** use **access** and **write** for each user. They become Samba's `valid users`
  and `write list`.
- **Guest access** (with Everyone off): read-only for guests unless **Guest writeable** is on.
- **Clear permissions** removes every per-user access and write grant on the share, so you can
  start over.

Users are managed on the **Users** tab. Each user gets a Linux account (used only for Samba; it
can't log in to the server) and a Samba password, kept in step with their web password.

---

## Samba configuration

Amahi-kai writes the whole `smb.conf`; don't edit it by hand, since changes get overwritten. A new
configuration is checked with `testparm` before it's installed, so a bad one can't take your
shares offline.

The global settings include:

- **Workgroup** (default `WORKGROUP`), changeable on **Shares > Settings** (Advanced mode)
- **Who can connect:** the server itself, your LAN and Tailscale only (`hosts allow`), on the LAN
  interface (and Tailscale's, if it's installed). Docker containers can't reach Samba.
- **Printer sharing off**
- **Greyhole settings** when Greyhole is installed (see [Storage Pooling](storage-pooling))

### Extras

The **Extras** field adds Samba lines to one share. For example, for Apple Time Machine:

```
vfs objects = catia fruit streams_xattr
fruit:time machine = yes
```

---

## Connecting to shares

- **Windows:** in File Explorer's address bar, `\\<server-ip>\ShareName`
- **macOS:** in Finder, **Cmd+K**, then `smb://<server-ip>/ShareName`
- **Linux:** in your file manager, `smb://<server-ip>/ShareName`, or:

```bash
smbclient -L //<server-ip>/ -U username
sudo mount -t cifs //<server-ip>/ShareName /mnt/share -o username=youruser,uid=$(id -u),gid=$(id -g)
```

Each user also has a private home share, `\\<server-ip>\username`.

---

## File browser

Click **Browse** on a share (or on the dashboard) to look through it in your web browser. You can:

- move through folders, with a breadcrumb trail
- preview images, video, audio and PDFs
- download files, or a whole folder as a zip (**Download this folder**, or **Download as zip** on a
  folder)

The file browser only views: it doesn't upload, rename, move or delete. Files change over the
network share (SMB, above), so Samba, and [Greyhole](storage-pooling) on pooled shares, sees every
change, and each user's share permissions apply. Away from home, connect over
[Tailscale](remote-access) and use the share as usual. A stolen web login can't change your files.

Users only see the shares they have access to. HTML, JavaScript and XML files are shown as plain
text, and files open sandboxed (scripts in them can't run), so a file someone puts in a share
can't act on your Amahi-kai session. A folder download only includes the files that are in the
share.

---

## File search

The search box searches file names across all shares, with filters for images, audio and video.
The index updates every 10 minutes (`amahi-kai-indexer.timer`). To rebuild it from scratch:

```bash
cd /opt/amahi-kai
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails shares:reindex"
```
