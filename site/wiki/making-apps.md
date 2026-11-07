---
layout: default
title: "Making Apps"
---

# Making Apps

Any app that runs in one Docker container can become an Amahi-kai app. You describe it in one
small file, a **manifest**, and add that file to the app catalog,
[CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps). Every Amahi-kai server
fetches the catalog's newest signed version every 6 hours, so once your manifest is merged and
the maintainer signs the next version, your app is on every server's **Apps** page within hours,
without an Amahi-kai update.

This page covers what Amahi-kai does with an app, what its image needs, how to try it the way a
server will run it, and how to add it. The catalog's
[README](https://github.com/CatDogBark/amahi-kai-apps#readme) lists every manifest field.

---

## What Amahi-kai does with your app

When someone clicks **Install**, Amahi-kai's root helper:

1. Checks your manifest, field by field. It installs nothing from anywhere else.
2. Makes the app a user of its own, `app-<id>`, and its folders under
   `/var/lib/amahi-kai/apps/<id>/`, owned by that user. Folders marked `kind: dataset` go on a
   ZFS pool instead (below).
3. Generates the secrets your manifest asks for (an admin token, a password), shown to the
   server's admins on the app's page (Apps → **Manage**), and kept for the next install.
4. Pulls your image, by its digest.
5. Creates the container:
   - as the app's user (`--user <uid>:<gid>`) when the manifest says `run_as: app`;
   - with `no-new-privileges`, so nothing in it can gain privileges (setuid programs in the
     image included), and with every kernel capability dropped but the ones your manifest's
     `capabilities` gives back (below);
   - with a memory limit (`1g` unless the manifest sets another), and all of the server's
     processors but one, so the server itself always has one; restarted unless stopped;
   - with your environment settings and the generated secrets;
   - with each of your folders mounted at the path you gave;
   - with the shares the admin chose at `/shares/<name>`, read only unless your app writes
     into shares and the admin allowed it;
   - with your ports published on the server, the usual ones when they're free, the next free
     ones if not. Only the server's LAN and Tailscale can reach them;
   - kept off the server's own services: your app can ask the server's DNS and ping it, but not
     reach its SSH, admin page or file sharing (it gets its files through the shares it's given);
   - on a network of its own, so it can't reach any other app, and reaching out only as far as
     its `network` says (below): the internet, unless it asks for the LAN too;
   - asking the server's DNS while it's on (Network → DNS), so your app reaches the LAN's
     devices by their names (Network → Devices), not addresses that change.
6. Starts it, and announces it on the LAN as "<Name> on <server>", so devices can find it.

**Updates:** when your manifest's `image` changes in the catalog, each server's Apps page offers
**Update**. Amahi-kai copies the app's folders first (except those marked `backup: false`, and
snapshots a dataset instead of copying it), starts
the new version, and waits up to 5 minutes for it to be healthy. If it isn't, Amahi-kai puts the
old version and its data back. "Healthy" means your image's Docker `HEALTHCHECK` passes, or,
without one, that its web page answers and the container is still running 10 seconds later.

**Uninstall** removes the container and the image, and keeps the app's folders and secrets, so
installing it again picks up where it was.

---

## What your image needs

- **Published where anyone can pull it**: Docker Hub or GitHub's registry (`ghcr.io`), public,
  for `linux/amd64`.
- **All its data in folders you name.** Everything else in the container can be thrown away at an
  update.
- **Able to run as an ordinary user** (best: `run_as: app`). It mustn't need to write outside
  its folders or `/tmp`. Images that must start as root and switch to a user they're given (the
  linuxserver.io images, with `PUID`/`PGID`) use `run_as: image`. An app that writes into shares
  (`writes_shares: true`) must run its processes as the app's user: `run_as: app`, or `run_as:
  image` with `PUID: "{{uid}}"` and `PGID: "{{gid}}"` in its environment, both exactly so. The
  catalog's check refuses anything else. (Given a share to write into, a `run_as: image` app's
  `{{gid}}` is the `users` group, so it can write there.)
- **Ping without raw sockets.** An image's `ping` is often marked to need raw sockets, which an
  app doesn't get, and then it doesn't run at all. Name it in the manifest (`ping: /usr/bin/ping`)
  and Amahi-kai mounts a copy of that same file without the mark, which pings the way Docker lets
  any container.
- **Shares only if it works with files in them.** `shares: true` has **Install** ask which shares to
  give it (read only, unless `writes_shares: true`, which says so too); an app without either
  installs without being asked, and gets none.
- **No default passwords.** If it needs one from the start, take it from an environment variable
  your manifest marks as a secret: Amahi-kai generates it.
- **Settings through the environment**, not a file someone has to edit.
- **A web page on a fixed port**, if it has one: that's where **Open** goes.
- **A `HEALTHCHECK`**, ideally, so updates know when it's ready.

Not supported (yet): more than one container, host networking, devices, privileged containers,
and anything other than `amd64`.

---

## Writing the manifest

The file is `apps/<id>.yml`, where `<id>` is the app's name in lowercase letters and digits
(`uptimekuma`). Here's Gitea's:

```yaml
name: Gitea
description: Your own Git server, like a small GitHub, for code and its history.
sign_in: "Its first page sets it up: make the admin account there (or the first account you register is the admin), and to keep its repositories in a share folder you gave it, set Repository Root Path to that folder under /shares."
category: development
logo: https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/gitea.png
releases: https://github.com/go-gitea/gitea/releases/tag/v{version}
image: gitea/gitea:1.27.3-rootless@sha256:1c17...
run_as: app
# It can keep its repositories in a share given read and write (a share Greyhole doesn't pool).
writes_shares: true
web_port: 3300
memory: 1g
ports:
  # 3000 is Amahi-kai's own web page.
  - { host: 3300, container: 3000 }
  - { host: 2222, container: 2222, label: Git over SSH }
