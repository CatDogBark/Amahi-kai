# Privilege model

How Amahi-kai gets root access on a NAS, and what keeps the web app from turning a bug into
root. Last updated 2026-10-30 (release keys). Design and history: [`docs/plans/privileged-helper.md`](../plans/privileged-helper.md).

## Summary

The web app runs as the unprivileged `amahi` user. It reaches root one way only:
**the root helper**, `/usr/local/sbin/amahi-helper` (`libexec/amahi-helper` and its parts in
`libexec/amahi-helper.d/`, put together as one file by `bin/amahi-join-helper`, so it loads
nothing but Ruby's standard library). It runs a
fixed list of operations, checks every request, and logs every call. One of them,
`system.update`, starts **System Update**: `bin/amahi-update` as its own systemd job
(`amahi-kai-update.service`), which pulls the code and redeploys, and rolls back if that
fails. The page follows its log, `/var/log/amahi-kai/update.log`.

Docker apps go through the helper too (since Phase 4's P4.1): the app has no `sudo docker` and
isn't in the `docker` group.

Root never runs code the `amahi` user can change: the code is root's, and the installer and the
updater run everything that loads the app or its gems as `amahi`.

## Who owns what

| Path | Owner, mode | Why |
| --- | --- | --- |
| `/opt/amahi-kai` (the code, `.git`, `.bundle/config`) | root:root, not group- or world-writable | Root runs `bin/amahi-update`, `bin/amahi-install-helper`, and installs the helper and sudoers rules from here |
| `/opt/amahi-kai/{tmp,log,public/assets,vendor/bundle}` | amahi | What the app writes: caches and pids, logs, the asset build, gems |
| `/usr/local/sbin/amahi-helper` | root:root 0755 | Installed from the root-owned tree by `bin/amahi-install-helper` |
| `/etc/sudoers.d/amahi-kai` | root:root 0440 | From `config/sudoers/amahi-kai`, installed only if `visudo -cf` accepts it |
| `/etc/amahi-kai/amahi.env` | root:amahi 0640 | Database password and `SECRET_KEY_BASE`; the app reads it |
| `/etc/amahi-kai/tunnel.token` | root:root 0600 | systemd reads it and hands it to `cloudflared`, which runs as a user made for it (`DynamicUser`), since whoever holds a token decides from Cloudflare's side where the tunnel connects |
| `/etc/amahi-kai/allowed_signers` | root:root 0644 | The release keys' public halves, from `config/allowed_signers`: the update check checks a release's tag against them |
| `/etc/amahi-kai/allow-development` | root:root 0644, empty, on some servers | Root's permission to switch to the `development` channel, which isn't signature-checked; the root helper refuses the switch without it |
| `/etc/greyhole.conf` | root:amahi 0640 | Holds the database password |
| `/var/log/amahi-kai/helper.log` | root:amahi 0640 | The helper's audit log; the app can read it, not write it |
| `/var/log/amahi-kai/update.log` | root, in a root:amahi 0750 folder | The last System Update's output; the update page reads it |
| `/var/lib/amahi-kai/backups/` | root:root 0700 | Database dumps taken before each update's migrations (the last 3) |
| `/var/lib/amahi-kai/apps/<app>/` | `app-<app>`, 0750 | A Docker app's folders, owned by its own system user (uid below 1000) |
| `/var/lib/amahi-kai/app-secrets/<app>.json` | root:amahi 0640 | Passwords and keys generated at an app's install; shown to admins |
| `/var/lib/amahi-kai/app-ports.json` | root:amahi 0640 | The host ports each app was given; the Apps page shows them |
| `/var/lib/amahi-kai/app-backups/<app>/` | root:root 0700, in a root:amahi 0750 folder | The copy of an app's data from before its last update, kept 30 days; `<app>.json` beside it (root:amahi 0640) describes it for Undo update |
| `/var/lib/amahi-kai/app-definitions/<app>.json` | root:amahi 0640 | What each installed app's container was made from (its manifest and image), so a reinstall, an Undo and a roll-back rebuild it as it was |
| `/var/lib/amahi-kai/catalog-src`, `/var/lib/amahi-kai/catalog` | root:root, readable | The app catalog as fetched (a bare git repo), and the manifests from it that passed the helper's checks |
| `/var/lib/amahi-kai-dns/` | root:root 0755 | The network's state: the router's rules (`router.json`), the NAS's last address change, the blocklists, the netplan files as last applied |

`bin/amahi-set-ownership` sets this up. The installer runs it, and System Update runs it at the
start of every update, so the first update after PR N takes the checkout back from the `amahi`
user. Root's `git pull` runs with hooks and `core.fsmonitor` turned off, so nothing from the
checkout's own git config runs as root. Logrotate rotates `log/production.log` as `amahi`.

## The root helper

One program, Ruby standard library only, started as `--disable-gems` so no gem or app code loads
in the root process. The operation name is its one argument; the arguments come as JSON on stdin,
so passwords never appear on a command line. Each operation:

- accepts only the arguments it lists, and validates each one itself (it doesn't trust the app);
- runs commands by absolute path as argument lists, with a minimal environment and no shell;
- writes files atomically, after checking them (`testparm` for Samba, `dnsmasq --test`, `sshd -t`);
- logs one JSON line per call, with secrets filtered out and file contents summarized as a size
  and a hash.

The areas it covers: Linux and Samba accounts, Samba's config, share folders, system services,
reboot and power off, the hostname, swap, data drives and fstab, ZFS pools (created only on
whole data disks with nothing in use on them, imported only when Amahi-kai made them; pools
mount under `/srv/pools`, where no share folder may be made), Greyhole, package installs (from
pinned apt repositories and a fixed package list), the Cloudflare Tunnel, Tailscale, the
security audit's fixes, drive temperatures, the storage health check (pools and SMART, every 15
minutes from `amahi-kai-storage-check.timer`, written to `/var/lib/amahi-kai/storage-health.json`),
Docker apps (below), and System Update (starting it, or checking for an update: `git fetch` as
root, written to `/var/lib/amahi-kai/update-status.json`, every 6 hours from
`amahi-kai-update-check.timer`, which fetches the app catalog too).

The network is the helper's as well: Unbound's config (only lines Amahi-kai writes, checked
with `unbound-checkconf`, never answering more than the NAS's networks) and its blocklists,
dnsmasq (DHCP only, never DNS), radvd and the NAS's own IPv6 address, the NAS's IPv4 address on
a port (netplan, applied after the reply and put back unless the NAS is reached at the new
address), and router mode: the internet port's netplan file, forwarding and the kernel's
settings, UFW's rules and the NAT block in `before.rules`, with the internet side shut first.
These operations run one at a time (a lock), so two network changes can't interleave.

`amahi-helper --list` prints the operations, and `--dry-run OPERATION` shows what a request
would do without doing it.

In Rails, `Privileged.call('users.create', login: 'ann', name: 'Ann')` runs an operation through
`sudo -n`. In tests it records the call instead.

## Sudoers

`config/sudoers/amahi-kai`, 1 rule:

| Rule | For |
| --- | --- |
| `/usr/local/sbin/amahi-helper` | Everything above, System Update and Docker apps included |

`bin/amahi-install-helper` also takes `amahi` out of the `docker` group, which versions before
P4.1 put it in.

## Docker apps

The web app only names an app (`apps.install`, `app: "jellyfin"`). The helper reads the app's
manifest from the app catalog, [CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps):
the update check fetches its newest signed version as root over HTTPS into a bare repository
(`/var/lib/amahi-kai/catalog-src`), and keeps only the manifests that pass every check below
(`/var/lib/amahi-kai/catalog`); the copy in the code (`config/apps`) is the fallback. A version is
a `catalog-N` tag signed with a release key, checked as a release's tag is (Release keys, below):
an SSH signature by a key in `/etc/amahi-kai/allowed_signers`, and the tag naming itself. The
highest N is taken, never one lower than the version the server has, and `main` is never
fetched, so whoever controls the catalog's repository can neither offer manifests nobody signed
nor take a server back to an older version's images. A version that fails any of this leaves the
catalog as it was. It checks every field: an image pinned by tag and
digest, published ports from 1024 up and none of the NAS's own, folders only under the app's own
folder (plain names, never where shares go), environment values on one line, and no
`DOCKER_MODS` (it makes an image download more code at start). There is no field for privileged
mode, devices, capabilities, host networking, host folders or extra Docker arguments, so a
manifest can't ask for them. Each app gets a system user (`app-<app>`), and the container runs as
that user unless the image drops to it itself (the manifest says which), with a memory limit, at
most 2,048 processes, all of the NAS's processors but one (`apps.follow_limits` sets that in place
on containers made before, at each update and each time Docker starts), 30 MB of logs, and every
kernel capability dropped (`--cap-drop ALL`) but those its manifest's `capabilities` gives back,
from Docker's own default set less `NET_RAW` and `MKNOD` (so never more than Docker would give):
none for an app running as its own user, and Transmission's four (`CHOWN`, `DAC_OVERRIDE`,
`SETUID`, `SETGID`) for its root setup, its daemon running as its user with none.
`apps.follow_capabilities` remakes a container made otherwise, once, at the update. Generated
secrets reach the container through a root-only `--env-file`, never a command line.

An install, update, undo or uninstall runs as a systemd unit of its own
(`amahi-kai-appjob-<app>`), so a restart of the web app can't cut it off, one job per app at a
time. A new container is made beside the stopped old one and swapped in, and what it was made
from is kept (`app-definitions`), so a failure starts the old one again.

Each app gets its catalog ports when they're free (checked by binding them), otherwise the next
free ones, and keeps them. Ports are published on IPv4. Docker's own rules for published ports
come before UFW's, so the helper adds a chain, `AMAHI-APPS`, to Docker's `DOCKER-USER`: new
connections into a container (`docker0`) pass only from `tailscale0` or the NAS's own private
subnets, and the rest are dropped. `amahi-kai-app-firewall.service` (`apps.firewall`) rebuilds it
after Docker starts or restarts, and every install does too. There is no host networking, so an
app can't open ports of its own on the NAS.

An app reaches the NAS itself only for DNS (Unbound answers apps on Docker's bridge) and a ping.
UFW lets SSH, the admin page and Samba in from anywhere, and traffic from a container counts as
anywhere, so the same chain does: `AMAHI-APPS-NAS`, jumped to first from `INPUT` for `docker0`, for
IPv4 and IPv6, refuses everything else from an app, and lets back the replies to what the NAS asks
of an app. It's the helper's own chain (UFW keeps a rule there through its reloads), so it holds
with UFW off too, and `apps.firewall` builds it with `AMAHI-APPS`, before Docker starts as well.
Another app's port through the NAS's own address was already refused (UFW has no rule for app
ports in `INPUT`).

Each app is on a Docker network of its own (`amahi-<app>`, bridge `amahi<n>`, a /24 of
`172.30.0.0/16` that no address or route on the NAS overlaps, kept in `app-networks.json` for its
next install), so no app reaches another. The same `INPUT` jump covers `amahi+`. `AMAHI-APPS`
sends what an app sends through `AMAHI-APPS-OUT`: nothing to another app's network or Docker's
own bridge, then by the app's `network` (its manifest's; an app made before the field takes the
catalog's): `lan` passes, `none` is refused, and the rest (`internet`, the default) is refused to
the private ranges, Tailscale's, link-local, multicast and the NAS's LAN subnets, DNS aside. What
comes into an app goes through `AMAHI-APPS-IN`, as before: only from the NAS's private subnets and
`tailscale0`. Docker's bridge (`docker0`) has no apps on it once `apps.follow_networks` (the
update to 1.6.2) has moved them; until then a container there goes out as it always did. The
apps still ask Unbound on Docker's bridge address, which their networks reach as the NAS's own
(`INPUT`, DNS allowed), and Unbound answers `172.30.0.0/16`.

An app whose manifest says `access: tailscale` (catalog format 5, P4.7) is published on
`127.0.0.1` only, so nothing reaches its ports from the LAN or the internet. The helper puts its
web port on the tailnet itself, as root:
- `tailscale serve --bg --https=<port> http://127.0.0.1:<port>`: HTTPS with Tailscale's certificate
  for the NAS's name, at the app's own port. The port is a whole number, and the target is always
  the NAS itself.
- `tailscale serve --https=<port> off` at uninstall.

It first reads `tailscale status` and refuses the app, before anything changes, unless Tailscale
is connected, with MagicDNS on and a certificate for the NAS's name allowed. The name goes into
the app's environment (`{{tailscale_url}}`) only after it matches a DNS-name pattern. Such an app
isn't announced on the LAN.

A secret marked `hash: argon2` reaches the container as an Argon2id hash. The helper runs Ubuntu's
`argon2` with the secret on its stdin, never its command line, and a new random salt each time. It
installs that one package, by name, the first time it's needed, as it does `acl` for apps that
write into shares.

Shares are given to an app by name. The helper finds each share's folder in smb.conf (which only
it writes), checks the folder is in the share root or on a mounted data drive, and mounts it with
`--mount` (which never creates a missing folder) at `/shares/<name>`, read only unless the app's
manifest says `writes_shares` and Greyhole doesn't pool the share. A pooled share also brings its
copy folder on each Greyhole drive, read only. For a share an app writes into, the app joins the
`users` group in its container, and the share's folders get a default ACL (`setfacl -d`, applied to
folders only, through `find`, which doesn't follow links) so what the app makes stays group-writable.

