# TECH_DEBT.md — Known Legacy Code & Future Cleanup

*Updated: 2026-02-26. Review periodically — tackle items when touching nearby code.*

---

## High Priority (will bite you)

### Share Model Callbacks
`app/models/share.rb` — `before_save_hook`, `after_save_hook`, `before_destroy_hook` do everything: write samba config, push to disk, update user permissions, reload services. One monolithic cascade that's hard to test and hard to debug. The factory stubs all of them out, which means specs never test the real save path.

**Fix:** Extract into a `ShareProvisioner` service object. Test the service directly.

### Command Class Inconsistency
`lib/command.rb` wraps shell execution with sudo. But newer code (SSE streaming controllers, setup wizard) calls `system("sudo ...")` directly. Two patterns for the same thing = confusion about which is "right."

**Fix:** Pick one. Either always use `Command`, or deprecate it and use `system()` with Shellwords everywhere. The SSE streaming pattern doesn't work well with Command since it needs line-by-line output.

---

## Medium Priority (messy but working)

### Tab/Subtab System
6 `config/initializers/*_tab.rb` files register nav items into a Tab model. Header iterates over them. Works fine but unnecessary indirection — the nav is static, never changes at runtime. Could replace with hardcoded links in the header partial.

**Files:** `app/models/tab.rb`, `app/models/subtab.rb`, `config/initializers/*_tab.rb`, `app/helpers/tabs_helper.rb`

### Three Layouts
`application.html.slim`, `basic.html.slim`, `debug.html.slim` — basic is used by pages that don't need tabs. Dashboard already uses application with `@no_tabs = true`. Could consolidate to one layout.

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
Several places use `HDA_TMP_DIR` / `/var/hda/` for staging samba/dns configs. Legacy Amahi convention. Works but not obvious. Could migrate to `/var/lib/amahi-kai/` for clarity.

### use_sample_data? Dev Mode
`settings_controller.rb` has a dev mode that loads fake server data from JSON files. Probably unused now that we have real installs. Harmless but confusing if you stumble into it.

### Server Model
`app/models/server.rb` — monit-style service monitoring from old Amahi. Works but overlaps with dashboard's `systemctl` status checks. Two systems doing similar things.

---

## Not Debt (intentional decisions)

- **Sprockets over Propshaft** — blocked by Bootstrap gem dependency. Not urgent.
- **Sleep calls in SSE streams** — intentional pacing for streaming output. Not waste.
- **Sleep in login failure** — timing attack prevention. Keep it.
- **`after_commit` for push_shares** — moved out of transaction intentionally to prevent rollback issues.