folders:
  - { name: data, path: /var/lib/gitea }
  - { name: config, path: /etc/gitea }
environment:
  TZ: "{{timezone}}"
```

- **`sign_in`** says how to sign in the first time, in one sentence: who to sign in as and with
  what ("the password Amahi-kai made for it", for one of your `secrets`), or what your app's first
  page asks for. The Apps page shows it under the installed app, and the install window as the
  install finishes. The catalog wants one for every app.
- **`image`** is pinned twice, by tag and by digest (`name:tag@sha256:...`), so every server gets
  exactly the build you tested.
- **`ports`**: `host` is the port the app gets on the server when it's free (1024 or above, not
  one of the server's own, and not another catalog app's); `container` is the one your image
  listens on.
- **`environment`** can use `{{uid}}`, `{{gid}}` and `{{timezone}}`, filled in at install. It
  can't set `DOCKER_MODS`, which has an image download more code as it starts. Its names are like
  `TZ`; with **`requires: 4`** they can be spelled the way your app spells its settings (letters
  of either case, digits, `_` and `-`, starting with a letter: PiGallery2's `Media-folder`).
- **`secrets`** (`{ env: ADMIN_TOKEN, label: Admin page token }`) are generated at install. With
  `requires: 4` a setting can hold one inside its value as `{{secret:ADMIN_TOKEN}}`, such as a
  password inside a JSON list of users; secrets are letters and digits, so they fit inside quotes.
  With **`requires: 5`**, `hash: argon2` gives the container an Argon2id hash of the secret, in the
  PHC form (`$argon2id$v=19$...`), while the Apps page shows the secret itself to sign in with:
  Vaultwarden's `ADMIN_TOKEN` takes one. A `{{secret:...}}` inside a value is the secret itself.
- **`folders`**: each `path` is made of plain names (letters, digits, `.`, `_`, `-`), isn't
  `/shares` or under it (where the app's shares go), and no two folders share one.
- **`folders`** with `backup: false` (caches, downloads) aren't copied before an update.
- **`folders`** with **`kind: dataset`** hold the data that grows (a sync engine's file store, say):
  they go on a ZFS pool, in a dataset of the app's own (`<pool>/apps/<id>`), on the pool the admin
  chooses at install, and the pool's snapshots cover them. The others (`kind: state`, the
  default) stay on the server's system disk: what the app needs to run. A dataset folder is
  **`required: true`** unless you say `required: false`: the app can't be installed until there's
  a pool. An optional one is left out until a pool is chosen, so your app must run without it.
  Before an update, Amahi-kai snapshots the dataset instead of copying it, and rolls back to the
  snapshot if the update fails. It needs `requires: 3`.
- **`logo`** is an `https` link. A logo of your own goes in the catalog's `logos/` folder. (An app
  added on the Apps page as one of your own takes a picture instead, kept on your server: its
  file's `logo` isn't used.)
- **`web_tls: true`** says the app's page is HTTPS with its own certificate:
  **Open** goes to `https://`, and the app is announced on the LAN as HTTPS. It needs
  `requires: 2`, since older Amahi-kai versions don't know it.
