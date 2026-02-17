# Docker Production Deployment — Architecture Spec

*Status: DRAFT — awaiting Troy's review before implementation.*
*Author: Kai | Date: 2026-02-17*

---

## Overview

Amahi-kai currently runs in Docker with `RAILS_ENV=development` and `dummy_mode: true`, which no-ops all system commands. This doc specifies how to make Docker the **real production deployment target** — where the container can manage users, shares, DNS, and services on the host system.

### Why Docker?

- **Isolation from host upgrades** — Ruby, Samba, and system package bumps don't break the app
- **Reproducible builds** — the image is the same everywhere
- **Easy rollback** — bad deploy? `docker compose pull && up -d` with the old image
- **Simplified install** — users need Docker + docker-compose, not a full Ruby/Rails dev env

---

## 1. System Interactions Inventory

Every system call Amahi-kai makes, categorized by what it touches:

### 1.1 User Management (`user.rb`, `platform.rb`)
| Action | Commands |
|--------|----------|
| Create user | `useradd -m -g users -c <name> -p <hash> <login>` |
| Modify user | `usermod -c <name> -p <hash> <login>`, `usermod -G users,sudo <login>` |
| Delete user | `userdel -r <login>` |
| Samba password | `pdbedit -d0 -t -a -u <login>` (stdin: password) |
| Remove from Samba | `pdbedit -d0 -x -u <login>` |
| SSH keys | Write to `/home/<user>/.ssh/authorized_keys`, `chown`, `chmod` |
| Read users | Parses `/etc/passwd` directly |

**Host paths touched:** `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/home/*`, Samba `passdb.tdb`

### 1.2 File Shares (`share.rb`)
| Action | Commands |
|--------|----------|
| Create share | `mkdir -p`, `chown`, `chmod g+w` on share path |
| Delete share | `rmdir` on share path |
| Update permissions | `chmod o+w`, `chmod o-w`, `chmod -R a+rwx` |
| Write Samba config | Generates `smb.conf` + `lmhosts`, copies to `/etc/samba/` |
| Reload Samba | (implicit — Samba reads config on next connection or via `smbcontrol`) |

**Host paths touched:** `/var/hda/files/*` (share data), `/etc/samba/smb.conf`, `/etc/samba/lmhosts`

### 1.3 DNS (`dns_alias.rb`)
| Action | Commands |
|--------|----------|
| Create/delete/update alias | `hda-ctl-hup` (legacy — sends HUP to dnsmasq) |

**Host paths touched:** dnsmasq config (if we rewrite this to generate config files instead)

### 1.4 Services (`server.rb`, `platform.rb`)
| Action | Commands |
|--------|----------|
| Start service | `systemctl start <service>.service` |
| Stop service | `systemctl stop <service>.service` |
| Enable/disable | `systemctl enable/disable <service>.service` |
| Restart monit | `systemctl restart monit.service` |
| Monit config | Write/remove files in `/etc/monit/conf.d/` |
| Reload service | `systemctl reload <service>` |

**Host paths touched:** `/etc/monit/conf.d/*`, `/etc/monit/monitrc`

### 1.5 Apps (`app.rb`)
| Action | Commands |
|--------|----------|
| Install/uninstall | Shell scripts via `Command` |
| Docker socket | `chmod 666 /var/run/docker.sock` |

**Host paths touched:** `/var/hda/apps/*`, `/var/hda/web-apps/*`, `/var/run/docker.sock`

### 1.6 Databases (`db.rb`)
| Action | Commands |
|--------|----------|
| Create DB + user | Direct SQL via ActiveRecord connection |
| Drop DB + user | Direct SQL via ActiveRecord connection |
| Backup | `mysqldump` via shell |

**Host paths touched:** `/var/hda/dbs/` (backup dir)

### 1.7 Search (`search_controller.rb`)
| Action | Commands |
|--------|----------|
| HDA search | `locate` command against filesystem |

**Host paths touched:** reads from share paths, writes to `tmp/cache/search/`

### 1.8 Other
| What | Path |
|------|------|
| Platform detection | Reads `/etc/issue` |
| DHCP leases | Reads `/var/lib/dnsmasq/dnsmasq.leases` |
| Disk info | Reads from system (fdisk, mount, df) — via Disks plugin |
| Network info | Reads from system interfaces — via Network plugin |

---

## 2. Proposed Architecture

### 2.1 Execution Model: Host Command Proxy

Rather than giving the container full root access to the host, we use a **command proxy** pattern:

```
┌─────────────────────┐     ┌──────────────────────┐
│   Docker Container  │     │       Host System     │
│                     │     │                       │
│  Rails App          │     │  amahi-host-agent     │
│    ↓                │     │    ↓                  │
│  Command class  ────┼─────┼──► Unix socket        │
│  (mode: :proxy)     │     │    ↓                  │
│                     │     │  Allowlisted commands │
│                     │     │  executed as root      │
└─────────────────────┘     └──────────────────────┘
```

**Why a proxy instead of direct bind mounts + capabilities?**

