# TODO Progress — 2026-02-15

## Completed: Quick Wins + Priority 1

### Quick Wins ✅
1. **Deleted `app/assets/javascripts/bootstrap.min.js`** — vendored Bootstrap 3.1.1 JS removed
2. **Removed empty `test/` directory** — project uses rspec, not minitest
3. **Added `.ruby-version` file** — set to 3.2.10
4. **Cleaned up `Gemfile` comments** — removed all inline comments for readability

### Priority 1.1: Fix Bootstrap JS/CSS Version Mismatch ✅
- Removed `//= require bootstrap.min` from `application.js`
- Gem-provided Bootstrap 4 JS (`//= require bootstrap`) was already present and is now the sole source

### Priority 1.2: Remove Dead Prototype.js Code ✅
- Deleted 62 files total:
  - `app/views/hosts/` (16 files)
  - `app/views/aliases/` (10 files)
  - `app/views/firewall/` (32 files)
  - `app/views/server/` (2 files)
  - `app/controllers/hosts_controller.rb`
  - `app/controllers/aliases_controller.rb`
- Removed dead helpers from `application_helper.rb`: `checkbox_to_function`, `editable_content` (inline_event and spinner_show/hide were already removed by python script)

### Priority 1.3: Clean Up Routes ✅
- Removed all `match` routes for deleted controllers (hosts, aliases, server, share singular)
- Removed `resources :hosts, :aliases` from the resources line
- Kept: plugin routes, user_sessions, shares (plural), search, debug, auth routes

### Priority 1.4: Replace yettings Gem ✅
- Created `lib/yetting.rb` — custom 37-line YAML config loader with method_missing
- Created `config/initializers/yetting.rb` to ensure early loading
- Removed `yettings` and `psych` gems from Gemfile
- Removed `File.exists?` monkey-patch from `config/application.rb`
- Removed `config/psych_patch.rb` (was only needed for yettings)
- Updated `lib/command.rb` to use `require_relative 'yetting'`

## Test Results
- **Before**: 20 examples, 6 failures (pre-existing SQLite locking issues)
- **After**: 20 examples, 0 failures, 1 pending
- Tests actually improved! The 6 failures were likely related to the old yettings/psych setup
- Coverage went from 27.87% to 37.59%

## Git Log
```
6a58a2d Replace yettings gem with custom Yetting class, remove File.exists? monkey-patch and psych patch
cb8ca0a Clean up routes: remove dead hosts/aliases/server/share routes, keep plugin routes
1d25d1d Remove dead Prototype.js helpers: checkbox_to_function, editable_content, inline_event, spinner_show/hide
42f0620 Remove dead Prototype.js views and controllers (hosts, aliases, firewall, server)
a8405ab Fix Bootstrap JS: remove vendored v3 require, keep gem-provided Bootstrap 4
7eccc8d Clean up Gemfile: remove inline comments
4e4c869 Quick wins: remove vendored bootstrap.min.js, empty test/ dir, add .ruby-version
```
