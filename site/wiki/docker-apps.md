---
layout: default
title: "Docker Apps"
---

# Docker Apps

Amahi-kai has a small catalog of apps that run in Docker containers. You install, start, stop
and uninstall them from the **Apps** tab. Each app runs on its own port of the server, as its own
user, with its own data folder, and keeps that data when it's uninstalled.

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

| App | What it's for | Open it at |
|-----|---------------|------------|
| **Jellyfin** | Your own streaming service for movies, TV and music | `http://<server>:8096` |
| **Vaultwarden** | A password manager server for the Bitwarden apps | `http://<server>:8880` |
| **Uptime Kuma** | Watches websites and services, and tells you when one goes down | `http://<server>:3001` |
| **Gitea** | Your own Git server, like a small GitHub | `http://<server>:3300` (Git over SSH on port 2222) |
| **Transmission** | A BitTorrent client with a web interface | `http://<server>:9091` (peers on port 51413) |

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

Once it's installed, **Open** on the Apps page and on the dashboard goes straight to the app.

**Set the app up right away.** Jellyfin, Uptime Kuma and Gitea ask the first person who opens
them to create the admin account, so open the app and do that as soon as it's installed.

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

Apps can't see your shares yet: giving an app a share or a ZFS dataset (Jellyfin's media, for
example) is planned next.

### Backing up an app's data

Stop the app on the Apps page, then copy its folder:

```bash
sudo cp -a /var/lib/amahi-kai/apps/jellyfin /path/to/backup/
```

Then start it again.

### App ports and the firewall

Docker writes its own firewall rules for the ports apps publish, ahead of UFW's, so an app's port
is reachable from your LAN even with UFW on. The [security audit](security) lists them.

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
- Make sure nothing else on the server uses its port: `sudo ss -ltnp | grep <port>`

### An app that ran out of memory

Each app has a memory limit (1 GB unless its definition sets another: Jellyfin has 2 GB). An app
that goes over it is restarted by Docker; its log says so.
