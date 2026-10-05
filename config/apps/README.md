# App catalog

One manifest per app (`<id>.yml`, the id being lowercase letters and digits). The root helper
(`libexec/amahi-helper`, `app_manifest`) reads it to install the app and checks every field; the
web app only names an app (docs/plans/apps.md, P4.1).

| Field | Meaning |
| --- | --- |
| `name`, `description`, `category`, `logo` | What the Apps page shows |
| `releases` | The release notes for a version, `{version}` being the tag's leading number (`2.5.5` for `2.5.5-rootless`): the Apps page's What's new link |
| `image` | `name:tag@sha256:digest`: the exact image, pinned |
| `run_as` | `app`: the container runs as the app's own user (`--user`). `image`: it starts as root and switches to the app's user itself (linuxserver images, given `PUID`/`PGID`) |
| `web_port` | The host port of the app's web page (one of `ports`'s `host`) |
| `memory` | Memory limit, like `512m` or `2g` (default `1g`) |
| `ports` | `host` (1024–65535, not the NAS's own, and no other app's), `container`, `protocol` (`tcp` or `udp`), and `label` for the Apps page (the web port is labelled "web"). `host` is the port the app gets when it's free; if not, the helper gives it the next free one at install, and the app keeps it (`/var/lib/amahi-kai/app-ports.json`) |
| `folders` | `name` (a folder under `/var/lib/amahi-kai/apps/<id>/`, owned by the app's user) and `path` in the container; `backup: false` leaves it out of the copy taken before an update (caches, downloads) |
| `environment` | Plain settings; `{{uid}}`, `{{gid}}` and `{{timezone}}` are filled in at install |
| `secrets` | `env` and `label`: generated at install, passed as that environment variable, shown to admins |
| `writes_shares` | `true` if the app may be given shares to write into (default `false`: shares are read only). Shares Greyhole pools are always read only |

Shares chosen at install appear in the app at `/shares/<name>`. Their folders come from smb.conf;
a pooled share also brings its copy folders on each Greyhole drive (read only, at the same path),
which its files link to. A share an app writes into gets a default ACL on its folders, so files
the app makes stay editable over SMB.

## Updating an app's version

`script/app-versions` asks each app's registry for newer releases of the same kind as the pinned
tag (`2.5.5-rootless` finds `2.5.6-rootless`, not `nightly-rootless`), and for newer builds of
the pinned tag itself (Jellyfin republishes `12.1`). It changes nothing unless asked:

```bash
script/app-versions                 # what's newer, with release notes links
script/app-versions --update gitea  # write the newest tag and digest into gitea.yml
```

Read the release notes (a new major version can need changes to the manifest), then open a PR
as usual. Once System Update brings it to a NAS, the app's row offers **Update**: the helper
copies the app's data, starts the new version, and goes back to the old one if it isn't healthy
within 5 minutes. The copy is kept for 30 days for **Undo update**.