- **Least privilege** — container never has root, CAP_SYS_ADMIN, or access to /etc/shadow
- **Auditable** — every command goes through an allowlist on the host side
- **Containable** — if the Rails app is compromised, the attacker can only run allowlisted commands
- **Simpler Docker config** — no privileged mode, no complex capability sets

**The host agent** is a small daemon (bash script or Go binary) that:
1. Listens on a Unix socket mounted into the container
2. Receives command requests (JSON: `{"cmd": "useradd", "args": [...]}`)
3. Validates against an allowlist of permitted command patterns
4. Executes as root and returns exit code + stdout/stderr
5. Logs every command for audit

### 2.2 Alternative: Direct Execution (Simpler, Less Secure)

For users who want simplicity over security (home server context — single trusted admin):

```yaml
# docker-compose.prod-direct.yml
services:
  web:
    privileged: false
    cap_add:
      - DAC_OVERRIDE    # file permission operations
      - CHOWN           # chown on share dirs
      - FOWNER          # chmod on files we don't own
      - SETUID          # useradd/userdel need to set UIDs
      - SETGID          # usermod group operations
    volumes:
      - /etc/passwd:/etc/passwd
      - /etc/shadow:/etc/shadow
      - /etc/group:/etc/group
      - /etc/samba:/etc/samba
      - /etc/dnsmasq.d:/etc/dnsmasq.d
      - /etc/monit/conf.d:/etc/monit/conf.d
      - /home:/home
      - /var/hda:/var/hda
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/log/samba:/var/log/samba
```

**Problem:** This is basically giving the container root access to the host with extra steps. Any Rails RCE = full host compromise. Fine for a home server with a single admin, but not great practice.

### 2.3 Recommendation

**Phase 1 (now):** Direct execution model. Get it working, prove the concept.
**Phase 2 (later):** Host agent proxy for users who want better isolation.

Rationale: This is a home server, not a multi-tenant cloud. The admin running Docker already has root. Adding the proxy layer is good engineering but shouldn't block shipping.

---

## 3. Configuration Changes

### 3.1 `config/hda.yml` — Environment-Based Override

```yaml
defaults: &defaults
  dummy_mode: false

development:
  <<: *defaults
  dummy_mode: true    # safe for dev

test:
  <<: *defaults
  dummy_mode: true    # safe for test

production:
  <<: *defaults
  dummy_mode: false   # real commands
```

No change needed here — production already has `dummy_mode: false`. The key is switching `RAILS_ENV=production` in docker-compose.

However, we should also support an **env var override** so users can run production Rails with dummy mode for testing:

```ruby
# lib/yetting.rb or config/hda.yml loader
# ENV['AMAHI_DUMMY_MODE'] overrides config file
```

### 3.2 `docker-compose.yml` — Production Profile

```yaml
services:
  db:
    image: mariadb:10.11
    container_name: amahi_db
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/mysql
    environment:
      MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASSWORD:-amahi}"
      MARIADB_DATABASE: amahi_production
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  web:
    build: .
    container_name: amahi_web
    restart: unless-stopped
    ports:
      - "80:3000"       # or use reverse proxy
      - "443:3000"      # if terminating TLS in the container
    depends_on:
      db:
        condition: service_healthy
    environment:
      RAILS_ENV: production
      DATABASE_HOST: db
      DATABASE_NAME: amahi_production
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"    # MUST be set
      RAILS_ALLOWED_HOST: "${RAILS_ALLOWED_HOST:-}"
      AMAHI_DUMMY_MODE: "false"
    cap_add:
      - DAC_OVERRIDE
      - CHOWN
      - FOWNER
      - SETUID
      - SETGID
    volumes:
      # Host system management
      - /etc/passwd:/etc/passwd
      - /etc/shadow:/etc/shadow
      - /etc/group:/etc/group
      - /etc/gshadow:/etc/gshadow
      - /etc/samba:/etc/samba
      - /etc/monit/conf.d:/etc/monit/conf.d:rw
      - /var/log/samba:/var/log/samba
      # Data
      - /var/hda:/var/hda
      - /home:/home
      # Docker socket (for Docker app management)
      - /var/run/docker.sock:/var/run/docker.sock
      # Host systemctl access (read-only)
      - /run/systemd/system:/run/systemd/system:ro
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket
    stdin_open: true
    tty: true

volumes:
  db_data:
```

### 3.3 Dockerfile Changes for Production

```dockerfile
# Additional packages for production
RUN apt-get update && apt-get install -y --no-install-recommends \
  # ... existing packages ...
  samba-common-bin \   # pdbedit for Samba user management
  dbus \               # systemctl needs D-Bus to talk to host systemd
  sudo \               # Command class uses sudo for privileged ops
  && rm -rf /var/lib/apt/lists/*

# Run as non-root by default; sudo for privileged commands
RUN useradd -m -s /bin/bash amahi && \
    echo "amahi ALL=(ALL) NOPASSWD: /usr/sbin/useradd,/usr/sbin/usermod,/usr/sbin/userdel,/usr/bin/pdbedit,/bin/chmod,/bin/chown,/bin/mkdir,/bin/rmdir,/bin/cp,/bin/mv,/bin/rm,/usr/bin/systemctl" > /etc/sudoers.d/amahi

USER amahi
```