An app can be given only some folders of a share instead (`/shares/<name>/<folder>`). Whatever it's
given, a share, a folder of one or a pooled share's copy folder, could be swapped for a link by
something that writes in the folder above it (a folder in a share, a share inside another, a pool
drive's copies), and Docker follows a link in a mount's source each time it starts a container, at
boot included. So the helper never gives Docker the path: it opens the folder without following a
link, checks that what it opened is that path (no link anywhere on the way), and bind-mounts it
through that handle (`/proc/self/fd/<n>`, `mount --no-canonicalize`) under
`/run/amahi-kai-app-shares`, root's only; the container mounts that. `/run` is empty after a
restart, and `amahi-kai-app-shares.service` (`apps.share_binds`) mounts the recorded ones again,
checked the same way, before Docker starts; one that's gone isn't mounted, so its app doesn't start
rather than starting without it. Folder names are refused with `..`, a comma, a quote or a control
character. System Update makes an app container from before this again once (`apps.follow_shares`).

An app of the owner's own (`custom.rb`) is a manifest the web app hands the helper
(`apps.custom_save`), kept as `/var/lib/amahi-kai/custom-apps/<id>.yml`, root's. It gets every check
above, and the helper installs and runs it exactly as the catalog's: what a manifest can't ask
for, it can't either. Its id must be new to the NAS (not the catalog's, and no container, data,
definition, secrets, storage or `app-<id>` user from an app before), so it can't take over another
app's folders, secrets or user, and one that starts as root keeps its folders off ZFS pools. The
web app asks for the owner's password again before it saves one, and the image is pinned by
digest from the registry the owner named (`AppVersions`, https only, never the NAS itself or a
link-local address). Nobody reviews its image. Its logo is a picture the helper checks by its
bytes (PNG, JPEG, WebP, or an SVG with no entities of its own, 256 KB at most) and keeps beside
its file; the web app serves it from the NAS under `default-src 'none'; sandbox`, so a script in
an SVG can't run as the person signed in, even opened on its own.