- **`access: tailscale`** makes the app reachable only from devices on the server's Tailscale
  network, over HTTPS (Vaultwarden is: browsers won't run its web vault over plain HTTP, and the
  Bitwarden apps refuse it). Its ports are published on the server itself only, and its
  `web_port` (plain HTTP, on TCP; not `web_tls`) is served on the tailnet with Tailscale's
  certificate, at `https://<the server's name on the tailnet>:<its port>`. `{{tailscale_url}}`
  in its environment is that address (Vaultwarden's `DOMAIN`). It's installed only once the
  server's Tailscale is connected with MagicDNS and HTTPS Certificates on, and it isn't announced
  on the LAN. It needs `requires: 5`: an older Amahi-kai would put the app on the LAN instead.

- **`network`** says what your app reaches out to: `internet` (the default: the internet, but
  not the devices on the server's LAN, its Tailscale network or other private addresses), `lan`
  (the internet and the LAN's devices too: cameras, a monitor checking the network's machines),
  or `none` (nothing past the server; it still asks the server's DNS). Ask for `lan` only when
  your app needs it: the Apps page says so on its card, before anyone installs it. No setting
  lets an app reach another app, or the server's own services. An older Amahi-kai ignores the
  field and lets the app reach everything, as it always did, so it needs no `requires`.

- **`capabilities`** gives back the kernel capabilities your app needs; every container starts
  with none. An app that runs as its own user (`run_as: app`) needs none, so leave it out. An image
  that starts as root and switches to the app's user itself (linuxserver.io's, `run_as: image`)
  needs the few its setup takes: Transmission's are `[CHOWN, DAC_OVERRIDE, SETUID, SETGID]`. They
  come from Docker's own default set, but `NET_RAW` and `MKNOD`, so no manifest gives an app more
  than Docker would. Find the fewest that work by trying your image with `--cap-drop ALL` and
  adding them back one at a time. An older Amahi-kai ignores the field and gives Docker's set.

Every field is in the catalog's [README](https://github.com/CatDogBark/amahi-kai-apps#readme).

---

## Trying it the way a server runs it

Run your image as a user it doesn't know, with its folders, its port and the memory limit, the
way Amahi-kai will:

```bash
docker run --rm --user 12345:12345 --memory 1g -p 8484:8080 -v "$PWD/data:/data" -e TZ=America/New_York ghcr.io/you/yourapp:1.0.0
```

(Make `data` writable by that user first: `sudo chown 12345:12345 data`.) If it starts, saves
what it should into `data`, and survives `docker rm` and a fresh `docker run`, it'll work.

Then check the manifest the way a server will, with Amahi-kai's own checks, from a checkout of
Amahi-kai beside one of the catalog:

```bash
ruby --disable-gems amahi-kai/libexec/amahi-helper --check-catalog amahi-kai-apps/apps
```

It prints `<id>: ok` for every app, or what's wrong.

---

## Adding it to the catalog

1. Fork [amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps) and add `apps/<id>.yml`
   (and `logos/<id>.svg`, if your logo is your own).
2. Open a pull request. Its checks run Amahi-kai's own manifest checks, so a manifest a server
   would refuse can't be merged.
3. Once it's merged, the maintainer signs the catalog's next version (a `catalog-N` tag, with a
   release key: servers take nothing else), and every server shows the app within 6 hours (or at once, with **Check now**
   on its Apps page).

### Releasing a new version

Change `image` to the new tag and digest, and open a pull request. From an Amahi-kai checkout,
`script/app-versions` finds newer versions on the registry and writes them for you:

```bash
script/app-versions --catalog ../amahi-kai-apps/apps --update yourapp
```

Read the release notes first: a new major version can need changes to the manifest. Within 6
hours of the merge, every server running your app marks it **Update ready** on the Apps page, with
**Update** on its page, and the update notice on its dashboard.

### New manifest fields

A server only understands the manifest fields its Amahi-kai knows. A manifest that uses newer
ones says so with `requires` (the catalog format it needs: 2 for `web_tls`, 3 for `kind:
dataset`, 4 for names as the app spells them and secrets inside values, 5 for `access` and a
secret's `hash`). Older servers then list the app with "Needs a newer Amahi-kai" instead of
installing what they can't read.

---

## On your own server only

An app doesn't have to be in the catalog to run on your server: **Add your own app** on the Apps
page takes the same manifest (**I have an app file**), or makes one from a form, and checks it the
way the catalog's are. It's for your server only, nobody else's, and nobody reviews it: see
[Docker Apps](docker-apps#apps-of-your-own). It's also the way to try an app on a server, exactly
as Amahi-kai will run it, before it goes to the catalog. A few things differ:

- Its `image` can name a tag only (`ghcr.io/you/app:1.0`): Amahi-kai pins the digest when it reads
  the file. The image has to be public, for now.
- Its id is its name's letters and digits (`My App` is `myapp`), and can't be one the catalog has.
- One that starts as root (`run_as: image`) keeps its folders on the system disk: `kind: dataset`
  needs `run_as: app`. The catalog holds to the same by review.

## Not yet

- **Other people's catalogs.** Servers fetch the one catalog only; an app of your own is added on
  its server, by hand.
- **HTTPS on the LAN.** Apps are reached over plain HTTP on the LAN, like Amahi-kai's own pages;
  HTTPS for both is planned. An app that can't work without HTTPS can be reached only through
  Tailscale, over HTTPS, today (`access: tailscale`).
