# Docker Production Deployment — Architecture Spec

*Status: FINAL DRAFT — awaiting Troy's approval before implementation.*
*Authors: Kai (app/Rails) + Claude Code (infrastructure) | Date: 2026-02-17*

---

## Overview

Amahi-kai currently runs in Docker with `RAILS_ENV=development` and `dummy_mode: true`, which no-ops all system commands. This doc specifies how to make Docker the **real production deployment target** — where the container can manage users, shares, and services on the host.

### Why Docker?

- **Isolation from host upgrades** — Ruby, Samba, and system package bumps don't break the app
- **Reproducible builds** — the image is the same everywhere
- **Easy rollback** — bad deploy? `docker compose pull && up -d` with the old image
- **Simplified install** — users need Docker + docker-compose, not a full Ruby/Rails dev env

### Design Decisions (agreed)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Samba | Host install, container manages config | SMB needs LAN broadcast/mDNS; containerizing adds complexity for no gain |
| dnsmasq | Host install, container manages config (Phase 2) | Same as Samba; needs new config generation code first |
| Command execution | Direct (bind mounts + sudoers) | Phase 1 simplicity; host agent proxy deferred to Phase 2 |
| Container user | Non-root `amahi` user with scoped sudoers | Least privilege within direct execution model |
| Config persistence | `/etc/amahi-kai/amahi.env` (outside repo) | Survives rebuilds, can't be accidentally committed |
| Install method | `bin/amahi-install` script (idempotent) | One command to go from blank Ubuntu to running system |

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

