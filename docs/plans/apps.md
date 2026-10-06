# Phase 4: apps

Status: planned with Troy, 2026-10-05; P4.1 (#58), P4.2 (#59), P4.4 (#60) and P4.5 (#62) are done,
not yet tested on the NAS ([`docs/testing/apps.md`](../testing/apps.md)). The overall decisions and P4.1's are made (below); each
later PR's decisions are listed under it, to settle when that PR starts.

Apps are how Amahi-kai grows: Jellyfin, Vaultwarden and the like today, bitShare (and later
bitTube) as first-class apps on the same model. Phase 4 rebuilds how apps are installed, run,
reached and stored, so that installing an app can't give it more than it was meant to have.

## Where apps are today

- **A catalog of 13 apps** (`config/docker_apps/catalog.yml`). Images aren't pinned (each install
  pulls whatever `latest` is that day), a few entries ship default passwords, entries can pass any
  extra `docker` arguments, and Portainer is given Docker's socket (full control of the NAS).
- **The web app runs Docker through sudo, and its user is in the `docker` group.** Either is root on
  the NAS: whoever controls the web app could start any container with any host folder mounted.
  This is the one root path the privileged-helper work (L–Q) didn't close.
- **App folders are world-writable** (`chmod -R 777` on `/opt/amahi/apps/<app>`), and every app's
  container runs as the same user (`PUID 1000`).
- **Uninstalling deletes the app's data.**
- **Apps are reached through `/app/<id>`**, a proxy inside Amahi-kai that buffers whole responses
  (no streaming, no large uploads) and serves every app from Amahi-kai's own web address, so an
  app's pages run alongside Amahi-kai's admin pages.
