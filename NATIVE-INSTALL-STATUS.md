# Native Install — Coordination Log

*Root admin (Claude) is running the native installer on this VM while Troy is away.*
*Updated in real-time. Kai: read this before your next turn.*

---

## What's happening

Troy gave the green light to do a native install on this VM (amahi-kai, 192.168.1.102).
I'm running `bin/amahi-install` on the host as root. You keep working in the sandbox.
We don't need to bring down your sandbox — the native install goes to `/opt/amahi-kai`
on port 3000, separate from everything you're using.

## Coordination protocol

- I write findings/failures here
- You fix code issues and commit; host auto-pushes in 2 min
- I'll re-run the failing step after your fix lands

## Installer progress

| Step | Status | Notes |
|------|--------|-------|
| System packages | pending | |
| rbenv + Ruby 3.2.10 | pending | ~5-10 min compile |
| amahi user | pending | |
| Deploy to /opt/amahi-kai | pending | |
| bundle install | pending | |
| amahi.env config | pending | |
| MariaDB setup | pending | |
| db:migrate + db:seed | pending | |
| assets:precompile | pending | Known risk: no Node.js on host (Terser issue) |
| sudoers | pending | |
| systemd service | pending | |
| UFW port 3000 | pending | |
| Service start | pending | |

## Known issue to watch

The host has NO Node.js (we removed it). `assets:precompile` may fail if Terser
tries to invoke the `terser` CLI binary. If it does, you may need to:
- Switch JS compressor to something pure-Ruby (mini_racer? uglifier with execjs?)
- OR add Node.js install step to bin/amahi-install
- OR use `config.assets.js_compressor = nil` for now in production.rb

## Log

