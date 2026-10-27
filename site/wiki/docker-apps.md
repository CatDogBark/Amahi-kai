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
| **bitTube** | Your YouTube channels and streaming services in one place, YouTube ad-free | `http://<server>:8484` |
| **Jellyfin** | Your own streaming service for movies, TV and music | `http://<server>:8096` |
| **PiGallery2** | Your photos and home videos as a gallery, folder by folder, as they are on the NAS | `http://<server>:8098` |
| **Vaultwarden** | A password manager server for the Bitwarden apps; reached only through Tailscale, over HTTPS (see below) | `https://<the server's name on your tailnet>:8880` |
| **Uptime Kuma** | Watches websites and services, and tells you when one goes down | `http://<server>:3001` |
| **Gitea** | Your own Git server, like a small GitHub | `http://<server>:3300` (Git over SSH on port 2222) |
| **Transmission** | A BitTorrent client with a web interface | `http://<server>:9091` (peers on port 51413) |
| **bitShare** (early: version 0.3, a project of its own) | Keeps folders in sync across your computers through the NAS, every version kept; its data goes on a ZFS pool | `https://<server>:8443` (its own certificate: the browser warns once) |

If an app's usual port is already used by something else on the server, it gets the next free one
at install, and keeps it. The Apps page shows each installed app's ports.

Each app is defined by a small file, its manifest, in the app catalog,
[CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps): the image and its exact
version, its ports, its folders, its settings and a memory limit. Versions are pinned, so
installing an app always gets the version that was tested. Amahi-kai fetches the catalog with its
update check, every 6 hours, so new apps and new versions arrive without an Amahi-kai update. To
make an app of your own, see [Making Apps](making-apps).

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

An install, update or uninstall runs as a job of its own on the server, so it finishes even if the
page is closed or Amahi-kai's web page restarts meanwhile; the app's row catches up when you
open the Apps page again. While one runs for an app, its other buttons wait for it.

Once it's installed, **Open** on the Apps page and on the dashboard goes straight to the app, on
its port.

### Apps on your network

Each installed app is announced on your LAN (mDNS, through Avahi), as "bitTube on <your server>",
"Jellyfin on <your server>" and so on, so devices and apps can find it without being told the
server's address: bitTube Desktop finds bitTube that way. **Settings → Servers** lists Avahi.

## Reaching apps

- **On your LAN**: `http://<server>:<port>`, which is where **Open** goes.
- **Away from home: through [Tailscale](remote-access)**, at `http://<the server's Tailscale name
  or address>:<port>`.
- **Nowhere else.** Amahi-kai's firewall rules let connections into apps come only from the
  server's own LAN and from Tailscale, so a port forwarded on your router doesn't expose them.
- **Not through the Cloudflare Tunnel**: it carries Amahi-kai's own pages, not the apps'. There the
  Apps page says to open apps on your LAN or Tailscale.

Apps use plain HTTP, like Amahi-kai's own pages on the LAN, except the ones reached only through
Tailscale.

### Apps reached only through Tailscale

Some apps can't work over plain HTTP: browsers won't run **Vaultwarden**'s web vault without
HTTPS, since it encrypts your passwords in the page, and the Bitwarden apps refuse a server that
isn't HTTPS. Those apps are reached only from devices on your Tailscale network, over HTTPS, at
the server's name there: `https://<name>.<your tailnet>.ts.net:8880` for Vaultwarden. Nothing on
the LAN reaches them, and they aren't announced there. The Apps page says **Tailscale only** on
their row, and **Open** goes to that address.

They need, before they're installed:

1. **Tailscale on the server**, connected (Network → Remote Access).
2. **MagicDNS** and **HTTPS Certificates** on for your tailnet, in Tailscale's admin console under
   **DNS**. HTTPS Certificates only lets your devices ask Tailscale for a certificate for their
   own name; it changes nothing else. Remote Access shows whether it's on.
3. **Tailscale on each device** that uses the app, at home too: it connects straight over the LAN
   when it can. To share with your household, add them to your tailnet, or share the server with
   theirs.

The certificate is Tailscale's, for the server's name on your tailnet, renewed by Tailscale. Like
every public certificate it's listed in public certificate logs, so the server's name on your
tailnet (not its address) is public.

**Vaultwarden**: open its address on a device on your tailnet and create your account; the
Bitwarden apps and browser extensions take the same address: choose self-hosted on their sign-in
screen.
It lets anyone who can reach it make an account, so once your household has theirs, turn
sign-ups off on its admin page (`/admin`, with the token on its row).

If you rename the server in Tailscale, give the app its new address: **Change** next to its shares,
then **Save and restart**.

**Set the app up right away.** Jellyfin, Uptime Kuma and Gitea ask the first person who opens
them to create the admin account, so open the app and do that as soon as it's installed.

### Giving an app shares

**Install** first asks which shares to give the app (none by default). They appear inside the app
at `/shares/<name>`: in Jellyfin, for example, add `/shares/Movies` as a library. To change them
later, click **Change** next to **Shares** on the app's row: the app restarts with the new ones,
keeping its data and the version it runs. The new container is made before the old one goes, so a
change that fails leaves the app as it was, running.

A share whose folder is a link (to somewhere else on the server) isn't given to an app.

**Only some folders of a share** can be given instead of all of it: tick the share, choose **Only
some folders**, and pick each folder in the share's folders (**+ Add a folder**). Each appears in
the app where it is in the share, at `/shares/<name>/<folder>` (`/shares/Vault/media/Pictures`),
so an app's own settings keep working when you narrow what it's given, and the rest of the share
is out of the app's reach. A share can give several folders, none inside another.

