# Privileged helper (Phase 3, PRs L and M)

Status: **PR L done** (#24, checked on the NAS 2026-10-04). **PR M** is split in three (Troy,
2026-10-04): **M1 done** (#26: services, reboot/power off, hostname, dnsmasq, swap), **M2 done**
(#27: data drives, Greyhole), **M3 done** (#28: packages, tunnel, Tailscale, Docker install,
security audit with PR P). Sudoers is now the helper, the updater and Docker. **PR N built**: the
code in `/opt/amahi-kai` is root's, so the `amahi` user can't change what root runs (see
[`docs/security/PRIVILEGE-ESCALATION-MITIGATION.md`](../security/PRIVILEGE-ESCALATION-MITIGATION.md)).

## Why

The app (service user `amahi`) gets root through about 116 sudoers rules, written by
`bin/amahi-install`, and about 130 call sites (`Shell.run` with an auto-`sudo` prefix, plus ~40
hand-written `sudo` strings). Several rules are root-equivalent on their own (commands allowed with
any arguments, and wildcard paths, which in sudoers also match `..` and spaces). So in practice
`amahi` is root, and nothing checks what the app asks for.

The helper replaces that with **one root-owned program that does a fixed list of operations and
validates every request itself**. It is also the first version of the platform's capability API
(see `roadmap.md`, Direction): the web UI calls `users.create`, not `useradd`.

## Design

### 1. One root-owned program outside the app directory

- Source in the repo: `libexec/amahi-helper`. Installed as `/usr/local/sbin/amahi-helper`,
  `root:root 0755`, by `bin/amahi-install-helper`, which `bin/amahi-install` and `bin/amahi-update`
  run as root.
- Never run it from `/opt/amahi-kai` directly. Since PR N that tree is root's (only `tmp/`,
  `log/`, `public/assets/` and `vendor/bundle/` are `amahi`'s), so `amahi` can't change the source
  the updater installs; before N it could.
- One sudoers line: `amahi ALL=(root) NOPASSWD: /usr/local/sbin/amahi-helper`.

### 2. Plain Ruby, standard library only

- Shebang `#!/usr/bin/ruby --disable-gems`. No Rails, no Bundler, no gems: those live in
  `amahi`-writable directories and must never load in a root process. Refuses to run if `RUBYOPT`
  or `RUBYLIB` is set (sudo's `env_reset` normally strips them).
- Runs commands by absolute path as argument lists with a fixed minimal environment
  (`PATH=/usr/sbin:/usr/bin:/sbin:/bin`), never through a shell.
- `module AmahiHelper` with the CLI entry under `if $PROGRAM_NAME == __FILE__`, so RSpec loads it
  and tests validation and planning directly. Ruby 3.2 has no `File::DIRECTORY`, so folders are
  opened with `NOFOLLOW` and checked with `fstat`.

### 3. Interface

```
sudo -n /usr/local/sbin/amahi-helper users.create        # stdin: {"login":"ann","name":"Ann"}
sudo -n /usr/local/sbin/amahi-helper users.set_password  # stdin: {"login":"ann","password":"..."}
→ stdout {"ok":true} or {"ok":false,"error":"login root is reserved"}
```

- The operation name is the only argument. All arguments, secrets included, arrive as one JSON
  object on stdin, so nothing appears in `ps`, the journal or sudo's log. Unknown or missing
  arguments are refused.
- Exit 0 = done; 1 = refused by validation (nothing changed); 2 = a step failed (the command's
  stderr is in `error`).
- `--dry-run OP` validates and prints the planned steps (passwords withheld); `--list` prints the
  operations; `--self-test` checks the operation table and that no gems are loaded.
- Rails side: `lib/privileged.rb`, `Privileged.call('users.create', login:, name:)` returns the
  reply or raises `Privileged::Error` with the helper's message, which the UI shows. As root (the
  updater's `rails runner`, the installer's seeds) it runs the helper without `sudo`. In dummy mode
  (dev/test) it runs nothing, records calls in `Privileged.calls` and returns `{"ok"=>true}`.

### 4. The helper validates everything and trusts nothing from Rails

- Logins: `\A[a-z][a-z0-9]{2,31}\z`; `root`, `amahi` and `nobody` are reserved. Change or delete
  only accounts the app created: uid ≥ 1000 and primary group `users`. Anything else is refused.
- Names (GECOS): no control characters or `:`, at most 64 characters (the `User` model checks the
  same). Passwords: no line breaks, at most 256 characters.
- Share paths: absolute and normalized (no `.`, `..`, `//`), strictly inside the share root
  `/var/lib/amahi-kai/files` or a data drive mounted at `/mnt/<name>` (an unmounted mount point is
  just a folder on the OS disk, so it's refused). A root must be a real directory at its own path.
  Folders are changed through an open file descriptor after checking (via `/proc/self/fd`) that it
  is the folder that was asked for, so a folder swapped for a symlink can't redirect a `chown`.
- `samba.write_config`: the helper writes the content to a temp file in `/etc/samba`, runs
  `testparm -s` on it, and renames it into place only if that passes. Samba can run commands as
  root and change identities from its config, so the raw text and testparm's canonical output are
  both checked, comparing names the way Samba does (case and spaces ignored). Refused: anything
  that runs a command (`*exec`, `*command`, `*script`, `*program`, except `dfree command =
  /usr/bin/greyhole-dfree`), `include`, `config file`, `username map`, `admin users`, `root
  directory`, `panic action`, `wins hook` and Samba's own path settings; `force user`/`force
  group`/`guest account` of root; `log file` outside `/var/log/samba`; share paths outside the
  roots above; VFS modules not on a short list. This applies to share "extra parameters" too.
- Services: only the ones `lib/system_services.rb` gives actions to (`SERVICES` in the helper; a
  spec checks the two lists match), by key, never a unit name from the request.
- dnsmasq can run scripts as root and read any file from its config, and the app writes its files
  whole, so every line must match one the app generates (`DNSMASQ_LINES`, `DNS_ALIAS_LINES`), and
  where dnsmasq is installed, `dnsmasq --test` must accept the file.
- Hostname: one DNS label (letters, digits, hyphens, at most 63). Swap: 1–8 GB at `/swapfile`, only
  when the file doesn't exist.

### 5. Audit log

Every call appends one JSON line to `/var/log/amahi-kai/helper.log` (`root:amahi 0640` in a
`root:amahi 0750` folder, so the UI can show it later): time, operation, arguments with
`password`/`secret`/`token`/`key` fields replaced by `[FILTERED]` and file contents replaced by
their size and SHA-256, the calling user (`SUDO_USER`), result and error, and duration. Rotated
weekly by `/etc/logrotate.d/amahi-kai` (`config/logrotate-amahi-kai.conf`).

### 6. Sudoers as a file in the repo

`config/sudoers/amahi-kai`. `bin/amahi-install-helper` copies it next to the live file under a name
with a dot (sudo skips those), runs `visudo -cf` on it, and only then moves it into place, so a
broken file can't disable sudo; on failure the old file stays and the script exits non-zero. Each PR
deletes the rules it made unnecessary, but only after a grep shows no remaining caller.

### 7. Tests

- `spec/lib/amahi_helper_spec.rb` loads the helper and tests, for each operation, validation (good
  and bad input) and the planned steps; file actions run on temporary folders; the CLI runs as its
  own process with `--disable-gems`; the generated `smb.conf` must pass the Samba checks; where
  Samba is installed, the real `testparm` is used.
- `spec/lib/privileged_spec.rb`: how Rails runs the helper, and a contract check that every
  `Privileged.call('<op>'` in `app/` and `lib/` names an operation and every operation is called.
- CI (lint job): `ruby --disable-gems libexec/amahi-helper --self-test` and
  `sudo visudo -cf config/sudoers/amahi-kai`.

## PR L: users, Samba, share folders (built)

| Operation | Replaces | Runs |
| --- | --- | --- |
| `users.create` {login, name} | `User#create_system_account` | `useradd -m -g users -s /usr/sbin/nologin -c <name> <login>` |
| `users.set_password` {login, password} | `User#sync_samba_password` | `pdbedit -d0 -t -a -u <login>`, password twice on stdin |
| `users.set_name` {login, name} | `usermod -c` in `User#before_save_hook` | `usermod -c <name> <login>`, only when the name changes |
| `users.normalize` {login} | (new) | `usermod -s /usr/sbin/nologin -G '' <login>` if the shell or extra groups differ |
| `users.delete` {login} | `User#before_destroy_hook` | `pdbedit -x` (failure ignored); `userdel -r` for app-created accounts |
| `samba.write_config` {content} | `SambaService.write_smb_conf` | checks above, `testparm -s`, atomic rename |
| `samba.write_lmhosts` {content} | `SambaService.write_lmhosts` | address-and-name lines only, atomic rename |
| `samba.reload` | `Platform.reload(:smb/:nmb)` | `systemctl try-reload-or-restart smbd.service nmbd.service` |
| `shares.create_dir` {path} | `ShareFileSystem` mkdir/chown/chmod | create, then `amahi:users`, `2775` |
| `shares.remove_dir` {path} | `ShareFileSystem` rmdir | remove only if empty |
| `shares.set_guest_write` {path, writable} | `chmod o+w` / `o-w` | top folder only |

`bin/amahi-update` runs `User.normalize_system_accounts` (→ `users.normalize`) on every update, so
existing accounts lose `/bin/sh` and the `sudo` group.

Removed sudoers rules: `useradd`, `usermod` (except `usermod -aG docker amahi`), `userdel`,
`pdbedit`, the `chmod`/`chown`/`mkdir` rules on `/var/lib/amahi-kai/*` and `/home/*/.ssh`, and the
`cp … /etc/samba/*` rules. The `systemctl … smbd/nmbd` rules stay until M (Settings → Servers uses
them). Also removed: `Platform.make_admin`, `Platform.update_user_pubkey`, the per-user SSH key
setting (it never worked on the NAS: sudo refused its `mkdir` and `mv`, so no keys were installed),
and `ShareFileSystem#clear_permissions` (`chmod -R a+rwx`, which nothing called).

### Check on the NAS after the System Update (Troy)

1. Users: create a test user with a password, log in to `smb://192.168.1.111/<user>`, change the
   password (old one fails, new one works), delete the user (`getent passwd <user>` is empty).
2. Shares: create a share (its folder is `amahi:users`, mode `2775`), toggle guest write, delete it.
3. `sudo tail /var/log/amahi-kai/helper.log` shows each call and no passwords.
4. `sudo -l -U amahi` lists the helper, and the removed rules are gone.
5. The existing `smb://192.168.1.111/admin` still works.

## PR M1: services, system, network (done, #26)

| Operation | Replaces | Runs |
| --- | --- | --- |
| `services.start`/`stop`/`restart` {service} | `Shell.run("systemctl …")` in `SystemServices` (Settings → Servers), `SecurityAudit`, `Host`, `DnsAlias` | `systemctl <verb> <unit>` |
| `services.enable`/`disable` {service} | `DnsmasqService.start!`/`stop!` | `systemctl enable --now` / `disable --now` |
| `system.reboot`, `system.poweroff` | `Platform.reboot!`/`poweroff!` (sudo had no rule for them, so the buttons did nothing) | `systemctl reboot` / `poweroff` |
| `system.create_swap` {size_gb} | `SwapService` (setup wizard) | create `/swapfile` 600, `fallocate` (or `dd`), `mkswap`, `swapon`, one fstab line |
| `network.set_hostname` {hostname} | `Platform.set_hostname!` (setup wizard) | `hostnamectl set-hostname` |
| `network.write_dnsmasq_config` {content} | `DnsmasqService.write_config!` | checked lines, `dnsmasq --test`, atomic write to `/etc/dnsmasq.d/amahi.conf` |
| `network.write_dns_aliases` {content} | `DnsAlias#regenerate_dnsmasq_config` | `address=` lines only, atomic write to `/etc/dnsmasq.d/amahi-aliases.conf` |

Removed sudoers rules (24): `systemctl start|stop|reload|enable|disable` for `smbd`/`nmbd`, all six
`dnsmasq.service` rules, `hostnamectl set-hostname *`, the two `cp … /etc/dnsmasq.d/*` rules, and
the swap rules (`fallocate`, `dd`, `chmod 600 /swapfile`, `mkswap`, `swapon`). `systemctl restart
smbd.service`/`nmbd.service` stayed until M2.

## PR M2: data drives and Greyhole (done, #27)

A data drive is a whole disk or partition (`sd*`, `vd*`, `xvd*`, `nvme*`) whose disk has nothing
mounted outside `/mnt`. The helper checks that itself from `lsblk`, so the OS disk (`/` on LVM
included), a disk used for swap or one mounted by hand elsewhere is refused whatever Rails sends.

| Operation | Replaces | Runs |
| --- | --- | --- |
| `disks.format` {device} | `DiskManager.format_disk!` (Disks, setup wizard) | unmounted data drive only: `mkfs.ext4 -F`, `udevadm settle` |
| `disks.mount` {device, mount_point} | `DiskManager.mount!` | `/mnt/<name>` (new, or an empty folder that isn't a mount point, and not a slot fstab gives another drive); `mount` (`ntfs-3g` for NTFS); one fstab line by UUID with the PR #13 options; replies with the mount point |
| `disks.unmount` {device} | `DiskManager.unmount!` | `umount`; removes only that UUID's fstab line (old file kept as `/etc/fstab.amahi-backup`); removes an empty `/mnt/storage-N` |
| `disks.preview` {device} | `DiskManager.preview` (broken: its `mkdir` in `/tmp` had no sudo rule) | mounts read-only in `/run` (`nosuid,nodev,noexec`, no journal replay), lists the top level with sizes (stops at a million entries or 30 s), unmounts |
| `greyhole.write_config` {content} | `Greyhole.configure!` | only the lines `Greyhole.generate_config` writes, pool drives under `/mnt`; `/etc/greyhole.conf` root:amahi 0640 (it holds the database password) |
| `greyhole.setup_database` | the SQL in `DiskService` and `SetupService` | `CREATE DATABASE greyhole`, grant to the app's MariaDB user, load the schema once the package has put it in place |
| `packages.add_repository` {repository} | three copies of the Greyhole repo setup | `greyhole` only: key over HTTPS, accepted only if its fingerprints (key and subkey) are exactly the pinned ones, then the keyring and source list |
| `packages.install` {packages} | `sudo apt-get install` for Greyhole | `greyhole`, `php8.3-mbstring`, `php8.3-mysql` only; `apt-get update` and `install` non-interactive, apt's output streamed to the page |

Greyhole has one install path, `Greyhole.install!`, used by Disks → Storage Pool and the setup
wizard. `Privileged.call` takes a block for streamed progress. Greyhole's `reinject_samba_globals!`
(a `sed` on `smb.conf` as `amahi`, which couldn't work) and `fsck` (no callers) are gone.

Removed sudoers rules (26): `mkfs.ext4`, `mount`, `umount`, `mkdir -p /mnt/*`, `rmdir /mnt/*`,
`tee -a /etc/fstab`, `cp /tmp/fstab.new /etc/fstab`, `lsblk`, `blkid`; the seven
`greyhole.service` rules, `cp`/`tee` to `/etc/greyhole.conf`, the Greyhole key and list copies
from `/tmp`, `mysql -u root *`, `dpkg --configure -a`, `phpenmod *`; `systemctl restart
smbd.service`/`nmbd.service`; and `mysqldump`, which nothing used and which could write any file
as root.

### Check on the NAS after the System Update (Troy)

Drives can't be tested until the NAS hardware arrives (VM 104's disks belong to Proxmox).

1. The update's last line is "✓ Amahi-kai updated and running!".
2. Disks and Disks → Storage Pool load and list the drives as before.
3. `sudo -l -U amahi | grep -cE 'mount|mkfs|fstab|greyhole|mysql'` prints `0`.
4. `sudo /usr/local/sbin/amahi-helper --self-test` prints `ok: 30 operations`.

## PR M3: packages, tunnel, Tailscale, security audit (done, #28)

Every package install now goes through `packages.add_repository` and `packages.install`. The
helper knows four apt repositories (Greyhole, Cloudflare, Tailscale, Docker), each with its key's
fingerprints pinned, and a fixed package list (Greyhole and its PHP modules, `cloudflared`,
`tailscale`, Docker Engine, `dnsmasq`, `fail2ban`, `unattended-upgrades`). Keyring and source-list
paths are the ones earlier installs used, so an installed repository is rewritten in place.

| Operation | Replaces | Runs |
| --- | --- | --- |
| `tunnel.configure` {token} | `CloudflareService.configure!` (Rails wrote the unit file and token, and root copied them) | token checked (base64 characters), saved root-only 0600; the helper writes the unit itself (`--token-file`); `daemon-reload`, `enable`, `restart` |
| `tunnel.start`/`stop`/`restart` | `systemctl … cloudflared` sudo rules | `systemctl <verb> cloudflared.service` |
| `tailscale.start` | `systemctl enable/start tailscaled` | `systemctl enable --now tailscaled.service` |
| `tailscale.up` | `sudo timeout 10 tailscale up` | the same, output streamed so the page gets the login URL |
| `tailscale.down`, `tailscale.logout` | `sudo tailscale …` (an unrestricted rule) | `tailscale down`; `tailscale logout` and stop `tailscaled` |
| `docker.grant_app_user` | `usermod -aG docker amahi` | the same, once the `docker` group exists |
| `security.report` | `ufw status` and reading `sshd_config` | UFW's state and sshd's effective settings (`sshd -T`, so drop-ins count) |
| `security.enable_firewall` | `ufw *` | deny incoming; allow 22/tcp, 3000/tcp, 443/tcp, 445/tcp, 139/tcp, 137:138/udp, plus 53 and 67/udp once Amahi-kai has configured dnsmasq; enable |
| `security.harden_ssh` {setting} | copying a Rails-written `sshd_config` over the real one | `root_login` or `password_login` (password and keyboard-interactive) set to `no` in `sshd_config.d/10-amahi-kai.conf`, checked with `sshd -t` (old file put back if it fails), `try-reload-or-restart ssh`. Password login is refused while no account with a login shell has a key in `~/.ssh/authorized_keys` (Troy, 2026-10-04) |
| `security.enable_auto_updates` | `dpkg-reconfigure -plow unattended-upgrades` | writes `20auto-upgrades` as that dialog does |

Rails: `CloudflareService`, `TailscaleService` (status is read without root), `DockerService`
(one install path; the Apps page's own copy is gone), the dnsmasq install on Network → Gateway, and
`SecurityAudit`. PR P is in it: the SSH checks use `sshd -T`; automatic updates must be turned on,
not only installed; a new check warns about Docker-published ports, which bypass UFW; a refused
fix shows the helper's reason; and setting up, starting or restarting the tunnel is refused on the
server while the audit has blockers (stopping it never is). Tunnel Restart now restarts.

Removed sudoers rules (42): every `apt-get` rule (all `SETENV`), the Docker key, list, `usermod`
and `systemctl` rules, all Cloudflare rules (`cloudflared` unrestricted, unit and token copies,
`rm -f /etc/systemd/system/cloudflared*`, `daemon-reload`, the service and repository rules), all
Tailscale rules (`bash /tmp/tailscale-install.sh`, `tailscale` unrestricted, `timeout … tailscale`,
the `tailscaled` service rules), and the security rules (`ufw *`, ssh restarts, `dpkg-reconfigure`,
copying `sshd_config`). 52 → 10 rules: the helper, the Docker app folders, `docker`, `smartctl` and
the updater.

### Check on the NAS after the System Update (Troy)

1. The update's last line is "✓ Amahi-kai updated and running!".
2. Network → Remote Access shows the tunnel connected and Tailscale running, as before.
3. Network → Security runs the audit; the SSH lines match `sudo sshd -T`.
4. `sudo -l -U amahi | grep -c NOPASSWD` prints `10`.
5. `sudo /usr/local/sbin/amahi-helper --self-test` prints `ok: 43 operations`.

## Decisions (Troy, confirmed 2026-10-03)

1. **Web admins in the Linux `sudo` group**: dropped. Web admin and OS admin are separate; making
   someone an admin no longer touches Linux groups or rewrites `smb.conf`.
2. **Shell access for web users**: app-created accounts get `/usr/sbin/nologin`, and the SSH key
   setting is gone (Troy uses his own `troy` account for SSH). The `public_key` column stays until
   a later cleanup.
3. **Language**: Ruby, standard library only.
4. **Share "reset permissions"**: it turned out the button only empties the share's user lists;
   the `chmod -R a+rwx` was dead code. Troy chose (2026-10-04) to delete it and add no
   reset-permissions operation for now.
5. **SSH password login fix** (2026-10-04): the helper turns it off only while an account that
   can log in has an SSH key; Fix all still includes it.
