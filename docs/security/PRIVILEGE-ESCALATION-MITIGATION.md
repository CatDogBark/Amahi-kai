# Privilege Escalation Mitigation Plan

**Status:** Draft  
**Author:** Kai (AI agent) with Troy's review  
**Last updated:** 2026-02-17  
**Applies to:** Amahi-kai Docker production deployment

---

## 1. Problem Statement

Amahi-kai's Rails application executes privileged system commands (user management,
service control, file permissions) via `lib/command.rb`. The `Command` class auto-prepends
`sudo` for a hardcoded list of binaries when not running as root.

In the current Docker setup, the container runs as a non-root `amahi` user (good), but
the privilege boundary is effectively **wide open** — the app can `sudo` to any command
matching its prefix list with no argument restrictions.

This document defines the hardening plan to constrain privilege escalation to the
minimum necessary for Amahi-kai to function.

---

## 2. Current Privilege Surface

### 2.1 Commands Requiring Root (via `Command.execute_direct`)

| Binary | Used By | Purpose |
|--------|---------|---------|
| `useradd` | `User#create_system_user` | Create Linux/Samba users |
| `usermod` | `User#update_system_user`, `Platform.make_admin` | Modify users, group membership |
| `userdel` | `User#destroy_system_user` | Remove users |
| `pdbedit` | `User` model | Samba password database |
| `systemctl` | `Platform` | Start/stop/reload services (smbd, nmbd, dnsmasq) |
| `chmod` | `Share` model, `Platform.setup_ssh` | File permissions on shares and `.ssh` |
| `chown` | `Share` model, `Platform.setup_ssh` | File ownership on shares and `.ssh` |
| `cp` | Share config staging | Copy config files to system paths |
| `mkdir` | Share creation | Create share directories |

### 2.2 What's NOT Needed

The `needs_sudo?` prefix list in `command.rb` also includes `apt-get`, `dpkg`, `rpm`,
`yum`, `pacman`, `rm`, `rmdir`, `mv` — none of these are used by the application.
They should **not** be granted sudo access.

---

## 3. Target Architecture

### 3.1 Principle of Least Privilege

Each privileged operation gets the narrowest possible scope:

- **Path-scoped:** `chmod`/`chown` restricted to `/var/hda/*` and `/home/*/.ssh/*`
- **Service-scoped:** `systemctl` restricted to specific service units via D-Bus + polkit
- **Argument-scoped:** `useradd`/`usermod` via wrapper scripts that block dangerous flags
- **No capabilities:** Container runs with zero `cap_add` entries
- **No debug TTY:** `stdin_open` and `tty` removed from production compose

### 3.2 Defense in Depth Layers

```
┌─────────────────────────────────────────┐
│  Rails App (amahi user, non-root)       │
├─────────────────────────────────────────┤
│  Wrapper Scripts (argument validation)  │  ← Phase 2
├─────────────────────────────────────────┤
│  Sudoers (path + command scoping)       │  ← Phase 1
├─────────────────────────────────────────┤
│  Polkit Policy (service allowlist)      │  ← Phase 1
├─────────────────────────────────────────┤
│  Container (no caps, no TTY, no root)   │  ← Phase 1
└─────────────────────────────────────────┘
```

---

## 4. Sudoers Specification

File: `/etc/sudoers.d/amahi-kai`  
Permissions: `0440`, owned by `root:root`

### Phase 1 — Scoped Sudoers

```sudoers
# Amahi-kai — least-privilege sudoers
# Phase 1: path-scoped commands, explicit allowlist

# User management (wrapper scripts in Phase 2)
amahi ALL=(root) NOPASSWD: /usr/sbin/useradd
amahi ALL=(root) NOPASSWD: /usr/sbin/usermod
amahi ALL=(root) NOPASSWD: /usr/sbin/userdel

# Samba password management
amahi ALL=(root) NOPASSWD: /usr/bin/pdbedit

# File operations — scoped to share and SSH paths only
amahi ALL=(root) NOPASSWD: /usr/bin/chmod [0-9]* /var/hda/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod -R [a-z]* /var/hda/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod [a-z]* /var/hda/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod u+rwx\,go-rwx /home/*/.ssh
amahi ALL=(root) NOPASSWD: /usr/bin/chmod u+rw\,go-rwx /home/*/.ssh/authorized_keys
amahi ALL=(root) NOPASSWD: /usr/bin/chown * /var/hda/*
amahi ALL=(root) NOPASSWD: /usr/bin/chown -R * /home/*/.ssh

# Directory creation for shares
amahi ALL=(root) NOPASSWD: /usr/bin/mkdir -p /var/hda/*

# Config file staging — fixed source path, no wildcards
amahi ALL=(root) NOPASSWD: /usr/bin/cp /tmp/amahi-staging/* /etc/samba/*
amahi ALL=(root) NOPASSWD: /usr/bin/cp /tmp/amahi-staging/* /etc/dnsmasq.d/*

# Explicit deny for everything else
Defaults:amahi !authenticate
```

