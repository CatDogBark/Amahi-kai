# TODO Progress — Priority 2 & 3

**Date:** 2025-02-15

## Priority 2: Frontend Modernization

### 2.1 Bootstrap 4 → 5: ❌ NOT FEASIBLE
- Only Bootstrap 4.1.3 gem available in sandbox, no network to fetch 5.x
- **Action needed:** Run `bundle update bootstrap` with network after updating Gemfile

### 2.2 jQuery UJS → Hotwire: ⏭️ SKIPPED (needs Troy's decision)
### 2.3 Sprockets → Propshaft: ⏭️ SKIPPED (do with Rails 8.0)

### 2.4 Replace Uglifier: ✅ DONE
- Commented out js_compressor and uglifier gem. No terser available.
- Commit: 6f512c3

## Priority 3: Backend & Code Quality

### 3.1 Increase Test Coverage: ⏭️ SKIPPED
### 3.2 Replace File.exists?: ✅ ALREADY DONE (Priority 1.4)

### 3.3 Security Hardening: ✅ DONE
- force_ssl: present commented, added TODO note
- CSP template exists (commented, needs tuning per deployment)
- CSRF: properly configured with :exception
- Commit: 092aba3

### 3.4 Replace ActiveResource: ⏭️ SKIPPED (needs Troy's decision)

### 3.5 Docker: ✅ REVIEWED
- Already updated for Ubuntu 24.04 + Ruby 3.2. Added version note.
- Commit: 6a29442

## Test Status
- 20 examples, 6 failures (pre-existing SQLite locking, not from our changes)
