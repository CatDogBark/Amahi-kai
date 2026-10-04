# Privileged helper (Phase 3, PRs L and M)

Status: design agreed in outline on 2026-10-03; **four decisions below are Troy's to confirm before
PR L starts.**

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
  `root:root 0755`, by `bin/amahi-install` and `bin/amahi-update` (both run as root).
- Never run it from `/opt/amahi-kai`: that tree is writable by `amahi` until PR N, and an
  `amahi`-writable root program is a root shell. (Until N, `amahi` could still change the source
  before the next update copies it. That is the same exposure the updater has today, and N closes
  it.)
- One sudoers line: `amahi ALL=(root) NOPASSWD: /usr/local/sbin/amahi-helper`.

### 2. Plain Ruby, standard library only

- Shebang `#!/usr/bin/ruby --disable-gems`. No Rails, no Bundler, no gems: those live in
  `amahi`-writable directories and must never load in a root process. Refuse to start if `RUBYOPT`
  or `RUBYLIB` is set (sudo's `env_reset` normally strips them).
- Run commands by absolute path as argument lists (`Open3.capture3(ENV_MIN, '/usr/sbin/useradd',
  ...)` with a fixed minimal `PATH`), never through a shell.
- Structure the file as `module AmahiHelper` with the CLI entry under `if $0 == __FILE__`, so
  RSpec can load it and test validation and command planning directly.

### 3. Interface

```
sudo /usr/local/sbin/amahi-helper users.create      # JSON on stdin: {"login":"troy2","name":"Troy"}
sudo /usr/local/sbin/amahi-helper users.set_password  # {"login":"troy2","password":"..."}
→ stdout {"ok":true} or {"ok":false,"error":"login 'root' is a system account"}
```

- The operation name is the only argument. All arguments, secrets included, arrive as one JSON
  object on stdin, so nothing appears in `ps`, the journal or sudo's log.
- Exit 0 = done; 1 = refused by validation (nothing ran); 2 = a command failed (stderr included in
  `error`).
- Rails side: `lib/privileged.rb`, `Privileged.call('users.create', login:, name:)` returns the
  parsed result or raises `Privileged::Error` with the helper's message, which the UI shows. When
  `Process.uid == 0` (installer, updater tasks) it runs the helper without `sudo`. In dummy mode
  (dev/test) it runs nothing, records calls in `Privileged.calls` and returns `{ok: true}`.

### 4. The helper validates everything and trusts nothing from Rails

- Logins: `\A[a-z][a-z0-9]{2,31}\z`; refuse `root` and any uid below 1000. Modify or delete only
  accounts the app created (primary group `users`), as `User#app_created_system_account?` does.
- Names (GECOS): printable, no `:` or newline, at most 64 characters.
- Share paths: `File.realpath` (of the parent when creating) must sit inside an allowed root: the
  share root `/var/lib/amahi-kai/files`, or a mounted data drive under `/mnt/`. Everything else is
  refused, including `/`, `/etc` and `/home`.
- `samba.write_config`: the helper writes the content to a temp file in `/etc/samba`, runs
  `testparm -s` on it, and renames it into place only if that passes. No copies from `/tmp`.
- Unit names (PR M) come from the same list as `lib/system_services.rb`.

### 5. Audit log

Every call appends one JSON line to `/var/log/amahi-kai/helper.log` (`root:amahi 0640`, so the UI
can show it later): time, operation, arguments with `password`/`secret`/`token`/`key` fields
replaced by `[FILTERED]`, the calling user (`SUDO_USER`), result and duration. Add a logrotate
entry.

### 6. Sudoers as a file in the repo

Move the heredoc in `bin/amahi-install` into `config/sudoers/amahi-kai`. Both scripts install it
after `visudo -cf` passes, and keep the old file if it doesn't. Each PR deletes the rules it made
unnecessary, but only after a grep shows no remaining caller. Delete the stale
`config/sudoers.d/amahi-kai` (an old `www-data` file nothing installs).

### 7. Tests

- Unit specs load the helper and test, for each operation, the validation (good and bad input) and
  the planned commands (dry-run mode returns the argument lists instead of running them).
- Contract spec: every `Privileged.call('<op>'` in `app/` and `lib/` names an operation in
  `AmahiHelper::OPERATIONS`.
- CI: `ruby --disable-gems libexec/amahi-helper --self-test` (proves it loads without gems), and
  `visudo -cf config/sudoers/amahi-kai`.

## PR L scope: users, Samba, share folders

| Operation | Replaces | Runs |
| --- | --- | --- |
| `users.create` {login, name} | `User#create_system_account` | `useradd -m -g users -s <shell> -c <name> <login>` |
| `users.set_password` {login, password} | `User#sync_samba_password` | `pdbedit -d0 -t -a -u <login>`, password twice on stdin |
| `users.set_name` {login, name} | `usermod -c` in `User#before_save_hook` | `usermod -c <name> <login>` |
| `users.delete` {login} | `User#before_destroy_hook` | `pdbedit -x`; `userdel -r` only for app-created accounts |
| `users.set_ssh_key` {login, key} | `Platform.update_user_pubkey` | only if decision 2 keeps it: writes `~/.ssh/authorized_keys` 0600, dir 0700, owned by the user; one line, a known key type, at most 8 KB |
| `samba.write_config` {content} | `SambaService.write_smb_conf` | validate with `testparm`, atomic rename |
| `samba.write_lmhosts` {content} | `SambaService.write_lmhosts` | atomic write |
| `samba.reload` | `Platform.reload(:smb)` | `systemctl reload smbd.service` |
| `shares.create_dir` {path} | `ShareFileSystem` mkdir/chown/chmod | `mkdir -p`, `chown amahi:users`, `chmod 2775` |
| `shares.remove_dir` {path} | `ShareFileSystem` rmdir | `rmdir` (only if empty) |
| `shares.set_guest_write` {path, writable} | `chmod o+w` / `o-w` | top directory only |
| `shares.reset_permissions` {path} | `chmod -R a+rwx` | per decision 4 |

`Platform.make_admin` (adds web admins to the Linux `sudo` group) goes or stays per decision 1.

Then remove the sudoers rules these replaced: `useradd`, `usermod`, `userdel`, `pdbedit`, the
`chmod`/`chown`/`mkdir` rules on `/var/lib/amahi-kai/*` and `/home/*/.ssh`, and the `cp … /etc/samba/*`
rules. Keep the `systemctl … smbd/nmbd` rules until M (Settings → Servers uses them).

### Check on the NAS after the System Update (Troy)

1. Users: create a test user with a password, log in to `smb://192.168.1.111/<user>`, change the
   password (old one fails, new one works), delete the user (`getent passwd <user>` is empty).
2. Shares: create a share (its folder is `amahi:users`, mode `2775`), toggle guest write, delete it.
3. `sudo tail /var/log/amahi-kai/helper.log` shows each call and no passwords.
4. `sudo -l -U amahi` lists the helper, and the removed rules are gone.

## PR M scope (outline)

`services.start|stop|restart` (units from `SystemServices::CATALOG`), `disks.format|mount|unmount`
plus fstab entries (keep the PR #13 safety rules: `nofail`, the OS-disk guard, no automatic
deletion), `network.set_hostname`, `dnsmasq.write_config|restart`, `tunnel.*` (token file, unit),
`tailscale.*`, `greyhole.*` (config, service, install), `packages.install` (a fixed list of
package names), `system.reboot|poweroff`. Then sudoers is down to the helper, the updater and
Docker for PR N.

## Decisions for Troy

1. **Web admins are added to the Linux `sudo` group** (`Platform.make_admin`). Their Linux
   passwords are locked, so it grants nothing today, but it ties web admin to OS admin.
   Recommendation: drop it.
2. **Shell access for web users.** Accounts get `/bin/sh`, and the per-user SSH key setting writes
   `authorized_keys`, so a user with a key can SSH in. Recommendation: `/usr/sbin/nologin` for app
   users and remove the SSH key setting (Troy uses his own `troy` account for SSH). Alternative:
   keep the setting for admins only.
3. **Language.** Recommendation: Ruby standard library only (same language and test suite as the
   app; Ubuntu's `ruby3.2` is already installed). Alternative: Rust, shared with bitShare later, at
   the cost of a build step on the NAS.
4. **"Reset permissions" on a share** runs `chmod -R a+rwx`, making every file world-writable.
   Recommendation: restore the normal share permissions (`amahi:users`, group-writable dirs
   `2775`, files `664`).