Updates (`apps.update`) run the version the catalog pins; the web app names the app. The helper
copies the app's folders (`cp -a`) into a root-only folder first, and puts them back
(`apps.undo_update`, or by itself when the new version isn't healthy) only from that copy, by
folder names it checks against the manifest's pattern. A version older than the one an app runs
is refused.

## Release keys

A release tag is signed with a release key: an SSH key the maintainer keeps, with a passphrase,
never on a server (`CONTRIBUTING.md`, Release keys). `config/allowed_signers` lists the keys' public
halves, and `bin/amahi-install-helper` installs it as `/etc/amahi-kai/allowed_signers`. When the
update check finds a newer release, the helper checks its tag against that file: `git verify-tag`
needs a signature by a key the file names, made with ssh-keygen (git gets no GPG or X.509 program
to run), and the tag must call itself by its own name, so an old release's tag can't be offered as
a newer one. On the `releases` and `candidates` channels, a newer release that isn't signed so is
refused: the helper offers nothing, System Update installs nothing, and System Status and the System
Update dialog say why. A signed one says which key signed it. `bin/amahi-update` takes the helper
for one from before update channels (and pulls `main` unchecked) only when its whole answer is
that it doesn't know `system.update_target`, never when a refusal's reason happens to say so: that
reason can quote a tag's own name. The release workflow also refuses to publish a tag that isn't
signed with one of the keys.

There are two keys, kept apart. Losing one changes nothing for a server: the next release is
signed with the other, and its `config/allowed_signers` swaps in a new key for the lost one. Losing
both: make a new key and put its line in `config/allowed_signers`, and add the same line to each
server's `/etc/amahi-kai/allowed_signers`, as root, before it takes the next release; until then it
refuses that release.

## Known gaps

- **Docker itself** runs as root: an app's container is as contained as Docker makes it.
- **The web app can add an app of its own choosing.** The password asked before an app of your
  own is saved is the web app's check, so something running as the web app's user could save one
  without it, and install it: any image, boxed in as above, with what it's given (its folders,
  the shares chosen, the internet). Before apps of your own, it could install only the catalog's.
  It still gets nothing past the box: no other app's data, no host folder, no capability Docker
  wouldn't give.
