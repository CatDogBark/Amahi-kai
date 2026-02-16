# Amahi-kai Modernization TODO

*Post-dependency-upgrade work. Prioritized by impact and risk.*

---

## 🔴 Priority 1: Breaking Issues & Cleanup

### 1.1 Fix Bootstrap JS/CSS Version Mismatch
- **Problem:** Gem provides Bootstrap **4.1.1** CSS via sass, but `app/assets/javascripts/bootstrap.min.js` is Bootstrap **3.1.1**
- **Impact:** JS components (modals, dropdowns, tooltips) may behave unpredictably
- **Fix:** Remove vendored `bootstrap.min.js`, use gem-provided Bootstrap 4 JS
- **Risk:** Low — Bootstrap 4 JS is mostly backward-compatible for what we use

### 1.2 Remove Dead Prototype.js Code
- **Problem:** 30 view files + 2 controllers reference undefined helpers (`update_page`, `link_to_remote`, `remote_function`) from the Prototype.js era (removed in Rails 4)
- **Files:**
  - `app/views/hosts/` (5 files) — replaced by `plugins/050-network/`
  - `app/views/aliases/` (5 files) — replaced by `plugins/050-network/`
  - `app/views/firewall/` (18 files) — no plugin replacement yet
  - `app/views/server/` (2 files) — replaced by `plugins/080-settings/`
  - `app/controllers/hosts_controller.rb` — replaced by network plugin
  - `app/controllers/aliases_controller.rb` — replaced by network plugin
- **Also:** Dead methods in `application_helper.rb`: `checkbox_to_remote`, `checkbox_to_function`, `editable_content`, `inline_event`, `spinner_show`, `spinner_hide`
- **Fix:** Delete dead files, remove dead helpers
- **Risk:** Low — these never execute, plugins provide replacements

### 1.3 Clean Up Routes
- **Problem:** 61 manual `match` routes duplicate what `resources` already provides, plus routes for dead controllers
- **Fix:** Remove routes for deleted controllers, consolidate duplicates
- **Risk:** Medium — need to verify plugin routes still work

### 1.4 Replace yettings Gem
- **Problem:** Abandoned gem (v0.1.1, ~2012), uses `File.exists?` (patched), wraps simple YAML config
- **Current:** Reads `config/yetting.yml`, creates `Yetting` class with methods for each key
- **Fix:** Replace with a simple custom YAML config loader (20 lines) or Rails credentials
- **Risk:** Low — straightforward replacement, used for app settings only

---

## 🟡 Priority 2: Frontend Modernization

### 2.1 Bootstrap 4 → 5
- **Why:** Bootstrap 4 EOL (Jan 2023), Bootstrap 5 drops jQuery dependency
- **Changes:** Class renames (`ml-` → `ms-`, `mr-` → `me-`), dropped jQuery plugins
- **Scope:** All views (main app + 6 plugins), theme stylesheets
- **Risk:** Medium — extensive but mechanical changes

### 2.2 jQuery UJS → Hotwire (Turbo + Stimulus)
- **Why:** `jquery_ujs` is unmaintained, Rails 7 standard is Turbo
- **Current:** Remote forms use `jquery_ujs` for AJAX, JS handlers for DOM updates
- **Scope:** Large — every `remote: true` form, every `ajax:success` handler
- **Alternative:** Keep jQuery + `rails-ujs` as intermediate step
- **Risk:** High — this is the biggest frontend change

### 2.3 Sprockets → Propshaft or Importmap
- **Why:** Sprockets is legacy, Propshaft is simpler, Importmap eliminates Node.js
- **Current:** Sprockets with `sass-rails`, `uglifier`
- **Scope:** Asset pipeline config, manifest files
- **Risk:** Medium — need to migrate all asset references