### Phase 1 Residual Risk: `useradd` UID-0 Backdoor

**⚠️ KNOWN RISK:** The Phase 1 sudoers grants unrestricted `useradd` access. An attacker
with code execution as `amahi` could run:

```bash
sudo useradd -o -u 0 -g root backdoor
```

This creates a UID-0 user — effectively a root backdoor. Sudoers argument pattern matching
is not expressive enough to block `-o -u 0` combinations reliably.

**Mitigation timeline:** Phase 2 wrapper scripts (see Section 5).

**Phase 1 acceptability:** On a trusted LAN with no internet-facing attack surface beyond
Cloudflare Tunnel (which terminates at the Rails app, not a shell), this is acceptable
residual risk. Document and revisit.

---

## 5. Wrapper Scripts (Phase 2)

### 5.1 Safe `useradd` Wrapper

File: `/usr/local/sbin/amahi-useradd`  
Permissions: `0755`, owned by `root:root`

```bash
#!/bin/bash
# /usr/local/sbin/amahi-useradd — safe wrapper for useradd
# Blocks UID-0 / non-unique UID flags to prevent privilege escalation

if echo "$@" | grep -qE '(-o|--non-unique|-u\s*0)'; then
    echo "amahi-useradd: UID 0 / non-unique flags are not allowed" >&2
    exit 1
fi
exec /usr/sbin/useradd "$@"
```

### 5.2 Safe `usermod` Wrapper

File: `/usr/local/sbin/amahi-usermod`  
Permissions: `0755`, owned by `root:root`

```bash
#!/bin/bash
# /usr/local/sbin/amahi-usermod — safe wrapper for usermod
# Blocks UID-0 / non-unique UID flags

if echo "$@" | grep -qE '(-o|--non-unique|-u\s*0)'; then
    echo "amahi-usermod: UID 0 / non-unique flags are not allowed" >&2
    exit 1
fi
exec /usr/sbin/usermod "$@"
```

### 5.3 Phase 2 Sudoers Update

When wrappers are deployed, replace the direct grants:

```sudoers
# User management — via safe wrappers (blocks UID-0 escalation)
amahi ALL=(root) NOPASSWD: /usr/local/sbin/amahi-useradd
amahi ALL=(root) NOPASSWD: /usr/local/sbin/amahi-usermod
amahi ALL=(root) NOPASSWD: /usr/sbin/userdel
```

And update `Command` / `needs_sudo?` to use the wrapper paths.

---

## 6. D-Bus + Polkit for Service Management

### 6.1 Why Not Sudoers for systemctl?

`systemctl` via sudoers requires either blanket access (`systemctl *`) or individual
entries per verb per service. Polkit is the native, designed-for-this-purpose mechanism
on systemd hosts.

### 6.2 Polkit Policy

File: `/etc/polkit-1/rules.d/50-amahi-kai.rules`

```javascript
// Amahi-kai: allow the amahi user to manage specific services only
polkit.addRule(function(action, subject) {
    var allowedServices = ["smbd.service", "nmbd.service", "dnsmasq.service"];
    if (action.id.indexOf("org.freedesktop.systemd1.manage-units") === 0 &&
        subject.user === "amahi") {
        var unit = action.lookup("unit");
        if (unit && allowedServices.indexOf(unit) >= 0) {
            return polkit.Result.YES;
        }
        return polkit.Result.NO;  // explicit deny for other services
    }
});
```

### 6.3 Container Integration

The container needs access to the host's D-Bus system bus:

```yaml
volumes:
  - /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro
```

The `amahi` user inside the container must map to a consistent UID on the host for
polkit to recognize it. Since `/etc/passwd` is bind-mounted from the host, the UID
should be consistent — but **verify this during Phase 1 validation**:

```bash
# Inside container:
id amahi
# On host:
id amahi
# UIDs must match
```

