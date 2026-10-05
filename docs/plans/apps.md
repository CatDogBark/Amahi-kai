# Phase 4: apps

Status: planned with Troy, 2026-10-05; P4.1 is done (#58). The overall decisions and P4.1's are made (below); each
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
  Tailscale.
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
  the five has been tested with Amahi-kai yet; each is tested on the new model.
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

Each app on its own port, `/app/<id>` retired, the dashboard and Apps pages linking to each app's
own address.

- [ ] Which apps the LAN can reach and which stay local-only (reached only through their tunnel
  hostname); the default for new installs.
- [ ] Ports: the catalog's usual port (8096 for Jellyfin) or picked automatically when it's taken.
- [ ] Binding: all interfaces (today), or the LAN and Tailscale addresses only, given that Docker's
  rules come before UFW.
- [ ] Host networking (some apps want it to find devices on the LAN): allowed for named apps, or
  never.
- [ ] Keep router mode possible (roadmap, Direction): binding and firewall choices mustn't assume
  the NAS only ever sits on someone else's LAN. Apps face the LAN side, never the internet side.
- [ ] HTTPS on the LAN: plain HTTP like the admin UI, or certificates.
- [ ] Apps' outgoing internet access: allowed by default (most need it for metadata and updates), or
  opt-in.

### P4.3: Apps from anywhere (Cloudflare Tunnel)

- [ ] Hostname naming (`jellyfin.example.com`, or chosen per app).
- [ ] Which apps may be published at all, and whether each needs Cloudflare Access in front.
- [ ] How the tunnel's routes are written (the helper writes cloudflared's ingress rules from the
  apps that have a hostname).

### P4.4: Storage for apps

- [ ] Shares an app may mount: chosen at install, read-only by default; read-write only for shares
  that aren't pooled (Greyhole), per the storage plan.
- [ ] How an app's user may read shares (group membership, ACLs), given shares' per-user
  permissions.
- [ ] ZFS datasets: one per app on the pool chosen at install (moved here from storage S4); quotas
  or not; the app's snapshots are the pool's.
- [ ] Uninstall: keep the data (default) or delete it, and how leftover data is shown and cleaned
  up later.
- [ ] Backups of app data (Proton Drive comes later as its own app).

### P4.5: App updates

- [ ] Manual (an Update button when the catalog has a newer pinned version) or automatic.
- [ ] Rollback to the previous image if the new one doesn't come up healthy.
- [ ] How often the catalog's versions are bumped, and by whom (a Claude session, a script).
- [ ] Showing what changed (the app's release notes link).

### P4.6: bitShare as the first built-in app

- [ ] How bitShare signs people in: Amahi-kai's users (so one account works for both), or its own.
- [ ] How bitShare uses snapshots and datasets (through the helper, as any app would).
- [ ] Where its image comes from (built from `~/Projects/bitShare` and published, then pinned in the
  catalog like any app).

### Also in Phase 4

- The wiki's Docker Apps page rewritten for the new model, with the plain statement that Docker
  itself is root-level software: install apps you trust.
- The security audit's Docker ports check updated for the new port binding.
- GPU access for transcoding (`/dev/dri`) waits: the NAS VM has no GPU.
