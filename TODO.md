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

### Test Coverage
- [x] 214 specs total (67 model, 88 request, 35 feature, 24 lib)
- [x] Coverage: ~45% → improving

### Frontend: jQuery UJS → Stimulus Migration
- [x] Turbo + Stimulus wired up with Sprockets (Phase 0)
- [x] 8 Stimulus controllers: toggle, delete, inline_edit, progress, server_action, locale, user, create_form
- [x] All 6 plugins converted: Disks, Settings, Users, Network, Shares, Apps
- [x] Removed: simple_remote_checkbox/text/select/radio helpers, SmartLinks, RemoteCheckbox, FormHelpers, Templates, jQuery templates
- [x] ~974 lines of dead jQuery UJS infrastructure deleted

---

## 🔴 Priority 1: Security & Stability

### 1.1 Command Injection Hardening
- **Problem:** `Command` class and model hooks build shell commands via string interpolation
  - `"useradd -m -g users -c \"#{self.name}\" #{pwd_option} \"#{self.login}\""`
  - User-controlled values (login, name, password) injected directly into shell strings
- **Impact:** Critical — any user with admin access could inject shell commands via crafted usernames/names
- **Fix:** Use `Open3.capture2e` with argument arrays, or at minimum `Shellwords.escape` all interpolated values
- **Scope:** `app/models/user.rb`, `app/models/server.rb`, `app/models/share.rb`, `lib/command.rb`
- **Risk:** Low — mechanical replacement, testable

### 1.2 Security Hardening
- [x] Add `Rack::Attack` for rate limiting (gem installed)
- [x] Configure Content Security Policy (CSP)
- [x] Replace ROT13 "encryption" for router passwords with real encryption (MessageEncryptor)
- [ ] Enable `config.force_ssl` in production
- [ ] Audit session/cookie security settings
- [ ] Review CSRF protection across AJAX endpoints

### 1.3 Stub Out Dead AmahiApi
- **Problem:** App calls `api.amahi.org` (dead service) via ActiveResource
- **Impact:** App marketplace page hangs/errors, potential startup delays
- **Fix:** Replace with local stub that returns empty results, log warnings
- **Scope:** `lib/amahi_api.rb`, `plugins/040-apps/`
- **Risk:** Low — just preventing calls to a dead server

---

## 🟡 Priority 2: Platform — Make It Actually Run

### 2.1 Systemd Integration (Replace hda-ctl)
- **Problem:** All service management goes through `hda-ctl` daemon (doesn't exist on Ubuntu)
- **Current:** `Command` class queues instructions, sends to hda-ctl via named pipe
- **Fix:** Replace with direct `systemctl` calls for start/stop/restart/enable/disable
- **Scope:** `lib/command.rb`, `app/models/server.rb`, `lib/platform.rb`
- **Risk:** Medium — core system management, needs careful testing on real hardware

### 2.2 Platform Detection Cleanup
- **Problem:** Platform class has dead code for Fedora, CentOS, Mac, Mint, Arch
- **Fix:** Keep only Debian/Ubuntu paths, add proper dpkg-based version detection
- **Scope:** `lib/platform.rb`
- **Risk:** Low

### 2.3 Docker Compose for Development
- **Goal:** `docker compose up` gives a working dev environment
- **Includes:** MariaDB, the Rails app, proper volume mounts
- **Risk:** Low

---

## 🟢 Priority 3: Frontend Modernization

### 3.1 jQuery UJS → Turbo + Stimulus ✅ COMPLETE
- All 6 plugins converted to Stimulus controllers
- jQuery still loaded (used for stretch-toggle, hover effects, search form)
- **Next:** Can remove jquery_ujs entirely once confirmed no remaining `data-remote` usage
- **Future:** Remove jQuery itself (replace remaining ~30 lines of vanilla jQuery with plain JS)

### 3.2 Sprockets → Propshaft
- **Blocked:** Bootstrap gem hard-depends on Sprockets
- **Requires:** Drop bootstrap gem, vendor CSS/JS, use dartsass-rails
- **Risk:** High — architectural change
- **Status:** Parked until Bootstrap gem dependency is resolved

---

## 🔵 Priority 4: Features & Future

### 4.1 Firewall Plugin
- **Need:** New plugin from scratch with nftables integration
- **Scope:** Large — new feature

### 4.2 App Marketplace
- **Need:** Decide on app distribution (Docker-based? Native packages?)
- **Blocked:** Needs decision on Amahi cloud integration

### 4.3 Storage/Disk Management
- **Need:** ZFS/Btrfs support, SMART monitoring, pool management
- **Scope:** Large — new features

### 4.4 Increase Test Coverage to 70%+
- **Current:** ~48% (248 specs: 101 model, 88 request, 35 feature, 24 lib)
- **Covered:** All controllers, all models (User, Share, Host, DnsAlias, Setting, Server, Plugin, App, Webapp), Command, Platform
- **Remaining:** More edge cases, integration scenarios

---

## 📋 Quick Wins (Do Anytime)

- [x] Add CI config (GitHub Actions)
- [x] Update NOTICE.md with current Rails 8 / Ruby 3.2 versions
- [ ] Consolidate duplicate locale keys across plugins

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
