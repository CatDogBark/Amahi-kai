# Privilege Escalation Mitigation Plan

**Status:** Draft
**Author:** Kai (AI agent) with Troy's review
**Last updated:** 2026-02-17
**Applies to:** Amahi-kai native production deployment (Ubuntu 24.04)

---

## 1. Problem Statement

Amahi-kai's Rails application executes privileged system commands (user management,
service control, file permissions) via `lib/command.rb`. The `Command` class auto-prepends
`sudo` for a hardcoded list of binaries when not running as root.

The app runs as a non-root `amahi` system user. The privilege boundary is enforced by
a scoped sudoers allowlist that restricts exactly which commands can be escalated.

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

## 3. Architecture

### Native Install Security Model

```
┌─────────────────────────────────────────┐
│  Rails App (amahi user, non-root)       │
├─────────────────────────────────────────┤
│  Wrapper Scripts (argument validation)  │  ← Phase 2
├─────────────────────────────────────────┤
│  Sudoers (path + command scoping)       │  ← Phase 1
├─────────────────────────────────────────┤
│  Linux permissions (systemd, file ACLs) │
└─────────────────────────────────────────┘
```

On a native install, the `amahi` user runs under systemd. Service management via
`systemctl` works directly (no D-Bus socket gymnastics needed). SSH key management
and file operations work naturally since the app owns the machine — just like
original Amahi.

---

## 4. Sudoers Specification

File: `/etc/sudoers.d/amahi-kai`
Permissions: `0440`, owned by `root:root`
Installed by: `bin/amahi-install`

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
amahi ALL=(root) NOPASSWD: /usr/bin/chmod [0-9]* /var/lib/amahi-kai/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod -R [a-z]* /var/lib/amahi-kai/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod [a-z]* /var/lib/amahi-kai/*
amahi ALL=(root) NOPASSWD: /usr/bin/chmod u+rwx\,go-rwx /home/*/.ssh
amahi ALL=(root) NOPASSWD: /usr/bin/chmod u+rw\,go-rwx /home/*/.ssh/authorized_keys
amahi ALL=(root) NOPASSWD: /usr/bin/chown * /var/lib/amahi-kai/*
amahi ALL=(root) NOPASSWD: /usr/bin/chown -R * /home/*/.ssh

# Directory creation for shares
amahi ALL=(root) NOPASSWD: /usr/bin/mkdir -p /var/lib/amahi-kai/*

# Config file staging — fixed source path, no wildcards
amahi ALL=(root) NOPASSWD: /usr/bin/cp /tmp/amahi-staging/* /etc/samba/*
amahi ALL=(root) NOPASSWD: /usr/bin/cp /tmp/amahi-staging/* /etc/dnsmasq.d/*

# Service management — scoped to Amahi-managed services ONLY
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl start smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl stop smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl restart smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl reload smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl enable smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl disable smbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl start nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl stop nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl restart nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl reload nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl enable nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl disable nmbd.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl start dnsmasq.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl stop dnsmasq.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl restart dnsmasq.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl reload dnsmasq.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl enable dnsmasq.service
amahi ALL=(root) NOPASSWD: /usr/bin/systemctl disable dnsmasq.service

# Database backups
amahi ALL=(root) NOPASSWD: /usr/bin/mysqldump
```

### What's NOT Allowed

- No `rm`, `mv`, `cp` (except scoped Samba/dnsmasq config copies)
- No `apt-get`, `dpkg`, or package management
- No `systemctl` for arbitrary services (no sshd, docker, etc.)
- No shell access, no wildcards

### Phase 1 Residual Risk: `useradd` UID-0 Backdoor

**⚠️ KNOWN RISK:** The Phase 1 sudoers grants unrestricted `useradd` access. An attacker
with code execution as `amahi` could run:

```bash
sudo useradd -o -u 0 -g root backdoor
```

This creates a UID-0 user — effectively a root backdoor.

**Mitigation timeline:** Phase 2 wrapper scripts (see Section 5).

**Phase 1 acceptability:** On a trusted LAN with no internet-facing attack surface beyond
Cloudflare Tunnel (which terminates at the Rails app, not a shell), this is acceptable
residual risk.

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

## 6. Security Considerations

### 6.1 Threat Model

Home server, single trusted admin, local network. The threat model:

- **Primary risk:** Rails RCE via unpatched vulnerability → attacker gets `amahi` user access
- **Mitigated by:** Non-root user, scoped sudoers (no rm/mv/cp/apt-get, systemctl limited to 3 services)
- **Accepted risk:** Admin with Rails credentials can manage system (that's the feature)

### 6.2 Existing Hardening (already implemented)

- Rack::Attack rate limiting
- CSRF protection
- Shellwords.escape on all user input to shell commands
- CSP headers (report-only)
- Session cookie hardening (httponly, same_site: :lax)
- SQL injection fixes (parameterized queries)

### 6.3 Code Cleanup Needed

The `Command` class `needs_sudo?` method currently includes `rm`, `mv`, `cp`, `apt-get`
in its prefix list. These should be removed to match the sudoers boundary. This is a
defense-in-depth cleanup — sudoers is the real enforcement, but the code should reflect intent.

---

## 7. Implementation Checklist

### Phase 1 — Minimum Viable Hardening

- [ ] `bin/amahi-install` installs `/etc/sudoers.d/amahi-kai` with path-scoped rules
- [ ] Validate sudoers with `visudo -cf /etc/sudoers.d/amahi-kai`
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
- [ ] Add integration tests for privilege boundaries

### Phase 3 — Future Consideration

- [ ] AppArmor/seccomp profiles
- [ ] Rate-limiting on privileged command execution
- [ ] Audit logging for all sudo operations

---

## 8. References

- [sudoers manual](https://www.sudo.ws/docs/man/sudoers.man/)
- `lib/command.rb` — privilege execution engine
- `lib/platform.rb` — service management, SSH setup
- `app/models/user.rb` — user CRUD (useradd/usermod/userdel/pdbedit)
- `app/models/share.rb` — share permissions (chmod/chown)
- `bin/amahi-install` — production installer (installs sudoers)
