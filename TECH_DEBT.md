# TECH_DEBT.md — Known Technical Debt

*Updated: 2026-02-27. Review periodically — tackle items when touching nearby code.*

---

## High Priority

### Fat Controllers
Several controllers exceed 300 lines with mixed responsibilities:
- `network_controller.rb` (660 lines) — DHCP, DNS, gateway, security, remote access, Cloudflare, 5 SSE streams
- `apps_controller.rb` (459 lines) — Docker engine management + app CRUD + 2 SSE streams
- `disks_controller.rb` (310 lines) — Disk management + Greyhole install streaming
- `setup_controller.rb` (336 lines) — 7-step wizard with inline logic
- `shares_controller.rb` (310 lines) — Share CRUD + file operations

**Fix:** Split NetworkController (→ SecurityController, RemoteAccessController, etc.), extract Docker engine to its own controller, use service objects for business logic.

### SSE Streaming Duplication
10 streaming endpoints across 5 controllers, all copy-pasting the same boilerplate (headers, Enumerator, sse_send lambda, dev simulation, error handling). ~300 lines of duplication.

**Fix:** Extract `StreamingConcern` with `stream_sse { |send| ... }` helper. **IN PROGRESS**

### Shell.run in Controllers
30 `Shell.run` / `Shell.capture` calls directly in controllers. Business logic should be in service objects or models.

**Fix:** Extract to service objects as controllers are refactored.

### Bare Rescues
29 `rescue => e` catching everything in app/, 11 in lib/. Should be narrowed to specific exceptions.

---

## Medium Priority

### Share Model (420 lines)
Does too much: Samba config, Greyhole config, system commands, validation. Service objects exist (ShareFileSystem, SambaService, ShareAccessManager) but model still has direct logic.

### Inline JS in Views
8 `<script>` blocks in views (Docker toggle, install terminal, onclick handlers). Should be Stimulus controllers.

### Mixed View Formats
Some views `.html.slim`, others `.html.erb`. Not a bug, just inconsistent. Pick one over time.

### Missing Model Validations
`cap_access`, `cap_writer`, `db`, `theme`, `user_session` have zero validations. Some are fine (join tables) but worth auditing.

### Platform Model Overlap
`Platform.reload` restarts services, but controllers also call `Shell.run("systemctl ...")` directly. Two paths to the same thing.

### Server Model Overlap
Monit-style service monitoring overlaps with dashboard's `systemctl` status checks.

---

## Low Priority

### Route Audit
137 routes — likely some dead ones. Audit for unused routes.

### JS → Stimulus Migration
8 plain JS files using global functions. Could be Stimulus controllers for better lifecycle.

### View Extraction
Several views over 150 lines that could use partials:
- `setup.html.erb` layout (330 lines)
- `remote_access.html.erb` (203 lines)
- `system_status.html.slim` (187 lines)

---

## Not Debt (intentional)

- **Sprockets over Propshaft** — blocked by Bootstrap gem dependency
- **Sleep in SSE streams** — intentional pacing for streaming output
- **Sleep in login failure** — timing attack prevention
- **`after_commit` for push_shares** — prevents rollback issues