With this in place, `systemctl` commands issued inside the container communicate over
D-Bus to the host's systemd, and polkit enforces the service allowlist. No sudo needed
for service management.

### 6.4 Shadow File Access

The Rails app reads `/etc/shadow` for password verification. In the container:

- Bind-mount `/etc/shadow` read-only: `-v /etc/shadow:/etc/shadow:ro`
- The `amahi` user must be in the `shadow` group to read it
- **No write access.** Password changes go through `usermod`/`pdbedit` via sudo.

This is standard practice for PAM-aware applications. The read-only mount prevents
any shadow file modification even if the app is compromised.

---

## 7. Docker Compose Production Changes

### 7.1 Remove Debug Settings

Remove from `docker-compose.prod.yml`:

```yaml
# REMOVE these — development/debug only
stdin_open: true   # no interactive stdin in production
tty: true          # changes signal handling, not needed
```

`tty: true` causes PID 1 to receive signals differently (SIGHUP handling changes) and
`stdin_open` keeps an unnecessary file descriptor open. Neither serves a purpose in
production.

### 7.2 Remove All Capabilities

```yaml
services:
  web:
    cap_drop:
      - ALL
    # NO cap_add entries — everything goes through sudo/polkit
```

### 7.3 Production Compose Additions

```yaml
services:
  web:
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    read_only: true  # optional, requires tmpfs for tmp/log/pid dirs
    tmpfs:
      - /tmp
      - /amahi/tmp
      - /amahi/log
    volumes:
      - /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro
      - /etc/passwd:/etc/passwd:ro
      - /etc/shadow:/etc/shadow:ro
      - share_data:/var/hda/files
```

---

## 8. Implementation Checklist

### Phase 1 — Minimum Viable Hardening

- [ ] Create `/etc/sudoers.d/amahi-kai` with path-scoped rules (Section 4)
- [ ] Validate sudoers with `visudo -cf /etc/sudoers.d/amahi-kai`
- [ ] Create `/etc/polkit-1/rules.d/50-amahi-kai.rules` (Section 6.2)
- [ ] Verify `amahi` UID consistency between container and host
- [ ] Test polkit: `systemctl restart smbd.service` works as `amahi`
- [ ] Test polkit: `systemctl restart sshd.service` is **denied** as `amahi`
- [ ] Remove `stdin_open: true` and `tty: true` from production compose
- [ ] Remove all `cap_add` entries from production compose
- [ ] Add `cap_drop: [ALL]` and `no-new-privileges:true`
- [ ] Bind-mount D-Bus socket, `/etc/passwd`, `/etc/shadow` (read-only)
- [ ] Add `amahi` user to `shadow` group for read access
- [ ] Update `Command#needs_sudo?` to remove unused prefixes (`apt-get`, `rm`, etc.)
- [ ] Document residual `useradd` UID-0 risk in operational notes
- [ ] Smoke test: create user, create share, start/stop service, verify all work

### Phase 2 — Full Hardening

- [ ] Create `/usr/local/sbin/amahi-useradd` wrapper script (Section 5.1)
- [ ] Create `/usr/local/sbin/amahi-usermod` wrapper script (Section 5.2)
- [ ] Update sudoers to use wrapper paths instead of direct binaries
- [ ] Update `Command` class to invoke wrappers
- [ ] Test wrapper: `amahi-useradd -o -u 0 backdoor` is **rejected**
- [ ] Test wrapper: `amahi-useradd -m -g users -c "Test" testuser` **works**
- [ ] Consider `read_only: true` filesystem with tmpfs mounts
- [ ] Audit `SystemUtils.run` and `SystemUtils.run_script` for privilege concerns
- [ ] Add integration tests for privilege boundaries

### Phase 3 — Future Consideration

- [ ] AppArmor/seccomp profiles for the container
- [ ] Migrate from sudo to a dedicated privilege broker daemon
- [ ] Rate-limiting on privileged command execution
- [ ] Audit logging for all sudo/polkit operations

---

## 9. References

- [Polkit JavaScript rules (freedesktop.org)](https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html)
- [Docker security best practices](https://docs.docker.com/engine/security/)
- [sudoers manual](https://www.sudo.ws/docs/man/sudoers.man/)
- `lib/command.rb` — privilege execution engine
- `lib/platform.rb` — service management, SSH setup
- `app/models/user.rb` — user CRUD (useradd/usermod/userdel/pdbedit)
- `app/models/share.rb` — share permissions (chmod/chown)
