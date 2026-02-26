# TECH_DEBT.md — Known Legacy Code & Future Cleanup

*Updated: 2026-02-26. Review periodically — tackle items when touching nearby code.*

---

## High Priority (will bite you)

### ~~Share Model Callbacks~~ ✅ EXTRACTED
Extracted into 3 service objects: `ShareFileSystem`, `SambaService`, `ShareAccessManager`. Model delegates via thin callbacks. Factory stubs inject null services. 3 new spec files. (`1245870`, 2026-02-26)

### Command Class Inconsistency
`lib/command.rb` wraps shell execution with sudo. But newer code (SSE streaming controllers, setup wizard) calls `system("sudo ...")` directly. Two patterns for the same thing = confusion about which is "right."

**Fix:** Pick one. Either always use `Command`, or deprecate it and use `system()` with Shellwords everywhere. The SSE streaming pattern doesn't work well with Command since it needs line-by-line output.

---

## Medium Priority (messy but working)

### ~~Tab/Subtab System~~ ✅ REPLACED
Replaced with inline nav structure in `_tabs.html.slim`. Tab model, 6 initializers, tabs_helper all deleted. 200 lines removed.

### ~~Three Layouts~~ ✅ CONSOLIDATED
`basic.html.slim` deleted. Search uses `application.html.slim` with `@no_tabs = true`. Remaining layouts (debug, setup, login) are genuinely different.

### Mixed View Formats
Some views are `.html.slim`, others `.html.erb`. Not a bug, just inconsistent. Consolidated plugin views kept their original format. Pick one and migrate over time.

### Platform Model
`app/models/platform.rb` — methods like `Platform.reload` that restart services. Some places use it, others call `systemctl` directly via Command. Leaky abstraction.

---

## Low Priority (dead code / cosmetic)

### ~~Plugin Model~~ ✅ DELETED
### ~~amahi_plugins.rb~~ ✅ DELETED
### ~~Plugin generator~~ ✅ DELETED
### ~~plugins/ directory~~ ✅ DELETED
All removed 2026-02-26 (474 lines). DB `plugins` table still exists but harmless.

### /var/hda/ Legacy Paths
Several places use `HDA_TMP_DIR` / `/var/hda/` for staging samba/dns configs. Legacy Amahi convention. Works but not obvious. Migrate to `/var/lib/amahi-kai/` on next fresh install.

### ~~use_sample_data?~~ ✅ DELETED
Removed along with SampleData class. Controllers now use real system data with rescue fallbacks for CI.

### Server Model
`app/models/server.rb` — monit-style service monitoring from old Amahi. Works but overlaps with dashboard's `systemctl` status checks. Two systems doing similar things.

---

## Not Debt (intentional decisions)

- **Sprockets over Propshaft** — blocked by Bootstrap gem dependency. Not urgent.
- **Sleep calls in SSE streams** — intentional pacing for streaming output. Not waste.
- **Sleep in login failure** — timing attack prevention. Keep it.
- **`after_commit` for push_shares** — moved out of transaction intentionally to prevent rollback issues.