- **Ports are published on every interface**, and Docker's firewall rules come before UFW's (the
  security audit's "Docker ports" check warns about it).
- **No way to give an app a share or a pool dataset**: the media folder Jellyfin gets is fixed in
  the catalog.
- No apps are installed on Troy's NAS (the dashboard shows 0), so nothing has to be migrated.

## Goals

1. **Bounded apps**: an app gets exactly what its definition grants (its own folders, the shares or
   dataset chosen at install, its ports), and the web app can't run anything else.
2. **Each app reached on its own**, not through Amahi-kai's address: fast, streaming, its own
   origin.
3. **Storage that fits the storage plan**: apps' own data in their own folder, big data on a ZFS
   dataset, shares only as chosen (never a pooled share to write into), data kept on uninstall.
4. **Predictable**: pinned versions, secrets generated per install, updates on purpose.
5. **bitShare can be built on it** without special cases.

## Overall decisions

These shape every PR after them.

- [x] **O1. Who runs Docker.** Recommended: **the root helper, as the only way in.** The helper
  creates, starts, stops and removes containers only from a validated app definition: no free-form
  Docker arguments, no Docker socket, no host folders outside the app's own and the ones granted.
  The web app loses `sudo docker` and the `docker` group. Alternatives: keep `sudo docker` (simple,
  but the web app stays root-equivalent); rootless Docker or Podman per app (stronger isolation, but
  a larger change: ports below 1024, file ownership on shares, a second container runtime).
  **Decided: the helper** (Troy, 2026-10-05). This is about what may start containers inside the
  NAS, not about reaching apps remotely (that's O3).
- [x] **O2. How an app is defined.** Recommended: **a small manifest of our own** (YAML in the repo),
  with only the fields Amahi-kai supports (image and version, ports, folders, storage it asks for,
  environment with generated secrets, a health check, memory limit), each checked by the helper.
  Alternative: Docker Compose files (familiar, but full of ways around the checks: privileged
  mode, devices, host networking, any host folder). **Decided: our own manifest.**
- [x] **O3. How you reach an app.** Recommended: **each app on its own port** on the NAS
  (`http://192.168.1.111:8096`), with an **optional Cloudflare Tunnel hostname per app** for remote
  use (Tailscale reaches the ports anyway), and **`/app/<id>` retired**. Alternative: a reverse
  proxy with a hostname per app on the LAN (`jellyfin.nas.lan`): nicer addresses, but it needs
  local DNS (dnsmasq isn't running on the NAS) and certificates. **Decided: own ports, with remote
  use required**: bitShare and other apps must work through the Cloudflare Tunnel (P4.3) or
  Tailscale. **Updated with P4.2 (Troy, 2026-10-04): Tailscale is the default way to reach apps
  from outside**; a Cloudflare hostname for an app is a specialty case, built later if wanted.
- [x] **O4. Where apps keep data.** Recommended: **each app gets its own system user and folder**
  (`/var/lib/amahi-kai/apps/<app>`, owned by that user, no `777`), and its container runs as that
  user. Big data goes on a **ZFS dataset** of its own (`<pool>/<app>`) when the app asks for storage
  and a pool exists. Shares are mounted **read-only or read-write as chosen at install**, never a
  pooled share read-write. **Uninstall keeps the data** unless you ask for it to go. **Decided.**
- [x] **O5. The catalog.** Recommended: **curated in this repo**, versions pinned, updated with
  Amahi-kai's own updates; no third-party catalogs for now. Apps that only work with root-level
  access (Portainer needs Docker's socket) leave the catalog. **Decided**, and the catalog is
  pruned to five apps (A5); more are added when wanted.
- [x] **O6. bitShare.** Recommended: **an app on this same model** (its own manifest, dataset, port
  and hostname), with no special path into Amahi-kai, so anything bitShare needs becomes a feature
  every app can use. **Decided**; bitShare is designed to run as a single container (A7).
- [x] **O7. Start fresh.** Recommended: no apps are installed, so the old install code, the
  `DockerApp` records and `/opt/amahi/apps` layout are replaced rather than migrated. This is the
  install machinery, not the app list; the list was pruned first (A5). **Decided.**

## PRs

### P4.1: Apps through the root helper (the foundation)

**Done** (#58). Manifests are in `config/apps` (format in its README). The Open buttons already use
each app's own port; `/app/<id>` stays until P4.2 retires it.

- The manifest format, and the catalog converted to it (pinned versions, no default passwords,
  no free-form arguments, apps that need root-level access dropped).
- Helper operations: install (pull the pinned image, create the app's user and folders, create the
  container from the manifest), start, stop, restart, uninstall (removes the container; keeps the
  data unless asked), status. Every field validated by the helper.
- Secrets generated at install, kept where only root and the app can read them, shown to admins on
  the app's page.
- Memory limit per app from its manifest.
- The last sudo rules besides the helper's removed (`docker`, and `mkdir`, `cp` and `rm -rf` under
  `/opt/amahi`), and the web app's user taken out of the `docker` group: the helper becomes the
  only thing the web app can run as root. Docker's install stays as it is.
- The Apps pages use it; the old installer and `/opt/amahi/apps` folders go.

Decisions for this PR:

- [x] **A1. Version pinning.** Recommended: tag **and digest** (`jellyfin:10.10.7@sha256:…`), so an
  install gets exactly the tested image; updates are explicit catalog changes. Alternatives: tag
  only (the same tag can be rebuilt), or `latest` (today). **Decided: tag and digest.**
- [x] **A2. Generated secrets.** Recommended: generated at install (admin passwords, keys), kept in a
  file per app readable by root and that app, and shown to admins on the app's page with a copy
  button. Alternative: shown once at install and never again. **Decided: kept, shown to admins.**
- [x] **A3. App folders.** Recommended: `/var/lib/amahi-kai/apps/<app>`, with the rest of
  Amahi-kai's state. Alternative: keep `/opt/amahi/apps` (what the wiki tells people to back up).
  **Decided: `/var/lib/amahi-kai/apps`.**
- [x] **A4. One user per app.** Recommended: a system user per app (`app-jellyfin`), so one app can't
  read another's data. Alternative: one shared `amahi-apps` user (simpler; apps can read each
  other's files). **Decided: one per app.**
- [x] **A5. Which apps stay in the catalog.** **Decided (Troy, 2026-10-05): Jellyfin, Vaultwarden,
  Uptime Kuma, Gitea and Transmission.** Dropped: Portainer (Docker's socket is root), Nextcloud
  and Syncthing (bitShare covers sync), Home Assistant (its container version has no add-ons and
  needs host networking to find devices; if wanted, Home Assistant OS runs better as its own
  Proxmox VM), Audiobookshelf, Pi-hole, Paperless-ngx (broken as defined: no Redis, a `changeme`
  secret) and Grafana (empty without a metrics source). Apps are added later when wanted. None of
  the five has been tested with Amahi-kai yet; each is tested on the new model. **bitTube**
  (Troy's own app, `CatDogBark/bitTube`, from GitHub's registry) joined the catalog on
  2026-10-05, as the sixth.
- [x] **A6. Default memory limit** for apps whose manifest doesn't set one, on an 8 GB VM shared with
  ZFS's 2 GB cache. Recommended: 1 GB, with Jellyfin set higher in its manifest. **Decided** (Troy
  is raising the VM to 8 GB).
- [x] **A7. One container per app.** **Decided (Troy, 2026-10-05):** the manifest describes a single
  container. All five apps keep their data in a built-in database file (SQLite) or need none.
  Apps built from several containers (an app plus its database server and Redis, like Immich or
  a working Paperless-ngx) wait until one is wanted; companion support is designed then, with that
  app. Companions' advantage is updating each part from its official image; their cost is start
  order, a private network, database backups and more for the helper to check.

### P4.2: Reaching apps

**Done** (#59). Each app on its own port, `/app/<id>` retired, the dashboard and Apps pages linking
to each app's own address.

Decisions (Troy, 2026-10-04):

- [x] **Who can reach an app's port: the LAN and Tailscale only.** The helper's `apps.firewall`
  adds a chain (`AMAHI-APPS`) to Docker's `DOCKER-USER`: new connections into a container are
  dropped unless they come from Tailscale (`tailscale0`) or one of the NAS's own private subnets.
  `amahi-kai-app-firewall.service` runs it each time Docker starts or restarts, and every install
  runs it too. Traffic from the NAS itself (cloudflared) isn't filtered. Apps are published on IPv4
  only. This keeps router mode possible: an internet-facing port would never reach apps.
- [x] **Tunnel-only apps: not built.** Tailscale is the default way to reach apps from outside;
  a per-app Cloudflare hostname is a specialty case (P4.3, later).
- [x] **Ports: automatic.** An app gets its catalog port when it's free, otherwise the next free
  one, and keeps it through reinstalls (`/var/lib/amahi-kai/app-ports.json`). The Apps page shows
  every port each app uses.
- [x] **Plain HTTP on the LAN**, like the admin UI. Vaultwarden's web vault needs HTTPS, so it
  waits for HTTPS through Tailscale (later; turned on in the Tailscale admin console).
- [x] **No host networking.** Docker forwards each app's ports to its container; an app with the
  NAS's own network could open any port and get around the rules above.
- [x] **Outgoing internet access allowed** (metadata, monitors, peers, mirrors).

### P4.3: Apps through Cloudflare (optional, later)

A specialty case since P4.2: Tailscale is the default way to reach apps from outside. Built if an
app needs a public hostname. HTTPS for apps through Tailscale (Vaultwarden needs it) comes first.

- [ ] Hostname naming (`jellyfin.example.com`, or chosen per app).
- [ ] Which apps may be published at all, and whether each needs Cloudflare Access in front.
- [ ] How the tunnel's routes are written (the helper writes cloudflared's ingress rules from the
  apps that have a hostname).

### P4.4: Storage for apps

**Done** (#60): shares for apps. Decisions (Troy, 2026-10-04):

- [x] **Shares chosen at install**, none by default, and changed later from the app's row (a
  reinstall with the new shares: the container is recreated, data and ports kept, and the image
  isn't downloaded again).
- [x] **Read only by default; read and write only for shares Greyhole doesn't pool**, and only for
  apps whose manifest says `writes_shares` (Transmission). A pooled share's files are links to
  their copies on the drives, so the app also gets that share's copy folder on each Greyhole drive,
  read only, at the same path. A share an app writes into gets a default ACL on its folders, so
  what the app makes is group-writable (`users`, like files made over SMB) whatever its umask; the
  app joins the `users` group in its container.
- [x] **Any share can be given**, and the dialog says that everyone with an account in the app can
  see it, whatever the share's own user list says (Samba enforces those, not the folders: every
  share folder is `users` 2775, files 0664).
- [x] **Shares appear at `/shares/<name>`** in every app. The web app names shares; the helper
  finds their folders in smb.conf (which only it writes) and checks they're in the share root or
  on a mounted data drive.
- [x] **ZFS datasets for apps wait for bitShare (P4.6)**: none of the five apps needs one, and
  there's no pool yet to test with.
- [x] **Backups of app data wait** (Proton Drive as its own app, or app data on a pool). Proxmox
  backups of the NAS VM cover it meanwhile.
- [x] Uninstall keeps the data unless asked (P4.1).

### P4.5: App updates

**Done** (#62). Decisions (Troy, 2026-10-05):

- [x] **Manual.** An installed app's row offers **Update to <version>** when the catalog (fetched on
  its own since P4.5b) has another version than the one it runs. Installing again and changing shares
  keep the version it runs; only Update changes it.
- [x] **A copy first, and rollback.** The helper (`apps.update`) copies the app's folders (all but
  those the manifest marks `backup: false`: Jellyfin's cache, Transmission's downloads) after
  checking there's room, starts the new version, and waits up to 5 minutes for it to be healthy:
  Docker's own health check where the image has one (Jellyfin, Uptime Kuma, Vaultwarden),
  otherwise its web page answering and the container still running 10 seconds later (Gitea,
  Transmission). If it isn't, the old version and the copied data are put back.
- [x] **One copy per app, kept 30 days, for Undo update** (`apps.undo_update`); the next update
  replaces it, and `amahi-kai-app-backups.timer` deletes it after 30 days (`apps.prune_backups`).
  Copies are in `/var/lib/amahi-kai/app-backups` (root only; a description beside each copy for
  the Apps page).
- [x] **Version bumps are a person's job, no automation.** `script/app-versions` lists newer
  releases of the same tag shape (and newer builds of the pinned tag) with release notes links;
  `--update APP` writes the new tag and digest. Someone reads the notes and opens a PR. No bot,
  no schedule, no Claude session runs it.
- [x] **What's new** links to the new version's release notes (the manifest's `releases`).

### P4.5b: The catalog's own repo

Decided (Troy, 2026-10-06): app updates mustn't wait for an Amahi-kai update.

- [x] **A repo of its own**, [CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps):
  one manifest per app in `apps/<id>.yml`, the same fields as before. Its CI runs this repo's
  helper on it (`amahi-helper --check-catalog apps`), so a manifest the NAS would refuse can't be
  merged. An app update is a PR there (`script/app-versions --catalog ../amahi-kai-apps/apps
  --update APP`).
- [x] **Fetched by the root helper** (`apps.refresh_catalog`) every 6 hours
  (`amahi-kai-catalog.timer`) and on the Apps page's **Check now**: main, over https only, into a
  bare repo of root's (`/var/lib/amahi-kai/catalog-src`), with git's hooks off. Every manifest is
  checked as an install would check it, plus what the pages show (name, description, category,
  logo and release notes on https); the ones that pass are written beside the current catalog
  and swapped in (`/var/lib/amahi-kai/catalog/apps`). One that fails is skipped and named on the
  Apps page; a fetch that fails, or finds nothing that passes, keeps the catalog there was. What
  happened is in `/var/lib/amahi-kai/catalog-status.json`. Trust is unchanged: System Update pulls
  Amahi-kai's own code from the same GitHub account.
- [x] **The fetched catalog comes first** for the helper and the pages; `config/apps` is the copy
  that comes with Amahi-kai, for a NAS that hasn't fetched one yet, and for an app the catalog
  no longer lists. Bring it up to date with the repo now and then.
- [x] **Formats.** A manifest's `requires` (default 1) is the catalog format it needs. This
  Amahi-kai knows format 1 (`CATALOG_FORMAT`, `AppCatalog::FORMAT`); an app or update that needs
  more is listed with "Needs a newer Amahi-kai: run System Update first", and the helper refuses
  to install it. A new manifest field raises the format, so older NASes don't misread it.

### P4.5c: Apps on the LAN

Troy (2026-10-06): the NAS knows what it runs, so devices shouldn't have to be told its address.

- [x] **Announced over mDNS** by Avahi (`avahi-daemon`, installed by `bin/amahi-install`, and by
  `bin/amahi-update` on NASes from before): each installed app with a web page is an HTTP service
  named "<App> on <hostname>" on the port it was given, with the subtype `_<id>._sub._http._tcp`
  so one app can be asked for (bitTube Desktop asks for `_bittube._sub._http._tcp`). The helper's
  `apps.announce` writes `/etc/avahi/services/amahi-app-<id>.service` for the installed apps and
  removes the others of its own; it runs after every install and uninstall and each time Docker
  starts (`amahi-kai-app-firewall.service`). UFW lets mDNS (5353/udp) in, both when the security
  audit turns UFW on and at each announce when it's on already.

### P4.6: bitShare as the first built-in app

- [ ] ZFS datasets for apps (from P4.4): one per app on the pool chosen at install; quotas or not;
  the app's snapshots are the pool's.
- [ ] How bitShare signs people in: Amahi-kai's users (so one account works for both), or its own.
- [ ] How bitShare uses snapshots and datasets (through the helper, as any app would).
- [ ] Where its image comes from (built from `~/Projects/bitShare` and published, then pinned in the
  catalog like any app).

### Also in Phase 4

- The wiki's Docker Apps page rewritten for the new model, with the plain statement that Docker
  itself is root-level software: install apps you trust.
- The security audit's Docker ports check updated for the new port binding.
- GPU access for transcoding (`/dev/dri`) waits: the NAS VM has no GPU.