- Amahi-kai mounts each folder given to an app itself, after checking that it's a real folder and
  that no link is on the way to it, and mounts it again before Docker starts the apps after a
  restart (`amahi-kai-app-shares.service`): a folder an app could write in can't be swapped for a
  link to elsewhere on the server.
- A folder renamed, moved or deleted after it was given keeps the app from starting until you
  give it its folders again with **Change**; the app's row says which folder is missing.
- Moving a file from one folder given to an app to another one, inside the app, copies it: each
  folder is mounted on its own.

- Shares are **read only** unless you choose **Read and write**, which only apps that save files
  into shares offer (Transmission, for downloads); each folder given has its own.
- Shares that **Greyhole pools** are always read only to apps: their files change over SMB only.
  When the storage pool changes (a drive joins or leaves it, or a share's pool copies turn on or
  Off), the apps given a pooled share restart with the pool as it is now, so they keep reading
  its files and don't hold on to a drive taken out of the pool. A stopped app stays stopped.
  The same happens when Docker starts and when a pool drive is mounted again, so a drive
  missing at boot doesn't keep an app from starting.
- What an app saves into a share stays editable over SMB.
- **Everyone with an account in the app can see the shares you give it**, whatever the share's own
  list of users says. Give an app only the shares its users should see.

### Passwords and keys

Apps that need a password from the start get one generated at install, never a default one:

- **Vaultwarden**: the token for its `/admin` page (Vaultwarden itself is given only a hash of it)
- **Transmission**: the web interface password (user `admin`)
- **PiGallery2**: the gallery's password (user `admin`)

An installed app's row on the Apps page has **Passwords and keys Amahi-kai made for …**: open it
to see them, with a **Copy** button. Only admins see the Apps page. Reinstalling keeps the same
values.

---

## Managing apps

### Start / Stop / Uninstall

Use the buttons on the app's row. The page shows what Docker reports, so an app that stopped on
its own shows as stopped, and one whose container was removed outside Amahi-kai shows an error
with **Install again**. They work for an app the catalog no longer lists too.

**Uninstall keeps the app's data.** It removes the container and its image; the app's folder,
passwords and user stay, and installing the app again picks them up, on the version it ran (Update
then moves it on, with a copy first). To delete the data too, uninstall the app, then click
**Delete it** on its row (it says its data from an earlier install is kept). Uninstall waits for
Docker to be running.

### Updating an app

Each installed app's row says which version it runs. When the update check (every 6 hours, or
**Check now**) finds a newer version of an app in the catalog, the dashboard says so, the update
button in the header gets its dot, and the app's row offers **Update to <version>**, next to
**What's new** (the release notes). Nothing updates on its own, and a catalog version older than
the one an app runs isn't offered.

**Update**:

1. Copies the app's data. Caches and Transmission's downloads are left out, and data on a ZFS pool
   is snapshotted instead of copied. It stops first if there isn't room for the copy, and a copy
   that fails starts the app again on the version it ran.
2. Starts the new version, and waits up to 5 minutes for it to come up healthy.
3. If it doesn't come up, puts the old version and its data back by itself, and says why.

The copy is kept for **30 days**. During that time **Undo update** on the row puts the old
version back, as it ran, with the app's data as it was before the update; anything changed since is
lost, and for data on a ZFS pool, so are the pool's own snapshots of it taken since. If the old
version's image is gone, it's downloaded again first; nothing changes if it can't be.
A later update replaces the copy, and it's deleted after 30 days (Settings → Jobs: **App update
copies**).

New versions reach the catalog by hand: someone reads the release notes and changes the app's
manifest in the catalog (see [Making Apps](making-apps)). An app that needs a newer Amahi-kai than
yours says "Needs a newer Amahi-kai: run System Update first" instead of offering Install or
Update.

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

Shares you give an app stay where they are: the app reads (or writes) them in place.

### Apps that keep their data on a ZFS pool

Some apps keep the data that grows on a ZFS pool (bitShare's files, say), so it isn't on the
system disk. Installing one asks for the pool, under **Storage**; it can't be installed before
there's a pool (**Disks → ZFS Pools**). Its data goes in a dataset of its own,
`<pool>/apps/<app>` (mounted at `/srv/pools/<pool>/apps/<app>`), and stays on that pool: its
settings stay in its folder on the system disk. The app's row says which pool.

- The pool's hourly and daily snapshots cover it. **Rolling the pool back** stops the app while
  it runs, then starts it again: its data goes back too.
- A pool can't be taken offline or deleted while an installed app keeps its data on it.
- **Update** snapshots the dataset instead of copying it, and **Undo update** rolls back to it.
- **Uninstall** keeps the dataset; **Delete it** deletes it too. To move an app to another pool,
  uninstall it, delete its data, and install it again on the other one.

### Backing up an app's data

Stop the app on the Apps page, then copy its folder:

```bash
sudo cp -a /var/lib/amahi-kai/apps/jellyfin /path/to/backup/
```

Then start it again.

### App ports and the firewall

Docker writes its own firewall rules for the ports apps publish, ahead of UFW's, so UFW doesn't
filter them. Amahi-kai adds its own rules in Docker's chain before Docker starts, and again each time
it starts and whenever router mode or the server's address changes: connections into an app from
anywhere but the server's private networks and Tailscale are dropped. The
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
that goes over it is restarted by Docker; its log says so. Each app can also run at most 2,048
processes, keeps at most 30 MB of logs (three files of 10 MB), and can't use raw sockets or make
device files.