### 2.4 Replace uglifier
- **Why:** Requires Node.js/ExecJS runtime
- **Options:** `terser` (still needs Node), or just skip minification (CDN/reverse proxy can handle it)
- **Fix:** `config.assets.js_compressor = :terser` or remove entirely
- **Risk:** Low

---

## 🟢 Priority 3: Backend & Code Quality

### 3.1 Increase Test Coverage (34% → 70%+)
- **Untested controllers:** debug, search, server, share, front, user_sessions, application
- **Untested models:** Most model edge cases
- **Plugin controllers:** Only basic CRUD tested
- **Goal:** Cover all controller actions, model validations, edge cases

### 3.2 Replace File.exists? Monkey-Patch
- **Current:** Global `File.exists?` alias in `application.rb` for yettings gem
- **Fix:** Remove after replacing yettings (1.4 above)

### 3.3 Security Hardening
- [ ] Enable `config.force_ssl` in production
- [ ] Configure Content Security Policy (CSP) — template exists but commented out
- [ ] Add `Rack::Attack` for rate limiting
- [ ] Audit session/cookie security settings
- [ ] Review CSRF protection across AJAX endpoints

### 3.4 Replace ActiveResource / AmahiApi
- **Current:** `lib/amahi_api.rb` uses ActiveResource to call `api.amahi.org`
- **Decision:** Do we keep Amahi cloud integration or fork completely?
- **If forking:** Replace with simple HTTP client or remove entirely
- **If keeping:** ActiveResource 6.1 works fine, just update API endpoints

### 3.5 Docker Compose for Development
- **Current:** Dockerfile + docker-compose exist but need updating for Ruby 3.2
- **Goal:** `docker compose up` gives you a working dev environment
- **Includes:** MariaDB, Redis (for caching), the Rails app

---

## 🔵 Priority 4: Platform Features

### 4.1 Firewall Plugin (Missing)
- **Problem:** Old firewall views exist but are dead Prototype.js code
- **Need:** New firewall plugin (like 050-network) with modern views
- **Scope:** New plugin from scratch, iptables/nftables integration

### 4.2 App Marketplace
- **Current:** `plugins/040-apps/` has framework for installing apps via AmahiApi
- **Need:** Decide on app distribution — keep Amahi's system? Build our own? Docker-based?
- **Scope:** Large — this is a product decision

### 4.3 Modern Service Management
- **Current:** Uses `Command` class to send instructions to `hda-ctl` daemon
- **Need:** Direct systemd integration, maybe DBus
- **Scope:** Replace `hda-ctl` dependency with native systemd calls

### 4.4 Storage/Disk Management
- **Current:** Basic disk listing and temperature monitoring
- **Need:** ZFS/Btrfs support, SMART monitoring, pool management
- **Scope:** Large — new features, not just modernization

---

## 📋 Quick Wins (Do Anytime)

- [ ] Delete `app/assets/javascripts/bootstrap.min.js` (vendored v3, conflicts with gem v4)
- [ ] Remove empty `test/` directory (using rspec, not minitest)
- [ ] Clean up `Gemfile` comments
- [ ] Add `.ruby-version` file (3.2.10)
- [ ] Add CI config (GitHub Actions)
- [ ] Update NOTICE.md with current Rails/Ruby versions
- [ ] Add `bin/setup` script for new developer onboarding
- [ ] Consolidate duplicate locale keys across plugins

---

## Decision Points (Need Troy's Input)

1. **Amahi cloud integration** — Keep or remove? Affects AmahiApi, app marketplace
2. **Branding** — Keep "Amahi" name/logos or rebrand? AGPL allows use but trademark is theirs
3. **Target audience** — Power users (CLI-friendly) or appliance-style (zero-config)?
4. **App system** — Docker-based apps? Snap? Native packages?
5. **Authentication** — Keep authlogic or migrate to Devise/Rodauth?

*Decisions 1, 2, and 5 deferred — not blocking current work. Will revisit later.*

---

*Last updated: 2026-02-15*
