# Amahi-kai Modernization Gameplan

## Current State
- Ruby 2.7.8, Rails 6.0.6.1, MariaDB 10.5, Debian 11 sandbox
- App boots and serves pages ✅
- DB migrates and seeds ✅
- **Full test suite: 43 examples, 0 failures, 1 pending** ✅
- JS feature specs running with headless Chromium ✅
- Assets compile cleanly ✅

---

## Phase 1: Stabilize & Clean Up ✅ COMPLETE
- [x] Gemfile cleaned, modern dependencies
- [x] Binstubs regenerated
- [x] db/seeds.rb fixed for authlogic 6.5
- [x] Platform detection works on Debian
- [x] All specs passing (model + feature, JS + non-JS)
- [x] poltergeist → selenium-webdriver + headless Chromium
- [x] Factories updated for factory_bot 6.x

---

## Phase 2: Modernize the Codebase (still Rails 5.2)
*Goal: Clean up code, fix deprecations, prepare for Rails 6*

### 2.1 Dockerfile & Infrastructure ✅
- [x] Ubuntu 24.04 base, MariaDB, docker-compose
- [x] systemd service commands everywhere
- [x] bin/dev-setup, Makefile, README rewritten

### 2.2 Deprecation Fixes ✅
- [x] `update_attributes` → `update`
- [x] `File.exists?` → `File.exist?`
- [x] `URI.escape` → `URI.encode_www_form_component`
- [x] `render :text` → `render plain:`
- [x] No deprecation warnings on boot

### 2.3 Security ✅
- [x] SCrypt crypto with Sha512 transition
- [x] Password validations (length ≥8, confirmation)

### 2.4 CoffeeScript → JavaScript ✅
- [x] Convert 12 .coffee files to plain .js
- [x] Remove `coffee-rails` gem dependency
- [x] Verify assets compile and all specs pass

### 2.5 Platform Cleanup
- [ ] Fix Debian samba service names (smbd/nmbd) ✅
- [ ] Remove dead platform support (Fedora, CentOS, Mac, Mint, Arch) — or just leave them
- [ ] `platform_versions` method: add Debian/Ubuntu dpkg-based version detection

### 2.6 Code Quality
- [ ] Clean up empty minitest stubs (test/functional/, test/unit/) — remove or convert to rspec
- [ ] Review `Command` class for Debian compatibility
- [ ] Audit unused routes and controllers

---

## Phase 3: Rails Upgrade Path
*Goal: Step through Rails versions incrementally*

### 3.1 Rails 5.2 → 6.0 ✅
- [x] Update Gemfile: `gem 'rails', '~> 6.0.0'`
- [x] Zeitwerk autoloader enabled (load_defaults 6.0)
- [x] Fixed UsersController#create JSON format handling
- [x] Added data-type: json to user form for jquery_ujs compat
- [x] Removed obsolete framework defaults initializers
- [x] All 43 tests passing, 0 failures

### 3.2 Rails 6.0 → 6.1
- [ ] Switch to Zeitwerk autoloader
- [ ] `form_with` defaults
- [ ] Run tests, fix failures

### 3.3 Rails 6.1 → 7.0
- [ ] Ruby 3.0+ required
- [ ] `secrets` → `credentials` migration
- [ ] Run tests, fix failures
- **🔧 NEED:** Ruby 3.0+ in sandbox image

### 3.4 Rails 7.0 → 7.1 → 7.2 (stretch goal)
- [ ] Ruby 3.1+ required
- [ ] Consider Hotwire/Turbo for jQuery replacement
- [ ] Consider importmap for assets

---

## Phase 4: Platform Modernization (stretch)
*Goal: Make Amahi work on modern Ubuntu/Debian natively*

### 4.1 Replace deprecated dependencies
- [ ] `yettings` → Rails credentials or custom YAML config
- [ ] `uglifier` → terser
- [ ] `bootstrap 4` → bootstrap 5
- [ ] `jquery-rails` → Stimulus/Turbo (with Rails 7)

### 4.2 Security hardening
- [ ] Authlogic → Devise (or keep authlogic fully modernized)
- [ ] CSRF/session hardening
- [ ] Content Security Policy headers

---

## Tools Needed from Troy (by phase)

| Phase | Tool | Why |
|-------|------|-----|
| 3.1 | Rails 6.0 gems pre-installed | Air-gapped sandbox |
| 3.3 | Ruby 3.0+ image variant | Rails 7 requires it |

---

## Commits So Far
1. `ff3dc70` — Initial commit
2. `5f9a2c4` — Phase 1: Stabilize for Debian/Ubuntu
3. `0d074bf` — Authlogic 6.5 compat + feature spec cleanup
4. `986e79e` — Deprecation fixes (update_attributes, File.exists?)
5. `b0fd64e` — Phase 2: Platform + Docker modernization
6. `4d01c18` — URI.escape fix
7. `337e38b` — Security + deprecation improvements
8. `1d5e203` — README rewrite
9. `762111c` — bin/dev-setup script
10. `4665437` — Makefile modernization
11. `b006175` — JS feature specs with headless Chromium + all specs green

*Last updated: 2026-02-14*