### 3.4 DNS Alias Fix

`dns_alias.rb` calls `system "hda-ctl-hup"` directly (bypasses `Command` class). This needs to be refactored to:

```ruby
def restart
  c = Command.new
  c.submit("systemctl reload dnsmasq")
  c.execute
end
```

Or, if we move to generating dnsmasq config files:

```ruby
def restart
  write_dnsmasq_config  # write /etc/dnsmasq.d/amahi-aliases.conf
  c = Command.new("systemctl reload dnsmasq")
  c.execute
end
```

### 3.5 systemctl from Inside Docker

Running `systemctl` inside a container to control **host** services requires the D-Bus socket:

```yaml
volumes:
  - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket
```

And the `dbus` package installed in the container. This lets `systemctl` send commands to the host's systemd over D-Bus.

**Important:** This only works for `systemctl start/stop/restart/reload/enable/disable` on host services. It does NOT give the container ability to install systemd units — those are bind-mounted paths.

---

## 4. Security Considerations

### 4.1 Threat Model

This is a **home server** managed by a **single trusted admin** on a **local network**. The threat model is:

- **Primary risk:** Rails RCE via unpatched vulnerability → attacker gets container access
- **Mitigated by:** Allowlisted sudo commands, no shell access to host, container user is non-root
- **Accepted risk:** Someone with Rails admin credentials can manage the system (that's the feature)

### 4.2 Hardening Measures

| Measure | Status |
|---------|--------|
| Container runs as non-root user | Proposed |
| Sudo limited to specific commands with NOPASSWD | Proposed |
| No `--privileged` flag | Proposed |
| Minimal Linux capabilities (no CAP_SYS_ADMIN) | Proposed |
| `/etc/shadow` bind-mount (needed for useradd) | Required but sensitive |
| Docker socket access (for Docker app management) | Required — inherently root-equivalent |
| Rack::Attack rate limiting | Already implemented |
| CSRF protection | Already implemented |
| Shellwords.escape on all user input | Already implemented |
| CSP headers | Already implemented (report-only) |
| Session cookie hardening | Already implemented |

### 4.3 Docker Socket Warning

Mounting `/var/run/docker.sock` is **effectively root access** to the host. Anyone who can hit the Docker API can create privileged containers, mount host filesystems, etc. This is an accepted trade-off for the Docker App System feature.

Mitigation options (future):
- Docker socket proxy (e.g., Tecnativa/docker-socket-proxy) that only allows specific API calls
- Run Docker App management as a separate sidecar with restricted socket access

### 4.4 `/etc/shadow` Access

Needed because `useradd` modifies `/etc/shadow`. The container can read password hashes. Mitigation:
- Container runs as non-root; only sudo'd `useradd`/`usermod`/`userdel` can touch it
- Future: host agent proxy eliminates this exposure entirely

---

## 5. Migration Path

### Step 1: Production Docker Compose (this spec)
- New `docker-compose.prod.yml` with bind mounts and capabilities
- Dockerfile adds `samba-common-bin`, `dbus`, `sudo`, sudoers config
- Switch `RAILS_ENV=production`, `dummy_mode: false`
- Fix `dns_alias.rb` to use `Command` class
- Add `AMAHI_DUMMY_MODE` env var override
- Generate `SECRET_KEY_BASE` and document it

### Step 2: Validate Core Features
- User create/modify/delete (Linux + Samba)
- Share create/delete with correct permissions on host filesystem
- Samba config generation and reload
- Service start/stop via systemctl
- Docker app install/uninstall

### Step 3: Production Hardening
- Non-root container user with sudoers allowlist
- Asset precompilation in Dockerfile (not at runtime)
- Log rotation
- Backup strategy for DB + share data
- Health check endpoint
- `config.force_ssl` with reverse proxy (Cloudflare Tunnel handles this)

### Step 4 (Future): Host Agent Proxy
- Small daemon on host listening on Unix socket
- Command allowlist with argument validation
- Audit logging
- Eliminates need for `/etc/shadow` mount and most capabilities

---

## 6. Open Questions for Troy

1. **Where are shares stored on the NAS?** Need to know the actual path to bind-mount (e.g., `/mnt/data`, `/srv/shares`, or keep `/var/hda/files`).

2. **Is Samba already running on the host?** If so, we write config and reload. If not, should the container run Samba itself?

3. **Is dnsmasq running on the host?** Same question — manage it from the container, or skip DNS management for now?

4. **Is monit installed?** The service monitoring uses monit config files. Could replace with systemd-native monitoring if monit isn't in the picture.

5. **Do you want the development and production compose files separate** (`docker-compose.yml` + `docker-compose.prod.yml`) or a single file with profiles?

6. **Secret key management** — Docker secrets, `.env` file, or just document that the user must set `SECRET_KEY_BASE`?

---

*Next step: Troy reviews this spec, answers open questions, then Kai implements.*
