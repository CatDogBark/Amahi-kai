# App catalog

One manifest per app (`<id>.yml`, the id being lowercase letters and digits). The root helper
(`libexec/amahi-helper`, `app_manifest`) reads it to install the app and checks every field; the
web app only names an app (docs/plans/apps.md, P4.1).

| Field | Meaning |
| --- | --- |
| `name`, `description`, `category`, `logo` | What the Apps page shows |
| `image` | `name:tag@sha256:digest`: the exact image, pinned |
| `run_as` | `app`: the container runs as the app's own user (`--user`). `image`: it starts as root and switches to the app's user itself (linuxserver images, given `PUID`/`PGID`) |
| `web_port` | The host port of the app's web page (one of `ports`'s `host`) |
| `memory` | Memory limit, like `512m` or `2g` (default `1g`) |
| `ports` | `host` (1024–65535, not the NAS's own, and no other app's), `container`, `protocol` (`tcp` or `udp`), and `label` for the Apps page (the web port is labelled "web"). `host` is the port the app gets when it's free; if not, the helper gives it the next free one at install, and the app keeps it (`/var/lib/amahi-kai/app-ports.json`) |
| `folders` | `name` (a folder under `/var/lib/amahi-kai/apps/<id>/`, owned by the app's user) and `path` in the container |
| `environment` | Plain settings; `{{uid}}`, `{{gid}}` and `{{timezone}}` are filled in at install |
| `secrets` | `env` and `label`: generated at install, passed as that environment variable, shown to admins |

To update an app, change its tag and digest together (the digest from the registry, for the tag's
multi-architecture image) and test it on the NAS.
