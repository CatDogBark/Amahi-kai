# Privilege model

How Amahi-kai gets root access on a NAS, and what keeps the web app from turning a bug into
root. Last updated 2026-10-05 (Phase 4 P4.5: app updates). Design and history: [`docs/plans/privileged-helper.md`](../plans/privileged-helper.md).

## Summary

The web app runs as the unprivileged `amahi` user. It reaches root one way only:
**the root helper**, `/usr/local/sbin/amahi-helper` (from `libexec/amahi-helper`). It runs a
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
| `/etc/amahi-kai/tunnel.token` | root:root 0600 | Only `cloudflared` (as root) reads it |
| `/etc/greyhole.conf` | root:amahi 0640 | Holds the database password |
| `/var/log/amahi-kai/helper.log` | root:amahi 0640 | The helper's audit log; the app can read it, not write it |
| `/var/log/amahi-kai/update.log` | root, in a root:amahi 0750 folder | The last System Update's output; the update page reads it |
| `/var/lib/amahi-kai/backups/` | root:root 0700 | Database dumps taken before each update's migrations (the last 3) |
| `/var/lib/amahi-kai/apps/<app>/` | `app-<app>`, 0750 | A Docker app's folders, owned by its own system user (uid below 1000) |
| `/var/lib/amahi-kai/app-secrets/<app>.json` | root:amahi 0640 | Passwords and keys generated at an app's install; shown to admins |
| `/var/lib/amahi-kai/app-ports.json` | root:amahi 0640 | The host ports each app was given; the Apps page shows them |
| `/var/lib/amahi-kai/app-backups/<app>/` | root:root 0700, in a root:amahi 0750 folder | The copy of an app's data from before its last update, kept 30 days; `<app>.json` beside it (root:amahi 0640) describes it for Undo update |

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
reboot and power off, the hostname, dnsmasq, swap, data drives and fstab, ZFS pools (created
only on whole data disks with nothing in use on them; pools mount under `/srv/pools`, where no
share folder may be made), Greyhole, package
installs (from pinned apt repositories and a fixed package list), the Cloudflare Tunnel,
Tailscale, the security audit's fixes, drive temperatures, the storage health check (pools and
SMART, every 15 minutes from `amahi-kai-storage-check.timer`, written to
`/var/lib/amahi-kai/storage-health.json`), and System Update (starting it, or
checking for an update: `git fetch` as root, written to `/var/lib/amahi-kai/update-status.json`,
every 6 hours from `amahi-kai-update-check.timer`). `amahi-helper --list` prints the operations, and
`--dry-run OPERATION` shows what a request would do without doing it.

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
manifest from the root-owned code (`config/apps/<app>.yml`) and checks every field: an image
pinned by tag and digest, published ports from 1024 up and none of the NAS's own, folders only
under the app's own folder, environment values on one line. There is no field for privileged
mode, devices, capabilities, host networking, host folders or extra Docker arguments, so a
manifest can't ask for them. Each app gets a system user (`app-<app>`), and the container runs as
that user unless the image drops to it itself (the manifest says which), with a memory limit.
Generated secrets reach the container through a root-only `--env-file`, never a command line.

Each app gets its catalog ports when they're free (checked by binding them), otherwise the next
free ones, and keeps them. Ports are published on IPv4. Docker's own rules for published ports
come before UFW's, so the helper adds a chain, `AMAHI-APPS`, to Docker's `DOCKER-USER`: new
connections into a container (`docker0`) pass only from `tailscale0` or the NAS's own private
subnets, and the rest are dropped. `amahi-kai-app-firewall.service` (`apps.firewall`) rebuilds it
after Docker starts or restarts, and every install does too. There is no host networking, so an
app can't open ports of its own on the NAS.

Shares are given to an app by name. The helper finds each share's folder in smb.conf (which only
it writes), checks the folder is in the share root or on a mounted data drive, and mounts it with
`--mount` (which never creates a missing folder) at `/shares/<name>`, read only unless the app's
manifest says `writes_shares` and Greyhole doesn't pool the share. A pooled share also brings its
copy folder on each Greyhole drive, read only. For a share an app writes into, the app joins the
`users` group in its container, and the share's folders get a default ACL (`setfacl -d`, applied to
folders only, through `find`, which doesn't follow links) so what the app makes stays group-writable.

Updates (`apps.update`) run the version the catalog pins, which only a change to the root-owned
code can move; the web app names the app. The helper copies the app's folders (`cp -a`) into a
root-only folder first, and puts them back (`apps.undo_update`, or by itself when the new version
isn't healthy) only from that copy, by folder names it checks against the manifest's pattern.

## Known gaps

- **Docker itself** runs as root: an app's container is as contained as Docker makes it. The
  catalog decides what runs, and it is reviewed with the code.
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

Add an operation to `libexec/amahi-helper` (arguments, validation, plan), with specs in
`spec/lib/amahi_helper_spec.rb`, and call it with `Privileged.call`. Don't add a sudoers rule. The
contract spec in `spec/lib/privileged_spec.rb` fails if the app calls an operation the helper
doesn't have, or the helper has one nothing calls. Never run app code as root in
`bin/amahi-install` or `bin/amahi-update`; use `as_app` (`spec/lib/install_scripts_spec.rb`
checks).
