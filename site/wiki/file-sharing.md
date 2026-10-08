---
layout: default
title: "File Sharing"
---

# File Sharing

Amahi-kai manages Samba file shares on **Setup → Shares**, and has a file browser (**Files** in the
header) for using shares from a web browser. When you create, change or delete a share, Amahi-kai regenerates
`/etc/samba/smb.conf` and reloads Samba.

---

## Concepts

- **Share**: a named folder exposed over SMB, under `/var/lib/amahi-kai/files/` or on a data drive
  mounted under `/mnt/`
- **All users**: everyone with an account can open the share (the default for new shares), and
  **Writeable** lets them change its files
- **Per-user access**: with All users off, you choose who can open the share and who can write to it
- **Guests**: lets people in without an account
- **Trash**: what's deleted from a share is kept for a while, so it can be restored

---

## Creating a share

1. Go to **Setup → Shares**.
2. Under **Create a New Share**, enter a name and click **Create**.

Amahi-kai creates the folder (owner `amahi`, group `users`, so share users can write to it), adds
the share to Samba's configuration and reloads Samba. A share's folder must be inside
`/var/lib/amahi-kai/files` or on a data drive under `/mnt`; other places are refused.

### Share settings

Click a share's name to open its settings. Each says what it does underneath.

| Section | Setting | Default | What it does |
|---------|---------|---------|--------------|
| Access | Who can use it | All users, Writeable | All users and Writeable, or (with All users off) each user's access and write, and guests |
| | Visible | On | Whether the share shows up when browsing the network; hidden, it still opens by its address |
| | People | | **Clear the list** takes everyone off the share's list of people |
| Storage | Folder | `/var/lib/amahi-kai/files/<name>` | The folder on disk; click it to change it |
| | Size | | How much the share's files take up, counted when you ask |
| | Pool copies | Off | Whether Greyhole pools the share, and how many copies it keeps (see [Storage Pooling](storage-pooling)) |
| Trash | Deleted files | 30 days | Where the share's deleted files are kept, and for how long (see [Trash](#trash)) |
| Advanced | Samba settings | empty | Extra Samba settings for this share (Advanced mode only) |

---

## Permissions

- **All users on:** every Amahi-kai user can open the share, and change its files if **Writeable**
  is on.
- **All users off:** tick **Access** and **Writeable** for each user. They become Samba's
  `valid users` and `write list`.
- **Guests** (with All users off): read-only for guests unless their **Writeable** is on.
- **Clear the list** removes every per-user access and write grant on the share, so you can start
  over.

Users are managed on the **Users** tab. Each user gets a Linux account (used only for Samba; it
can't log in to the server) and a Samba password, kept in step with their web password.

---

## Samba configuration

Amahi-kai writes the whole `smb.conf`; don't edit it by hand, since changes get overwritten. A new
configuration is checked with `testparm` before it's installed, so a bad one can't take your
shares offline.

The global settings include:

- **Workgroup** (default `WORKGROUP`), changeable on **Setup → Shares → Settings** (Advanced mode)
- **Who can connect:** the server itself, your LAN and Tailscale only (`hosts allow`), on the LAN
  interface (and Tailscale's, if it's installed). Docker containers can't reach Samba.
- **Printer sharing off**
- **Greyhole settings** when Greyhole is installed (see [Storage Pooling](storage-pooling))

### Advanced Samba settings

With Advanced mode on, a share's **Advanced** section takes extra Samba settings for that share,
one per line, as `smb.conf` writes them. Amahi-kai checks them before Samba uses them, and refuses
ones that could run programs. Samba takes one `vfs objects` line per share, so the modules you add
there are joined with the ones Amahi-kai sets itself (Greyhole's on a pooled share, the recycle bin
for the Trash on any other). Amahi-kai sets the recycle bin's own settings, so `recycle:` lines are
left out.

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

Click **Files** in the header (or a share on the dashboard). The Shares page has a card for each
share you can open, with a pool or read-only badge, how many things it holds and its network
address. For admins, the [Trash](#trash) sits below them.

Inside a share:

- **A whole row is the link.** A folder opens. A file shows in the panel beside the list, with a
  preview for pictures, video and audio, its kind, size and date, **Download**, and **Open full
  screen** for pictures, video, audio, PDFs and text. Files with no preview say so.
- **The breadcrumbs** (Shares › the share › its folders) take you back up.
- **List or grid:** the grid shows pictures as themselves. The choice is remembered in that browser.
- **Download folder** zips the folder you're in, and the download button on a folder's row zips that
  one. The page says the zip is coming until the download starts; then the browser shows its
  progress.

The file browser only views: it doesn't upload, rename, move or delete. Files change over the
network share (SMB, above), so Samba, and [Greyhole](storage-pooling) on pooled shares, sees every
change, and each user's share permissions apply. Away from home, connect over
[Tailscale](remote-access) and use the share as usual. A stolen web login can't change your files.

Users only see the shares they have access to. HTML, JavaScript and XML files are shown as plain
text, and files open sandboxed (scripts in them can't run), so a file someone puts in a share
can't act on your Amahi-kai session. A folder download only includes the files that are in the
share.

---

## Trash

Every share keeps what's deleted from it over the network share. A pooled share's deleted files
stay on the pool drives, in Greyhole's trash; any other share's go to a hidden `.recycle` folder in
the share, which search leaves out. Temporary and lock files aren't kept.

For admins, **Trash** sits below the shares on the file browser's Shares page. It lists every
share's deleted files, newest first, with their size and the space they use.

- **Restore** puts a file back where it was (a pooled share's through Greyhole, which makes its
  copies again).
- **Delete** removes one for good, and **Empty trash** removes all of them.
- **Keep files** sets how long the Trash keeps them: 7, 14, 30 (the default), 60 or 90 days, or
  until emptied. A daily job (`amahi-kai-trash.timer`, on **Settings → Jobs**) deletes the older
  ones.

---

## File search

The search box searches file names across all shares, with filters for images, audio and video.
The index updates every 10 minutes (`amahi-kai-indexer.timer`). To rebuild it from scratch:

```bash
cd /opt/amahi-kai
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails shares:reindex"
```
