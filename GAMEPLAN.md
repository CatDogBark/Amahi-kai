# Amahi-kai Modernization Gameplan

## Current State
- Ruby 2.7.8, Rails 5.2.8.1, MariaDB 10.5, Debian 11 sandbox
- App boots and serves pages ✅
- DB migrates and seeds (with workaround) ✅
- Tests: RSpec (models + features) + Minitest (functional) — NOT yet running
- Binstubs are stale (Bundler-generated, need Rails regeneration)

---

## Phase 1: Stabilize & Clean Up (no version upgrades)
*Goal: Get a solid, testable, warning-free baseline on current versions*

### 1.1 Fix binstubs
- [ ] Regenerate `bin/rails`, `bin/rake`, `bin/setup` etc.
- [ ] Remove Bundler binstub warnings

### 1.2 Fix db/seeds.rb
- [ ] Update for authlogic 6.5 (no more `password_confirmation` virtual attr)
- [ ] Make seeding idempotent

### 1.3 Fix Platform constant warnings
- [ ] `Platform::SERVICES` and `Platform::FILENAMES` double-load
- [ ] Platform detection fails on Debian 11 (`/etc/issue` says "Debian" but code expects it in PLATFORMS)
- [ ] Need to verify platform detection works correctly

### 1.4 Get tests running
- [ ] Replace `poltergeist` with `cuprite` or `selenium-webdriver` in spec_helper
- [ ] Fix spec_helper.rb to not require poltergeist
- [ ] Run `bundle exec rspec spec/models/` — fix failures
- [ ] Run `bundle exec rspec spec/features/` — fix failures  
- [ ] Run `bundle exec rake test` (minitest functional) — fix failures
- **🔧 TOOL NEEDED:** `chromium` + `chromedriver` in sandbox image for feature specs

### 1.5 Clean up Gemfile & dependencies
- [ ] Remove commented-out gems (poltergeist, mini_racer, rails_best_practices)
- [ ] Remove Fedora workaround comments
- [ ] Remove `mini_portile2` explicit dep (nokogiri handles it)
- [ ] Remove `psych` explicit dep (Fedora 19 workaround, not needed)
- [ ] Audit for unused gems

### 1.6 Remove yettings_monkey_patch.rb
- [ ] Not needed on Ruby 2.7, only was for 3.1+
- [ ] Remove from config/application.rb require

---

## Phase 2: Modernize the Codebase (still Rails 5.2)
*Goal: Clean up code, fix deprecations, prepare for Rails 6*

### 2.1 Update Dockerfile
- [ ] Replace Fedora 29 base with Ubuntu 24.04 or Debian 12
- [ ] Update for current gem/ruby versions
- [ ] docker-compose.yml update for MariaDB instead of MySQL

### 2.2 Fix deprecation warnings
- [ ] Run app and collect all Rails deprecation warnings
- [ ] Fix each one (prepares for Rails 6 upgrade)

### 2.3 Code quality
- [ ] Fix `Platform` class — make it a proper singleton, avoid constant redefinition
- [ ] Update `Command` class — consider making `hda-ctl` dependency optional for dev
- [ ] Fix authlogic crypto provider warning (migrate from Sha512 to SCrypt)
- [ ] Update `acts_as_authentic` config for authlogic 6.x API

### 2.4 Asset pipeline
- [ ] Verify all assets compile cleanly
- [ ] Fix any sprockets 4.x compatibility issues
- [ ] Ensure manifest.js is complete

---

## Phase 3: Rails Upgrade Path
*Goal: Step through Rails versions incrementally*

### 3.1 Rails 5.2 → 6.0
- [ ] Update Gemfile: `gem 'rails', '~> 6.0.0'`
- [ ] Run `rails app:update` — review each conflict
- [ ] Replace `update_attributes` with `update` where used
- [ ] Autoloading: prepare for Zeitwerk (default in 6.1)
- [ ] Fix any ActionMailer changes
- [ ] Run tests, fix failures
- **🔧 TOOL NEEDED:** Internet access OR pre-install Rails 6.0 gems in image

### 3.2 Rails 6.0 → 6.1
- [ ] Switch to Zeitwerk autoloader
- [ ] `form_with` defaults to local: false
- [ ] ActiveStorage changes (if used)
- [ ] Run tests, fix failures

### 3.3 Rails 6.1 → 7.0
- [ ] Ruby upgrade to 3.0+ required
- [ ] `secrets` → `credentials` migration
- [ ] `rails` command replaces `rake` for DB tasks
- [ ] Run tests, fix failures
- **🔧 TOOL NEEDED:** Ruby 3.0+ in sandbox image

### 3.4 Rails 7.0 → 7.1 → 7.2 (stretch goal)
- [ ] Ruby 3.1+ required
- [ ] Consider Hotwire/Turbo replacement for jQuery
- [ ] Consider importmap or jsbundling for assets

---

## Phase 4: Platform Modernization (stretch)
*Goal: Make Amahi work on modern Ubuntu/Debian natively*

### 4.1 Platform detection
- [ ] Support Ubuntu 22.04/24.04 properly
- [ ] Support Debian 11/12
- [ ] Modernize service management (full systemd, drop upstart/init.d)

### 4.2 Replace deprecated dependencies
- [ ] `yettings` → Rails credentials or custom YAML config
- [ ] `coffee-rails` → plain JS or ES6
- [ ] `uglifier` → terser
- [ ] `bootstrap 4` → bootstrap 5
- [ ] `jquery-rails` → Stimulus/Turbo (with Rails 7)

### 4.3 Security
- [ ] Authlogic → Devise (or keep authlogic but fully modernize)
- [ ] CSRF/session hardening
- [ ] Content Security Policy headers

---

## Tools Needed from Troy (by phase)

| Phase | Tool | Why |
|-------|------|-----|
| 1.4 | `chromium` + `chromedriver` | Feature/integration tests |
| 3.1 | Rails 6.0 gems pre-installed | Air-gapped sandbox |
| 3.3 | Ruby 3.0+ image variant | Rails 7 requires it |

---

## Priority Order
1. **Phase 1** — this is where I should focus now
2. **Phase 2** — once tests pass
3. **Phase 3** — once code is clean
4. **Phase 4** — long-term vision

*Last updated: 2026-02-14*
