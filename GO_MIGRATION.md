# Go Migration Analysis

*Created: 2026-02-27. Shelved for future consideration.*

---

## Current Stack

- Ruby 3.2.10, Rails 8.0.4, MariaDB, Sprockets
- 14 models, 14 controllers, 144 routes, 232 specs
- ~5,600 lines application code, ~4,100 lines views, ~2,400 lines JS/CSS
- 133 shell calls for system management
- 10 SSE streaming endpoints
- Memory footprint: ~300MB

## Why Consider Go

- **Memory:** 300MB → ~30MB (matters for Pi/low-RAM devices)
- **Single binary:** deploy with `scp`, no Ruby/Bundler/gems
- **ARM cross-compile:** `GOOS=linux GOARCH=arm64 go build` — trivial
- **System integration:** `os/exec` and native syscalls replace Shell.run
- **Startup:** 3 seconds → 50ms
- **SSE/concurrency:** goroutines are built for this

## What We'd Lose

- **ActiveRecord magic** — joins, callbacks, validations, scopes all become hand-written SQL
- **Database migrations** — raw SQL via golang-migrate/goose instead of Rails DSL
- **Rails conventions** — file structure, routing, naming all become our decisions
- **View helpers** — `link_to`, `form_with`, `time_ago_in_words`, etc. — rewrite or find libraries
- **26 locale files** — need i18n library and wiring (or drop multi-language)
- **232 specs** — rewrite as Go tests
- **Rapid prototyping** — Rails scaffolds faster for new features
- **Gem ecosystem** — smaller Go web ecosystem (but adequate)

## What Stays Unchanged

- All JavaScript (Stimulus controllers) — 1,562 lines
- All CSS/SCSS — 805 lines
- Domain knowledge (Samba config format, Greyhole, disk detection, etc.)
- MariaDB schema (same tables, same relationships)
- bin/amahi-install (bash, language-independent)

## Estimated Effort

| Phase | Sessions | Scope |
|-------|----------|-------|
| Scaffold + DB + Auth | 1 | Go project, MariaDB, session auth, login |
| Core models + CRUD | 1-2 | Users, shares, settings, DNS |
| Dashboard + file browser | 1 | Two biggest UI features |
| System management | 1 | Shell integration, services, setup wizard |
| Docker apps + extras | 1 | App catalog, proxy, Greyhole, Cloudflare |
| Polish + installer | 1 | bin/amahi-install updates, testing |
| **Total** | **6-8 sessions** | |

## Go Libraries (likely choices)

- **Router:** Chi or Echo
- **DB:** sqlx + golang-migrate
- **Templates:** html/template (stdlib) or Templ
- **Sessions:** gorilla/sessions or scs
- **Auth:** bcrypt (golang.org/x/crypto)
- **SSE:** net/http Flusher (stdlib)

## When It Makes Sense

- Targeting Raspberry Pi or sub-2GB RAM devices
- Distributing to many users (single binary install)
- Need real-time features (WebSocket file sync, live monitoring)
- Rails memory footprint becomes a bottleneck

## When It Doesn't

- Rapidly iterating on features (Rails is faster for prototyping)
- Current hardware is adequate (3.8GB+ RAM)
- Single deployment target (our VM)

## Compromise Option

Write a Go companion binary for the 133 system management calls. Keep Rails for the web UI. Gets native system integration without a full rewrite.

---

*Decision: Stay on Rails for now. Legacy code (the real problem) has been eliminated. Revisit if targeting ARM or broader distribution.*
