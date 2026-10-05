---
layout: default
title: "Docker Apps"
---

# Docker Apps

Amahi-kai has a small catalog of apps that run in Docker containers. You install, start, stop
and uninstall them from the **Apps** tab. Each app runs on its own port of the server, reachable
from your LAN and Tailscale, as its own user, with its own data folder, and keeps that data when
it's uninstalled.

---

## Prerequisites

Docker is **not** installed by default. Install it from the web UI:

1. Go to the **Apps** tab
2. Click **Install Docker**
3. Watch the streamed installation progress

Amahi-kai's root helper adds Docker's official apt repository (its signing key is checked
against a pinned fingerprint), installs Docker and turns the service on.

> Docker itself is root-level software: an app's container runs with whatever its image does.
> Amahi-kai only installs the apps in its catalog, each from a version that was checked, but only
> install apps you trust.

---

## The catalog

| App | What it's for | Usual address |
|-----|---------------|---------------|
| **Jellyfin** | Your own streaming service for movies, TV and music | `http://<server>:8096` |
| **Vaultwarden** | A password manager server for the Bitwarden apps | `http://<server>:8880` |
| **Uptime Kuma** | Watches websites and services, and tells you when one goes down | `http://<server>:3001` |
| **Gitea** | Your own Git server, like a small GitHub | `http://<server>:3300` (Git over SSH on port 2222) |
| **Transmission** | A BitTorrent client with a web interface | `http://<server>:9091` (peers on port 51413) |

If an app's usual port is already used by something else on the server, it gets the next free one
at install, and keeps it. The Apps page shows each installed app's ports.

Each app is defined by a small file in `config/apps/` in Amahi-kai's code: the image and its
exact version, its ports, its folders, its settings and a memory limit. Versions are pinned, so
installing an app always gets the version that was tested; newer versions come with Amahi-kai's
own updates. More apps are added when they're wanted.

---

## Installing an app

1. Go to the **Apps** tab
2. Click **Install** on the app
3. Watch the install window as Amahi-kai:
   - creates the app's own user (`app-<name>`) and its folders
   - generates its passwords or keys, if it has any
   - downloads the app's image
   - creates and starts its container
4. The last line says where to open it, for example `http://192.168.1.111:8096/`

Once it's installed, **Open** on the Apps page and on the dashboard goes straight to the app, on
its port.

## Reaching apps

- **On your LAN**: `http://<server>:<port>`, which is where **Open** goes.
- **Away from home: through [Tailscale](remote-access)**, at `http://<the server's Tailscale name
  or address>:<port>`.
- **Nowhere else.** Amahi-kai's firewall rules let connections into apps come only from the
  server's own LAN and from Tailscale, so a port forwarded on your router doesn't expose them.
- **Not through the Cloudflare Tunnel**: it carries Amahi-kai's own pages, not the apps'. There the
  Apps page says to open apps on your LAN or Tailscale.

Apps use plain HTTP, like Amahi-kai's own pages on the LAN. **Vaultwarden** needs HTTPS for its
web vault, so it's usable once HTTPS through Tailscale is added (later); until then only its
`/admin` page works.

**Set the app up right away.** Jellyfin, Uptime Kuma and Gitea ask the first person who opens
them to create the admin account, so open the app and do that as soon as it's installed.

### Giving an app shares

**Install** first asks which shares to give the app (none by default). They appear inside the app
at `/shares/<name>`: in Jellyfin, for example, add `/shares/Movies` as a library. To change them
later, click **Change** next to **Shares** on the app's row: the app restarts with the new ones,
keeping its data.

- Shares are **read only** unless you choose **Read and write**, which only apps that save files
  into shares offer (Transmission, for downloads).
- Shares that **Greyhole pools** are always read only to apps: their files change over SMB only.
- What an app saves into a share stays editable over SMB.
- **Everyone with an account in the app can see the shares you give it**, whatever the share's own
  list of users says. Give an app only the shares its users should see.

### Passwords and keys

Apps that need a password from the start get one generated at install, never a default one:

- **Vaultwarden**: the token for its `/admin` page
- **Transmission**: the web interface password (user `admin`)

An installed app's row on the Apps page has **Passwords and keys Amahi-kai made for …**: open it
to see them, with a **Copy** button. Only admins see the Apps page. Reinstalling keeps the same
values.

---

## Managing apps

### Start / Stop / Uninstall

Use the buttons on the app's row. The page shows what Docker reports, so an app that stopped on
its own shows as stopped, and one whose container was removed outside Amahi-kai shows an error
with **Install again**.

**Uninstall keeps the app's data.** It removes the container and its image; the app's folder,
passwords and user stay, and installing the app again picks them up. To delete the data too,
uninstall the app, then click **Delete it** on its row (it says its data from an earlier install
is kept).

### Updating an app

Each installed app's row says which version it runs. When an Amahi-kai update brings a newer
version of an app into the catalog, its row offers **Update to <version>**, next to **What's
new** (the release notes). Nothing updates on its own.

**Update**:

1. Copies the app's data. Caches and Transmission's downloads are left out. It stops first if
   there isn't room for the copy.
2. Starts the new version, and waits up to 5 minutes for it to come up healthy.
3. If it doesn't come up, puts the old version and its data back by itself, and says why.

The copy is kept for **30 days**. During that time **Undo update** on the row puts the old
version back, with the app's data as it was before the update; anything changed since is lost.
A later update replaces the copy, and it's deleted after 30 days (Settings → Jobs: **App update
copies**).

New versions reach the catalog by hand: someone runs `script/app-versions`, reads the release
notes, and makes the change in Amahi-kai's code (see `config/apps/README.md`).

### From the command line

The web UI is the usual way; these are for looking closer:

```bash
sudo docker ps --filter label=amahi.app
```

```bash
sudo docker logs amahi-jellyfin
```

---

## App data

Each app's data is in its own folder, owned by the app's user:

```
/var/lib/amahi-kai/apps/
  jellyfin/
    config/
    cache/
  vaultwarden/
    data/
  gitea/
    data/
    config/
```

Generated passwords are in `/var/lib/amahi-kai/app-secrets/<app>.json`, readable only by root and
Amahi-kai.

Shares you give an app stay where they are: the app reads (or writes) them in place. Giving an
app storage on a ZFS pool comes with bitShare.

### Backing up an app's data

Stop the app on the Apps page, then copy its folder:

```bash
sudo cp -a /var/lib/amahi-kai/apps/jellyfin /path/to/backup/
```

Then start it again.

### App ports and the firewall

Docker writes its own firewall rules for the ports apps publish, ahead of UFW's, so UFW doesn't
filter them. Amahi-kai adds its own rules in Docker's chain each time Docker starts: connections
into an app from anywhere but the server's private networks and Tailscale are dropped. The
[security audit](security)'s **Docker ports** check says whether they're in place. To see them:

```bash
sudo iptables -S AMAHI-APPS
```

---

## Troubleshooting

### The install window ends with ✗

The line above it says why (for example, the image couldn't be downloaded). Fix that and click
**Install again**. The root helper's log has every step:

```bash
sudo tail -n 40 /var/log/amahi-kai/helper.log
```

### The app's page doesn't open

- Check the app shows **Open** (running) on the Apps page
- Look at its log: `sudo docker logs amahi-<app>`
- Use the port on its row (it may not be the usual one)
- From outside your LAN, use Tailscale: apps aren't reachable any other way

### An app that ran out of memory

Each app has a memory limit (1 GB unless its definition sets another: Jellyfin has 2 GB). An app
that goes over it is restarted by Docker; its log says so.
