# Amahi-kai Modernization Gameplan

## Current State
- Ruby 3.2.10, Rails 8.0.4, Bootstrap 5.3, MariaDB, Ubuntu 24.04
- 115+ specs (model, request, feature), all passing
- Security hardened (Rack::Attack, CSP, Shellwords, stubbed dead API)
- Direct systemd execution (no hda-ctl dependency)
- CI ready (GitHub Actions config)

---

## ✅ Phase 1: Stabilize & Clean Up — COMPLETE
- Gemfile cleaned, modern dependencies
- All specs passing (model + feature, JS + non-JS)
- poltergeist → selenium-webdriver + headless Chromium
- Factories updated for factory_bot 6.x

## ✅ Phase 2: Modernize the Codebase — COMPLETE
- Dockerfile & Infrastructure (Ubuntu 24.04, docker-compose)
- All deprecation fixes (update_attributes, File.exists?, URI.escape, render :text)
- CoffeeScript → JavaScript (12 files)
- SCrypt crypto with Sha512 transition
- Bootstrap 4 → 5 migration
- Dead Prototype.js code removed (62 files)
- Dead routes cleaned (~60 routes)
- yettings gem replaced
- uglifier → terser

## ✅ Phase 3: Rails Upgrade Ladder — COMPLETE
- Rails: 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0.4
- Ruby: 2.7.8 → 3.2.10

## ✅ Phase 4: Security & Infrastructure — COMPLETE
- Shellwords.escape on all shell commands
- Rack::Attack rate limiting
- Content Security Policy (report-only)
- Dead AmahiApi stubbed
- hda-ctl replaced with direct execution
- Platform cleanup (Ubuntu/Debian only)
- GitHub Actions CI config
- Docker Compose updated
- Sudoers config template

---

## Phase 5: Frontend Modernization (Next)
*Goal: Replace jQuery/UJS with modern Rails frontend*

### 5.1 jQuery UJS → Turbo + Stimulus
- 38 remote forms, 52 AJAX handlers across 7 JS files
- Gems installed: turbo-rails, stimulus-rails, importmap-rails
- Strategy: incremental, one plugin at a time
- **Prerequisite:** test coverage at 70%+

### 5.2 Sprockets + Bootstrap gem
- Staying on Sprockets (Bootstrap gem depends on it)
- Propshaft blocked until Bootstrap dependency resolved

---

## Phase 6: Features & Polish (Future)
- Firewall plugin (nftables)
- App marketplace redesign (Docker-based?)
- Storage management (ZFS/Btrfs, SMART)
- Branding decision (keep Amahi name?)
- Auth system decision (keep authlogic?)

---

## Commits
1. `ff3dc70` — Initial commit
2. `5f9a2c4` — Phase 1: Stabilize for Debian/Ubuntu
3. `0d074bf` — Authlogic 6.5 compat + feature spec cleanup
4. `986e79e` — Deprecation fixes
5. `b0fd64e` — Phase 2: Platform + Docker modernization
6. `4d01c18` — URI.escape fix
7. `337e38b` — Security + deprecation improvements
8. `1d5e203` — README rewrite
9. `762111c` — bin/dev-setup script
10. `4665437` — Makefile modernization
11. `b006175` — JS feature specs + all specs green
12. `a204c3d` — Rails 6.0 upgrade
13. `bef6113` — Rails 6.1 upgrade
14. `5cd2376` — Rails 7.0 upgrade
15. `1ba420b` — Ruby 3.2 upgrade
16. `82965fc` — Rails 7.1 upgrade
17. `fd4e174` — Rails 7.2 upgrade
18. `29a6ec6` — Rails 8.0 upgrade + TODO cleanup + quick wins
19. `9edba7e` — Bootstrap 4 → 5 + terser
20. `4fd3ae3` — Model specs + pin validation fix
21. `dc5f698` — Request specs + unsafe redirect fix
22. `87eb4e1` — TODO reprioritized
23. `b5992d8` — Shellwords.escape security hardening
24. `325079e` — Rack::Attack + CSP + AmahiApi stub
25. `e7bd9e3` — hda-ctl → direct command execution
26. `9d1d8ca` — Platform cleanup + CI + Docker + docs

*Last updated: 2026-02-16*