- **The `development` channel and a new install aren't checked.** `development` follows the `dev`
  branch, which has no signed tags, so whoever controls the repository controls what a server on
  that channel installs, as root; switching back to `releases` doesn't undo what it installed. So
  the root helper switches a server to `development` only when root's file
  `/etc/amahi-kai/allow-development` exists: neither the web app nor anything acting as it can
  move a server off signed releases. `bin/amahi-install-helper` makes the file on a server that
  follows `development` already (a development install included). A new install gets the code
  over HTTPS from GitHub as it is, and checks every release after that.
- **Greyhole's own work queue is open to every local account.** Greyhole's daemon runs as root and
  takes its work from `/var/spool/greyhole`, which has to be writable by everyone who can write to
  a pooled share (Samba's module writes there as the connecting user), and it doesn't hold the
  share and path it finds there to the pool's folders. So on a server with Greyhole installed,
  anything running as a local account, the web app's user included, can have root's Greyhole daemon
  work outside the pool. This is Greyhole's design, upstream; Amahi-kai neither creates that spool
  nor can shut it without stopping pooling. **On a server with Greyhole installed, take the claim
  above that the app's user can only reach root through this helper as holding for everything
  except Greyhole.** A pool of ZFS drives has nothing of the kind, and the storage plan prefers one
  (`docs/plans/storage.md`); Greyhole stays for basic SMB storage on mixed drives.
- **A setuid file can run as root from a ZFS snapshot.** A pool and its datasets are mounted
  `nosuid` (`setuid=off`, `devices=off`, and the share root and data drives are mounted `nosuid,nodev`),
  but the automatic mounts under a dataset's `.zfs/snapshot` aren't: a setuid-root file in a
  snapshot runs as root from there, measured on ZFS 2.2.2, which has no setting for it. It takes
  root writing such a file to a pool first (an app's image that starts as root, or a drive prepared
  elsewhere), plus a way to run it. The catalog rule against images that start as root covers the
  first; re-check when Ubuntu's ZFS has the setting.
- **The database isn't rolled back** with the code: migrations must keep working with the
  previous version's code. System Update dumps the database first (`/var/lib/amahi-kai/backups`,
  root-only, the last 3); restoring one is a manual step.

