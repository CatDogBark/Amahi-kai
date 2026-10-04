# Privilege model

How Amahi-kai gets root access on a NAS, and what keeps the web app from turning a bug into
root. Last updated 2026-10-04 (PR O). Design and history: [`docs/plans/privileged-helper.md`](../plans/privileged-helper.md).

## Summary

The web app runs as the unprivileged `amahi` user. It reaches root in two ways only:

1. **The root helper**, `/usr/local/sbin/amahi-helper` (from `libexec/amahi-helper`). It runs a
   fixed list of operations, checks every request, and logs every call. One of them,
   `system.update`, starts **System Update**: `bin/amahi-update` as its own systemd job
   (`amahi-kai-update.service`), which pulls the code and redeploys, and rolls back if that
   fails. The page follows its log, `/var/log/amahi-kai/update.log`.
2. **Docker**: the app runs `docker` through sudo and its user is in the `docker` group. Either
   is full control of the NAS. Phase 4 narrows this.

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
reboot and power off, the hostname, dnsmasq, swap, data drives and fstab, Greyhole, package
installs (from pinned apt repositories and a fixed package list), the Cloudflare Tunnel,
Tailscale, the security audit's fixes, drive temperatures, and System Update (starting it, or
checking for an update: `git fetch` as root, written to `/var/lib/amahi-kai/update-status.json`,
every 6 hours from `amahi-kai-update-check.timer`). `amahi-helper --list` prints the operations, and
`--dry-run OPERATION` shows what a request would do without doing it.

In Rails, `Privileged.call('users.create', login: 'ann', name: 'Ann')` runs an operation through
`sudo -n`. In tests it records the call instead.

## Sudoers

`config/sudoers/amahi-kai`, 5 rules:

| Rule | For |
| --- | --- |
| `/usr/local/sbin/amahi-helper` | Everything above, System Update included |
| `/usr/bin/docker`, `mkdir -p /opt/amahi/*`, `cp /tmp/amahi-staging/* /opt/amahi/*`, `rm -rf /opt/amahi/apps/*` | Docker apps (Phase 4) |

## Known gaps

- **Docker** is root-equivalent: `sudo docker` and the `docker` group both are. Phase 4 starts
  with a design for Docker apps (per-app access, no Docker socket for the web app).
- **The database isn't rolled back** with the code: migrations must keep working with the
  previous version's code. System Update dumps the database first (`/var/lib/amahi-kai/backups`,
  root-only, the last 3); restoring one is a manual step.

## Checking a NAS

```
sudo -l -U amahi                                   # the 5 rules above
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
