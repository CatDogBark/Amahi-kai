---
layout: default
title: "Making Apps"
---

# Making Apps

Any app that runs in one Docker container can become an Amahi-kai app. You describe it in one
small file, a **manifest**, and add that file to the app catalog,
[CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps). Every Amahi-kai server
fetches the catalog every 6 hours, so once your manifest is merged, your app is on every
server's **Apps** page within hours, without an Amahi-kai update.

This page covers what Amahi-kai does with an app, what its image needs, how to try it the way a
server will run it, and how to add it. The catalog's
[README](https://github.com/CatDogBark/amahi-kai-apps#readme) lists every manifest field.

---

## What Amahi-kai does with your app

When someone clicks **Install**, Amahi-kai's root helper:

1. Checks your manifest, field by field. It installs nothing from anywhere else.
2. Makes the app a user of its own, `app-<id>`, and its folders under
   `/var/lib/amahi-kai/apps/<id>/`, owned by that user.
3. Generates the secrets your manifest asks for (an admin token, a password), shown to the
   server's admins on the Apps page, and kept for the next install.
4. Pulls your image, by its digest.
5. Creates the container:
   - as the app's user (`--user <uid>:<gid>`) when the manifest says `run_as: app`;
   - with a memory limit (`1g` unless the manifest sets another), restarted unless stopped;
   - with your environment settings and the generated secrets;
   - with each of your folders mounted at the path you gave;
   - with the shares the admin chose at `/shares/<name>`, read only unless your app writes
     into shares and the admin allowed it;
   - with your ports published on the server, the usual ones when they're free, the next free
     ones if not. Only the server's LAN and Tailscale can reach them.
6. Starts it, and announces it on the LAN as "<Name> on <server>", so devices can find it.

**Updates:** when your manifest's `image` changes in the catalog, each server's Apps page offers
**Update**. Amahi-kai copies the app's folders first (except those marked `backup: false`), starts
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
  linuxserver.io images, with `PUID`/`PGID`) use `run_as: image`.
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
(`uptimekuma`). Here's bitTube's:

```yaml
name: bitTube
description: Your YouTube channels and streaming services in one place, with YouTube ad-free.
category: media
logo: https://cdn.jsdelivr.net/gh/CatDogBark/amahi-kai-apps@main/logos/bittube.svg
releases: https://github.com/CatDogBark/bitTube/releases/tag/v{version}
image: ghcr.io/catdogbark/bittube:0.1.7@sha256:5243...
run_as: app
web_port: 8484
memory: 1g
writes_shares: true
ports:
  - { host: 8484, container: 8080 }
folders:
  - { name: data, path: /data }
environment:
  TZ: "{{timezone}}"
```

- **`image`** is pinned twice, by tag and by digest (`name:tag@sha256:...`), so every server gets
  exactly the build you tested.
- **`ports`**: `host` is the port the app gets on the server when it's free (1024 or above, not
  one of the server's own, and not another catalog app's); `container` is the one your image
  listens on.
- **`environment`** can use `{{uid}}`, `{{gid}}` and `{{timezone}}`, filled in at install.
- **`secrets`** (`{ env: ADMIN_TOKEN, label: Admin page token }`) are generated at install.
- **`folders`** with `backup: false` (caches, downloads) aren't copied before an update.
- **`logo`** is an `https` link. A logo of your own goes in the catalog's `logos/` folder.
- **`web_tls: true`** says the app's page is HTTPS with its own certificate (as bitShare's is):
  **Open** goes to `https://`, and the app is announced on the LAN as HTTPS. It needs
  `requires: 2`, since older Amahi-kai versions don't know it.

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
3. Once it's merged, every server shows the app within 6 hours (or at once, with **Check now**
   on its Apps page).

### Releasing a new version

Change `image` to the new tag and digest, and open a pull request. From an Amahi-kai checkout,
`script/app-versions` finds newer versions on the registry and writes them for you:

```bash
script/app-versions --catalog ../amahi-kai-apps/apps --update yourapp
```

Read the release notes first: a new major version can need changes to the manifest. Within 6
hours of the merge, every server running your app shows **Update** on its row, and the update
notice on its dashboard.

### New manifest fields

A server only understands the manifest fields its Amahi-kai knows. A manifest that uses newer
ones says so with `requires: 2` (the catalog format it needs). Older servers then list the app
with "Needs a newer Amahi-kai" instead of installing what they can't read.

---

## Not yet

- **A catalog of your own.** Servers install from the one catalog only. To try an app on your
  server before it's in the catalog, run it with `docker run` as above.
- **HTTPS.** Apps are reached over plain HTTP on the LAN, like Amahi-kai's own pages; HTTPS for
  both is planned.