## Checking a NAS

```
sudo -l -U amahi                                   # the 1 rule above
sudo /usr/local/sbin/amahi-helper --self-test      # ok: N operations
sudo tail -5 /var/log/amahi-kai/helper.log         # recent root actions
sudo find /opt/amahi-kai -xdev \( -path /opt/amahi-kai/tmp -o -path /opt/amahi-kai/log \
  -o -path /opt/amahi-kai/public/assets -o -path /opt/amahi-kai/vendor/bundle \) -prune \
  -o ! -user root -print | head                    # prints nothing
```

## Adding something that needs root

Add an operation to its area's part in `libexec/amahi-helper.d/` (arguments, validation, plan), with specs in
`spec/lib/amahi_helper_spec.rb`, and call it with `Privileged.call`. Don't add a sudoers rule. The
contract spec in `spec/lib/privileged_spec.rb` fails if the app calls an operation the helper
doesn't have, or the helper has one nothing calls. Never run app code as root in
`bin/amahi-install` or `bin/amahi-update`; use `as_app` (`spec/lib/install_scripts_spec.rb`
checks). Nor change anything as root by a path through a folder the app owns (the same spec): the
app user can put a link at any name in it.

Each new operation or argument goes in the table in `spec/lib/amahi_helper_checks_spec.rb`, which
fails until it's there: a request that's accepted, and what each argument may hold besides. Every
argument is tried with about 30 kinds of bad value, with the helper's own checks running. If the
operation writes a config a tool reads, add what the check passes over to
`spec/lib/amahi_helper_real_tools_spec.rb`, where the real tool reads it (CI's Real Tools job).
