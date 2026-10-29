# Phase 4: apps

Status: planned with CatDogBark, 2026-10-05; P4.1 (#58), P4.2 (#59), P4.4 (#60) and P4.5 (#62) are done,
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
- No apps are installed on CatDogBark's NAS (the dashboard shows 0), so nothing has to be migrated.

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
  **Decided: the helper** (CatDogBark, 2026-10-05). This is about what may start containers inside the
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
  Tailscale. **Updated with P4.2 (CatDogBark, 2026-10-04): Tailscale is the default way to reach apps
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
- [x] **A5. Which apps stay in the catalog.** **Decided (CatDogBark, 2026-10-05): Jellyfin, Vaultwarden,
  Uptime Kuma, Gitea and Transmission.** Dropped: Portainer (Docker's socket is root), Nextcloud
  and Syncthing (bitShare covers sync), Home Assistant (its container version has no add-ons and
  needs host networking to find devices; if wanted, Home Assistant OS runs better as its own
  Proxmox VM), Audiobookshelf, Pi-hole, Paperless-ngx (broken as defined: no Redis, a `changeme`
  secret) and Grafana (empty without a metrics source). Apps are added later when wanted. None of
  the five has been tested with Amahi-kai yet; each is tested on the new model. **bitTube**
  (CatDogBark's own app, `CatDogBark/bitTube`, from GitHub's registry) joined the catalog on
  2026-10-05, as the sixth.
- [x] **A6. Default memory limit** for apps whose manifest doesn't set one, on an 8 GB VM shared with
  ZFS's 2 GB cache. Recommended: 1 GB, with Jellyfin set higher in its manifest. **Decided** (CatDogBark
  is raising the VM to 8 GB).
- [x] **A7. One container per app.** **Decided (CatDogBark, 2026-10-05):** the manifest describes a single
  container. All five apps keep their data in a built-in database file (SQLite) or need none.
  Apps built from several containers (an app plus its database server and Redis, like Immich or
  a working Paperless-ngx) wait until one is wanted; companion support is designed then, with that
  app. Companions' advantage is updating each part from its official image; their cost is start
  order, a private network, database backups and more for the helper to check.

### P4.2: Reaching apps

**Done** (#59). Each app on its own port, `/app/<id>` retired, the dashboard and Apps pages linking
to each app's own address.

Decisions (CatDogBark, 2026-10-04):

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
  waited for HTTPS through Tailscale (turned on in the Tailscale admin console): P4.7, where it's
  reached only through Tailscale.
- [x] **No host networking.** Docker forwards each app's ports to its container; an app with the
  NAS's own network could open any port and get around the rules above.
- [x] **Outgoing internet access allowed** (metadata, monitors, peers, mirrors).

### P4.3: Apps through Cloudflare (optional, later)

A specialty case since P4.2: Tailscale is the default way to reach apps from outside. Built if an
app needs a public hostname. HTTPS for apps through Tailscale (Vaultwarden needs it) came first: P4.7.

- [ ] Hostname naming (`jellyfin.example.com`, or chosen per app).
- [ ] Which apps may be published at all, and whether each needs Cloudflare Access in front.
- [ ] How the tunnel's routes are written (the helper writes cloudflared's ingress rules from the
  apps that have a hostname).

### P4.4: Storage for apps

**Done** (#60): shares for apps. Decisions (CatDogBark, 2026-10-04):

- [x] **Shares chosen at install**, none by default, and changed later from the app's row (a
  reinstall with the new shares: the container is recreated, data and ports kept, and the image
  isn't downloaded again).
- [x] **Only apps that work with files in shares are asked** (CatDogBark, 2026-10-27, after
  Vaultwarden's Install asked for shares it never reads): a manifest says `shares: true`, or
  `writes_shares: true`; the others install without the dialog unless they have a ZFS pool to
  choose (then it's for the pool only) or were given shares before (so they can be taken back).
- [x] **Read only by default; read and write only for shares Greyhole doesn't pool**, and only for
  apps whose manifest says `writes_shares` (Transmission). A pooled share's files are links to
  their copies on the drives, so the app also gets that share's copy folder on each Greyhole drive,
  read only, at the same path. A share an app writes into gets a default ACL on its folders, so
  what the app makes is group-writable (`users`, like files made over SMB) whatever its umask; the
  app joins the `users` group in its container. On a ZFS pool made before pools had POSIX ACLs on,
  the share's dataset gets `acltype=posixacl` and `xattr=sa` first (setfacl fails without them).
  An image whose init drops to the app's user (`run_as: image`, `PUID`/`PGID`, linuxserver.io's)
  takes that user's groups from its own `/etc/group` and loses `--group-add`, so given a share to
  write into it gets the `users` group as `PGID`.
- [x] **Any share can be given**, and the dialog says that everyone with an account in the app can
  see it, whatever the share's own user list says (Samba enforces those, not the folders: every
  share folder is `users` 2775, files 0664).
- [x] **Shares appear at `/shares/<name>`** in every app. The web app names shares; the helper
  finds their folders in smb.conf (which only it writes) and checks they're in the share root or
  on a mounted data drive.
- [x] **ZFS datasets for apps wait for bitShare (P4.6)**: none of the five apps needed one, and
  there was no pool yet to test with. P4.6 (2026-10-10) splits an app's folders into state, shares
  and datasets.
- [x] **Backups of app data wait** (Proton Drive as its own app, or app data on a pool). Proxmox
  backups of the NAS VM cover it meanwhile.
- [x] Uninstall keeps the data unless asked (P4.1).

### P4.5: App updates

**Done** (#62). Decisions (CatDogBark, 2026-10-05):

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

Decided (CatDogBark, 2026-10-06): app updates mustn't wait for an Amahi-kai update.

- [x] **A repo of its own**, [CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps):
  one manifest per app in `apps/<id>.yml`, the same fields as before. Its CI runs this repo's
  helper on it (`amahi-helper --check-catalog apps`), so a manifest the NAS would refuse can't be
  merged. An app update is a PR there (`script/app-versions --catalog ../amahi-kai-apps/apps
  --update APP`).
- [x] **Fetched by the root helper with the update check** (`system.check_update`: every 6 hours
  by `amahi-kai-update-check.timer`, and on System Update's and the Apps page's **Check now**,
  so every check looks at Amahi-kai and its apps; none installs anything): main, over https only, into a
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
- [x] **Formats.** A manifest's `requires` (default 1) is the catalog format it needs. An
  Amahi-kai knows the formats up to its own (`CATALOG_FORMAT`, `AppCatalog::FORMAT`): 2 adds
  `web_tls`, 3 folders' `kind` and `required` (P4.6), 4 names as the app spells them and secrets
  inside values, 5 `access: tailscale` and a secret's `hash` (P4.7). An app or update that needs
  more is listed with "Needs a newer Amahi-kai: run System Update first", and the helper refuses
  to install it. A new manifest field raises the format, so older NASes don't misread it.

### P4.5c: Apps on the LAN

CatDogBark (2026-10-06): the NAS knows what it runs, so devices shouldn't have to be told its address.

- [x] **Announced over mDNS** by Avahi (`avahi-daemon`, installed by `bin/amahi-install`, and by
  `bin/amahi-update` on NASes from before): each installed app with a web page is an HTTP service
  named "<App> on <hostname>" on the port it was given, with the subtype `_<id>._sub._http._tcp`
  so one app can be asked for (bitTube Desktop asks for `_bittube._sub._http._tcp`). The helper's
  `apps.announce` writes `/etc/avahi/services/amahi-app-<id>.service` for the installed apps and
  removes the others of its own; it runs after every install and uninstall and each time Docker
  starts (`amahi-kai-app-firewall.service`). UFW lets mDNS (5353/udp) in, both when the security
  audit turns UFW on and at each announce when it's on already.

### P4.6: App storage, and bitShare

Decided with CatDogBark on 2026-10-10: **apps install on the system disk, and Amahi-kai decides where
their storage goes.** An app runs from the system disk (its image, and the small state it needs to
run) with no storage set up at all. What it keeps that grows goes in a share or a ZFS dataset,
and the app only declares which kind it needs: Amahi-kai orchestrates the rest. Apps don't
install on pools: certain things they keep do.

- [ ] **Each folder in a manifest has a kind** (`state` and `dataset` done in P4.6a, #158; `share` is P4.6b):
  - `state` (the default): what the app needs to run (settings, keys, a small database), in
    `/var/lib/amahi-kai/apps/<id>/` on the system disk, as today.
  - `share`: files people use (bitTube's downloads): a share chosen at install, **wherever
    Amahi-kai keeps that share** (CatDogBark): the app doesn't care. A Greyhole share's folder is on the
    system disk, so the app's files land there first and Greyhole moves them onto the pool drives,
    as it does with anyone's over SMB.
    - **A Greyhole share reaches the app through Samba**, so Greyhole sees every write: the helper
      mounts the share by name on the NAS's own Samba (`//127.0.0.1/<share>`), with an account of
      the app's own, and gives that folder to the container (containers still can't reach Samba
      themselves). The app sees the share's real files, not Greyhole's links, so it needs no copy
      folders and nothing follows the pool for it. The mount comes up after Samba and before the
      app.
    - **A share that isn't pooled** (the system disk, a data drive, a ZFS pool) is mounted
      directly, as P4.4 does: nothing needs to see its writes.
    - This replaces P4.4's read-only rule for the shares an app keeps its files in.
  - `dataset`: the app's own private data (bitShare's chunk store and its database): a ZFS dataset
    of its own, `<pool>/apps/<id>`, on the pool chosen at install, in the pool's snapshots. No quota
    (CatDogBark, 2026-10-11: people manage their own files, and the disk warnings cover it; quotas are on
    the roadmap's long-term list). Never Greyhole (it only sees Samba's writes, and nobody opens
    chunks over SMB).
- [x] **Each storage folder is required or optional** (#158). Optional: the app installs and runs
  without it, and that feature stays off until one is chosen (bitTube streams with no downloads
  folder, its Download hidden). Required: the app can't be installed until there's somewhere to
  put it (bitShare needs a ZFS pool).
- [x] **bitShare's database goes with its chunks** (CatDogBark; catalog amahi-kai-apps#14): both on its dataset, so one snapshot
  always has the two together (a database on the system disk could name chunks a pool roll-back
  took away). Only the container and what Amahi-kai keeps about the app stay on the system disk.
- [x] **Chosen at install, changed by reinstalling** for now (CatDogBark; #158); moving an app's storage
  between pools comes later. Uninstall keeps the storage unless asked (P4.1).
- [x] **A pool with apps' storage on it** (#158) isn't taken offline or deleted (like shares), its page
  lists the apps on it, and an update snapshots the app's dataset first (instead of copying its
  folders) and rolls back to it if the update fails. **Rolling the pool back stops the apps on
  it** while it runs (CatDogBark: "rollbacks are emergencies and they take priority over any app
  functionality"), then starts them again.
- [ ] **Two PRs** (CatDogBark, 2026-10-11): **P4.6a**, datasets (what bitShare needs; its tests on the
  NAS wait for it), done in #158, then **P4.6b**, Greyhole shares through Samba (what bitTube's
  downloads need).
- [ ] **bitTube** runs with no downloads folder (a change in bitTube); its downloads become an
  optional `share`. **bitShare**'s `data` and `chunks` became a required `dataset` (catalog
  amahi-kai-apps#14). The bitShare
  installed for testing (its folders on the system disk) is uninstalled and installed again onto
  the test pool once this is in.
- [x] **How bitShare signs people in: Amahi-kai's users** (CatDogBark, 2026-10-11: one login for
  everything on Amahi-kai, the desktop app included; separate logins aren't a good design). It
  needs a way for an app to ask Amahi-kai whether a sign-in is right (the capability API's
  direction, [`roadmap.md`](roadmap.md)), planned on its own; P4.6 doesn't wait for it, and bitShare
  keeps its own admin until then.
- [x] How bitShare uses snapshots and datasets: through the helper, as any app does (the pool's
  snapshots, and one before each update; #158).
- [x] Where its image comes from: built from `~/Projects/bitShare`, published to GHCR by its tag
  workflow, pinned in the catalog (0.3.0 on 2026-10-10); the image carries the Linux client for
  computers to download.

### P4.7: Apps reached only through Tailscale (catalog format 5)

CatDogBark (2026-10-27): Vaultwarden can't work over plain HTTP. Browsers keep its web vault from
running there (it encrypts in the page, which browsers allow only on HTTPS pages), and the
Bitwarden apps refuse a server that isn't HTTPS: their command-line client since 2025.11 ("Insecure URL
not allowed"), and the Android app over LAN HTTP since about 2025.8. A password server also has
no business on the internet, and apps aren't on the Cloudflare Tunnel by design. So it's reached
only through Tailscale, over HTTPS with Tailscale's certificate for the NAS's name; HTTPS on the
LAN for everything stays a later, optional front door (roadmap, "HTTPS on the LAN").

- [x] **`access: tailscale`** (format 5): the app's ports are published on `127.0.0.1` only, and its
  `web_port` is served on the tailnet by `tailscale serve --bg --https=<port> http://127.0.0.1:<port>`,
  at the same port number (the address `https://<the NAS's name on the tailnet>:<port>`).
  tailscaled keeps the serve entry across restarts; it's set again with each new container and
  removed at uninstall. `{{tailscale_url}}` in the environment is that address (Vaultwarden's
  `DOMAIN`, for its links and passkeys). The page must be plain HTTP on TCP (not `web_tls`).
  An older Amahi-kai lists the app as needing a newer one instead of putting it on the LAN.
- [x] **Refused, before anything changes, while Tailscale can't serve it**: install, update and
  undo say what's missing. They want Tailscale installed and connected, MagicDNS on, and HTTPS
  Certificates on, with the NAS's name among `tailscale status`'s `CertDomains`. The Apps page
  says so on the app's row (no Install until then), and Remote Access shows HTTPS certificates
  on or off.
- [x] **Not announced on the LAN** (nothing there can open it), and **Open** goes to the tailnet
  address, through the Cloudflare Tunnel too.
- [x] **A secret's `hash: argon2`** (format 5): the container gets an Argon2id hash of it (PHC form,
  OWASP's settings: `-id -k 19456 -t 2 -p 1`), from Ubuntu's `argon2`, installed by the helper the
  first time it's needed. The secret goes on argon2's stdin, with a new salt for each container.
  The Apps page shows the token itself, to sign in with. Vaultwarden's `ADMIN_TOKEN` takes it, so
  Vaultwarden stops warning about a plain-text token.
- [x] **Vaultwarden's manifest** (the catalog's PR, after this release): `requires: 5`, `access:
  tailscale`, `DOMAIN: "{{tailscale_url}}"`, `hash: argon2` on `ADMIN_TOKEN`, and a first sign-in
  note. Sign-ups stay on at install (CatDogBark, 2026-10-27): the household makes its accounts,
  then turns them off on `/admin`. It keeps its own port, `:8880`, so 443 on the tailnet is left
  for Amahi-kai's own HTTPS later.
- [x] `config/apps` brought up to date from the catalog once its PR was merged (#19, after 1.3.0;
  the copy comes after the catalog). Specs that use Vaultwarden as their sample app stub Tailscale's
  readiness and the hash.
- Renaming the NAS in Tailscale leaves the app's `DOMAIN` on the old name until its container is
  made again (Change → Save and restart): the wiki says so. Following a rename on its own can
  come later.

### Also in Phase 4

- The wiki's Docker Apps page rewritten for the new model, with the plain statement that Docker
  itself is root-level software: install apps you trust.
- The security audit's Docker ports check updated for the new port binding.
- GPU access for transcoding (`/dev/dri`) waits: the NAS VM has no GPU.
- **The Apps page laid out again (2026-10-27, CatDogBark's pick of three mockups).** The table put
  each app's sign-in and passwords on a row of their own, which read as another app, and only the
  buttons told whether an app ran. Now: your apps first, as cards saying in a word where each is
  (Running, Stopped, Installing…, Needs attention) with Open or Start, and Manage; then **Add
  apps**, the catalog's others, by category. Everything else moved to the app's own page
  (`/apps/<id>`): how to sign in and the passwords Amahi-kai made (hidden until Show), its address,
  ports and version (Update, Undo update), its shares and storage, Stop and Uninstall. The
  Installed tab is gone (`/apps/installed_apps` goes to the Apps page). With many more apps, the
  catalog will want search and pages.
