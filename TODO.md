# Amahi-kai Modernization TODO

*Prioritized by impact and risk. Updated 2026-02-16.*

---

## ✅ Completed

### Phase 1: Stabilize & Clean Up
- [x] Gemfile cleaned, modern dependencies
- [x] All specs passing (model + feature, JS + non-JS)
- [x] poltergeist → selenium-webdriver + headless Chromium

### Phase 2: Modernize the Codebase
- [x] Dockerfile & Infrastructure (Ubuntu 24.04, docker-compose)
- [x] Deprecation fixes (update_attributes, File.exists?, URI.escape, render :text)
- [x] CoffeeScript → JavaScript (12 files)
- [x] Security: SCrypt crypto with Sha512 transition
- [x] Bootstrap JS/CSS version mismatch fixed (P1.1)
- [x] Dead Prototype.js code removed — 62 files (P1.2)
- [x] Dead routes cleaned — ~60 routes (P1.3)
- [x] yettings gem replaced with custom loader (P1.4)
- [x] File.exists? monkey-patch removed (P3.2)
- [x] uglifier replaced with terser (P2.4)
- [x] Bootstrap 4 → 5 migration (P2.1)
- [x] Pin validation fix (errors[:base] << → errors.add)
- [x] Unsafe redirect fix (Google search, allow_other_host)

### Phase 3: Rails Upgrade Ladder
- [x] Rails 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0.4
- [x] Ruby 2.7.8 → 3.2.10

### Security Hardening
- [x] Shellwords.escape in user.rb, share.rb, platform.rb, app.rb
- [x] Rack::Attack rate limiting
- [x] Content Security Policy (CSP) in report-only mode
- [x] ROT13 → real encryption (AES-256-GCM via MessageEncryptor)
- [x] AmahiApi stubbed (raises instead of hanging on dead server)
- [x] hda-ctl replaced with direct Command execution (3 modes: dummy/direct/hdactl)
- [x] Platform detection cleanup (only Ubuntu/Debian remain)
- [x] Session cookies hardened (httponly, same_site: :lax)
- [x] CSRF tokens in all Stimulus fetch requests via shared csrfHeaders()
- [x] jquery_ujs fully removed from asset pipeline

### Frontend: jQuery UJS → Stimulus Migration ✅ COMPLETE
- [x] Turbo + Stimulus wired up with Sprockets (Phase 0)
- [x] 8 Stimulus controllers: toggle, delete, inline_edit, progress, server_action, locale, user, create_form
- [x] All 6 plugins converted: Disks, Settings, Users, Network, Shares, Apps
- [x] Removed all simple_remote_* helpers from application_helper.rb
- [x] Removed: SmartLinks, RemoteCheckbox, FormHelpers, Templates, jQuery templates
- [x] Removed: spinner.js, ajax-setup.js, core-ext.js, debug.js
- [x] Removed: remote-checkboxes.js, remote-radios.js, remote-selects.js, form-helper.js
- [x] Removed: jquery.ui.templates.js, smart-links.js, templates.js
- [x] ~1,200+ lines of dead jQuery/UJS infrastructure deleted total
- [x] JS codebase: ~742 lines total (from thousands)

### Test Coverage
- [x] 248 specs total (101 model, 88 request, 35 feature, 24 lib)
- [x] All models covered: User, Share, Host, DnsAlias, Setting, Server, Plugin, App, Webapp
- [x] All controllers covered: network, settings, apps, disks, shares, users, debug, front, search
- [x] Lib covered: Command (3 modes), Platform
- [x] Coverage: ~48%
- [x] Flaky test ordering bug FIXED (was caused by jQuery template references)

### Code Quality
- [x] CI config (GitHub Actions)
- [x] NOTICE.md updated with current stack info
- [x] Duplicate locale keys cleaned (6 intra-file dupes, hello_world boilerplate)
- [x] Shared csrfHeaders() helper (DRY across 8 Stimulus controllers)
- [x] Deprecated Kernel#open calls fixed (File.open, URI.open, IO.popen)
- [x] SampleData YAML crash fixed (servers.yml.gz safe_load compatibility)

---

## 🔴 Priority 1: Security & Stability

### 1.1 Remaining Security Items
- [ ] Enable `config.force_ssl` in production (needs HTTPS setup guidance)
- [ ] Audit remaining shell interpolation in install/uninstall scripts
- [ ] Review app install scripts for injection vectors (`install_bg`, `uninstall_bg`)

---

## 🟡 Priority 2: Platform — Make It Actually Run

### 2.1 Docker Compose for Development
- **Status:** Basic `docker-compose.yml` exists (MariaDB + Rails)
- **Remaining:** Test it end-to-end, add health checks, volume mounts for hot reload
- **Risk:** Low

---

## 🟢 Priority 3: Frontend — Remaining Cleanup

### 3.1 Remove jQuery Entirely ✅ COMPLETE
- All remaining jQuery converted to vanilla JS
- jquery3 + jquery-ui removed from asset manifest
- jquery-rails + jquery-ui-rails commented out in Gemfile
- Zero jQuery in the entire codebase

### 3.2 Sprockets → Propshaft
- **Blocked:** Bootstrap gem hard-depends on Sprockets
- **Requires:** Drop bootstrap gem, vendor CSS/JS, use dartsass-rails
- **Risk:** High — architectural change
- **Status:** Parked until Bootstrap gem dependency is resolved

---

## 🔵 Priority 4: Features & Future

### 4.1 Increase Test Coverage to 70%+
- **Current:** ~50% (301 specs: 101 model, 88 request, 35 feature, 77 lib)
- **Lib coverage:** Command, Platform, Yetting, TempCache, Leases, Tab, credential encryption
- **Remaining:** Edge cases, error paths, more integration scenarios

### 4.2 Firewall Plugin
- **Need:** New plugin from scratch with nftables integration
- **Scope:** Large — new feature

### 4.3 App Marketplace
- **Need:** Decide on app distribution (Docker-based? Native packages?)
- **Blocked:** Needs decision on Amahi cloud integration

### 4.4 Storage/Disk Management
- **Need:** ZFS/Btrfs support, SMART monitoring, pool management
- **Scope:** Large — new features

---

## Decision Points (Deferred)

1. **Amahi cloud integration** — Keep or remove? Affects AmahiApi, app marketplace
2. **Branding** — Keep "Amahi" name/logos or rebrand?
3. **Target audience** — Power users (CLI-friendly) or appliance-style (zero-config)?
4. **App system** — Docker-based apps? Snap? Native packages?
5. **Authentication** — Keep authlogic or migrate to Devise/Rodauth?

*Decisions deferred — not blocking current work.*

---

*Last updated: 2026-02-16*