### 1.3 DNS (`dns_alias.rb`) — PHASE 2
| Action | Commands |
|--------|----------|
| Create/delete/update alias | Currently: `system "hda-ctl-hup"` (broken — bypasses Command class, binary doesn't exist) |

**Gap identified:** No code exists to generate dnsmasq config files. The old Amahi platform had a separate `hda-ctl` daemon that read aliases from the DB and wrote dnsmasq config. We need to write:
- `DnsAlias#write_dnsmasq_config` — generates `/etc/dnsmasq.d/amahi-aliases.conf`
- `DnsAlias#restart` — refactored to use `Command` class + `systemctl reload dnsmasq`

**Deferred to Phase 2** — not blocking core functionality (users, shares, Samba).

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

### 1.5 Docker Apps (`docker_app.rb`, `container_service.rb`)
| Action | Commands |
|--------|----------|
| Install/manage apps | Docker API via socket |

**Host paths touched:** `/var/run/docker.sock`

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

---

## 2. Architecture

### 2.1 Phase 1: Direct Execution (bind mounts + sudoers)

```
┌─────────────────────────────┐
│      Docker Container       │
│                             │
│  Rails App (user: amahi)    │
│    ↓                        │
│  Command class              │
│    ↓                        │
│  sudo (scoped sudoers)      │
│    ↓                        │
│  useradd / pdbedit / etc    │
│  (via bind-mounted paths)   │
└──────────┬──────────────────┘
           │ bind mounts
┌──────────▼──────────────────┐
│      Host System            │
│                             │
│  /etc/passwd, /etc/shadow   │
│  /etc/samba/                │
│  /var/hda/files/            │
│  /home/                     │
│  /var/run/docker.sock       │
│  /var/run/dbus/system_bus   │
└─────────────────────────────┘
```

### 2.2 Phase 2 (Future): Host Agent Proxy

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

Deferred — adds security but requires writing a new daemon. The `Command` class is already mode-switchable (`:dummy`, `:direct`, `:hdactl`) so adding `:proxy` is straightforward when needed.

---

## 3. Security Boundary: Sudoers Allowlist

This is the **real security enforcement.** The container runs as non-root user `amahi`. The sudoers file defines exactly what it can escalate to:

```sudoers
# /etc/sudoers.d/amahi — Amahi-kai production allowlist
# User management
amahi ALL=(root) NOPASSWD: /usr/sbin/useradd
amahi ALL=(root) NOPASSWD: /usr/sbin/usermod
amahi ALL=(root) NOPASSWD: /usr/sbin/userdel
amahi ALL=(root) NOPASSWD: /usr/bin/pdbedit

# File/share management (scoped to /var/hda)
amahi ALL=(root) NOPASSWD: /bin/mkdir -p /var/hda/*
amahi ALL=(root) NOPASSWD: /bin/rmdir /var/hda/*
amahi ALL=(root) NOPASSWD: /bin/chmod
amahi ALL=(root) NOPASSWD: /bin/chown

# Samba config (scoped to specific files)
amahi ALL=(root) NOPASSWD: /bin/cp * /etc/samba/smb.conf
amahi ALL=(root) NOPASSWD: /bin/cp * /etc/samba/lmhosts

# Service management (scoped to Amahi-managed services ONLY)
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
```

### What's NOT allowed

- No `rm`, `mv`, `cp` (except scoped Samba config copies)
- No `apt-get`, `dpkg`, or package management
- No `systemctl` for arbitrary services (no sshd, docker, etc.)
- No shell access, no wildcards

### Code cleanup needed

The `Command` class `needs_sudo?` method currently includes `rm`, `mv`, `cp`, `apt-get` in its prefix list. These should be removed to match the sudoers boundary. This is a defense-in-depth cleanup — sudoers is the real enforcement, but the code should reflect intent.

---

## 4. Configuration

### 4.1 Persistent Config: `/etc/amahi-kai/amahi.env`

Generated by the install script, **outside the repo**, sourced by docker-compose:

```bash
# /etc/amahi-kai/amahi.env
SECRET_KEY_BASE=<64-char hex generated at install>
DB_ROOT_PASSWORD=<generated>
RAILS_ENV=production
DATABASE_HOST=db
DATABASE_NAME=amahi_production
AMAHI_DUMMY_MODE=false
# Optional:
# RAILS_ALLOWED_HOST=nas.example.com
# AMAHI_SHARE_ROOT=/var/hda/files
```

### 4.2 `docker-compose.prod.yml`

```yaml
services:
  db:
    image: mariadb:10.11
    container_name: amahi_db
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/mysql
    env_file:
      - /etc/amahi-kai/amahi.env
    environment:
      MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASSWORD:-amahi}"
      MARIADB_DATABASE: "${DATABASE_NAME:-amahi_production}"
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
      - "80:3000"
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - /etc/amahi-kai/amahi.env
    cap_add:
      - DAC_OVERRIDE
      - CHOWN
      - FOWNER
      - SETUID
      - SETGID
    volumes:
      # Host user/group management
      - /etc/passwd:/etc/passwd
      - /etc/shadow:/etc/shadow
      - /etc/group:/etc/group
      - /etc/gshadow:/etc/gshadow
      - /home:/home

      # Samba config
      - /etc/samba:/etc/samba

      # Share data
      - /var/hda:/var/hda

      # Docker socket (for Docker App System)
      - /var/run/docker.sock:/var/run/docker.sock

      # Host systemctl access via D-Bus
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket

      # Samba logs
      - /var/log/samba:/var/log/samba
    stdin_open: true
    tty: true

volumes:
  db_data:
```

### 4.3 Dockerfile Changes

```dockerfile
# Additional packages for production
RUN apt-get update && apt-get install -y --no-install-recommends \
  # ... existing packages ...
  samba-common-bin \   # pdbedit for Samba user management
  dbus \               # systemctl needs D-Bus to talk to host systemd
  sudo \               # Scoped privilege escalation
  && rm -rf /var/lib/apt/lists/*

# Non-root user with scoped sudo
RUN useradd -m -s /bin/bash amahi
COPY docker/sudoers-amahi /etc/sudoers.d/amahi
RUN chmod 440 /etc/sudoers.d/amahi

USER amahi
```

### 4.4 `config/hda.yml` — Add Env Var Override

```ruby
# In lib/yetting.rb or wherever dummy_mode is read:
def self.dummy_mode
  if ENV['AMAHI_DUMMY_MODE'].present?
    ENV['AMAHI_DUMMY_MODE'] == 'true'
  else
    # Fall back to config file
    config['dummy_mode']
  end
end
```

This lets users run `RAILS_ENV=production` with `AMAHI_DUMMY_MODE=true` for testing the production stack without real system commands.

---

## 5. Install Script: `bin/amahi-install`

Idempotent. Run it once on a blank Ubuntu 24.04 server. Run it again, nothing breaks.

```bash
#!/bin/bash
# bin/amahi-install — Amahi-kai production installer
set -euo pipefail

CONFIG_DIR="/etc/amahi-kai"
ENV_FILE="$CONFIG_DIR/amahi.env"
SHARE_ROOT="/var/hda/files"

echo "==> Amahi-kai Production Installer"

# 1. Install Docker (if needed)
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# 2. Install docker-compose plugin (if needed)
if ! docker compose version &>/dev/null; then
  echo "==> Installing docker-compose plugin..."
  apt-get update && apt-get install -y docker-compose-plugin
fi

# 3. Install Samba (if needed)
if ! command -v smbd &>/dev/null; then
  echo "==> Installing Samba..."
  apt-get update && apt-get install -y samba samba-common-bin
  systemctl enable --now smbd nmbd
fi

# 4. Create directories
echo "==> Creating directories..."
mkdir -p "$SHARE_ROOT"
mkdir -p "$CONFIG_DIR"
mkdir -p /var/hda/dbs

# 5. Generate .env file (if not exists)
if [ ! -f "$ENV_FILE" ]; then
  echo "==> Generating configuration..."
  SECRET=$(openssl rand -hex 32)
  DB_PASS=$(openssl rand -hex 16)
  cat > "$ENV_FILE" <<EOF
SECRET_KEY_BASE=$SECRET
DB_ROOT_PASSWORD=$DB_PASS
RAILS_ENV=production
DATABASE_HOST=db
DATABASE_NAME=amahi_production
AMAHI_DUMMY_MODE=false
EOF
  chmod 600 "$ENV_FILE"
  echo "==> Config written to $ENV_FILE"
else
  echo "==> Config already exists at $ENV_FILE (skipping)"
fi

# 6. Build and start
echo "==> Starting Amahi-kai..."
docker compose -f docker-compose.prod.yml up -d --build

echo ""
echo "==> Amahi-kai is starting up!"
echo "    Visit: http://$(hostname -I | awk '{print $1}'):80"
echo "    Login: admin / secretpassword (CHANGE THIS)"
echo ""
echo "    Config: $ENV_FILE"
echo "    Shares: $SHARE_ROOT"
```

---

## 6. Security Considerations

### 6.1 Threat Model

Home server, single trusted admin, local network. The threat model:

- **Primary risk:** Rails RCE via unpatched vulnerability → attacker gets container access
- **Mitigated by:** Non-root user, scoped sudoers (no rm/mv/cp/apt-get, systemctl limited to 3 services)
- **Accepted risk:** Admin with Rails credentials can manage system (that's the feature)

### 6.2 Docker Socket Warning

Mounting `/var/run/docker.sock` is **effectively root access** to the host. Anyone who can create Docker containers can escape to the host. This is an accepted trade-off for the Docker App System.

Future mitigation: Docker socket proxy (e.g., Tecnativa/docker-socket-proxy) limiting API surface.

### 6.3 `/etc/shadow` Access

Required because `useradd`/`usermod` modify `/etc/shadow`. Container can read password hashes.
Mitigation: non-root user, only sudo'd user management commands can touch it.
Future: host agent proxy eliminates this exposure entirely.

### 6.4 Existing Hardening (already implemented)

- Rack::Attack rate limiting
- CSRF protection
- Shellwords.escape on all user input to shell commands
- CSP headers (report-only)
- Session cookie hardening (httponly, same_site: :lax)
- SQL injection fixes (parameterized queries)

---

## 7. Implementation Phases

### Phase 1: Production Docker (implement now)
- [ ] `docker-compose.prod.yml` with bind mounts, capabilities, env_file
- [ ] Dockerfile: add `samba-common-bin`, `dbus`, `sudo`, non-root user
- [ ] `docker/sudoers-amahi` — scoped allowlist (per Section 3)
- [ ] `AMAHI_DUMMY_MODE` env var override in yetting/hda.yml loader
- [ ] Fix `dns_alias.rb` — refactor `system "hda-ctl-hup"` to use `Command` class (no-op for now)
- [ ] Clean up `Command#needs_sudo?` — remove `rm`, `mv`, `cp`, `apt-get` from prefix list
- [ ] `bin/amahi-install` — idempotent installer script
- [ ] Asset precompilation in Dockerfile (not at runtime)
- [ ] Validate: user CRUD (Linux + Samba), share CRUD, Samba config generation, Docker apps

### Phase 2: DNS + Hardening (after core is proven)
- [ ] `DnsAlias#write_dnsmasq_config` — generate `/etc/dnsmasq.d/amahi-aliases.conf`
- [ ] dnsmasq install in `bin/amahi-install`
- [ ] Add dnsmasq service entries to sudoers
- [ ] Docker socket proxy for App System
- [ ] `config.force_ssl` with reverse proxy documentation
- [ ] Health check endpoint (`/healthz`)
- [ ] Log rotation strategy
- [ ] Backup documentation (DB + share data)

### Phase 3: Host Agent Proxy (future)
- [ ] Small daemon on host listening on Unix socket
- [ ] Command allowlist with argument validation
- [ ] Audit logging
- [ ] New `Command` execution mode: `:proxy`
- [ ] Eliminates need for `/etc/shadow` mount and most capabilities

---

## 8. What Persists Across Container Rebuilds

| What | Where | Type | Survives `docker compose down`? |
|------|-------|------|--------------------------------|
| Share files | `/var/hda/files/` | Host path | ✅ |
| Database | `db_data` volume | Docker volume | ✅ |
| Linux users | `/etc/passwd`, `/etc/shadow` | Host files | ✅ |
| Samba users | `/var/lib/samba/` | Host path | ✅ |
| Samba config | `/etc/samba/` | Host path | ✅ |
| App config | `/etc/amahi-kai/amahi.env` | Host file | ✅ |
| Rails code | Container image | Rebuilt on upgrade | N/A |
| Assets, gems | Container image | Rebuilt on upgrade | N/A |

---

## 9. Upgrade Flow

```bash
cd /path/to/amahi-kai
git pull
docker compose -f docker-compose.prod.yml up -d --build
# Entrypoint runs db:migrate automatically
# Done.
```

---

*Next step: Troy reviews and approves. Kai implements Phase 1.*
