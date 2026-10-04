# Amahi-kai: notes for Claude sessions

Amahi-kai is a Rails 8.1 NAS web app, modernized from the 2013 Amahi platform. It is still in
development: the one install is Troy's NAS, an Ubuntu 24.04 VM on Proxmox, reached on the LAN by IP
over plain HTTP, through a Cloudflare Tunnel, and through Tailscale. Troy owns the repo
(`CatDogBark/Amahi-kai`, **public**) and the NAS.

Current work: Phase 3 of a code review fix plan. Read **`docs/plans/roadmap.md`** first, then the
plan for the PR you're on (**`docs/plans/privileged-helper.md`**: L, M (M1–M3, with P), N and O
are done; Q, plain CSS instead of Sass, is built). The privilege model is in
`docs/security/PRIVILEGE-ESCALATION-MITIGATION.md`.

## Workflow

- One PR per change set: branch from `main` → PR → CI green → merge (Troy approves merging fix PRs
  once CI passes) → Troy runs **System Update** in the NAS web UI and checks → next PR.
- After each merge, stop and report to Troy in a few plain sentences: what changed, and exactly
  what to click or check on the NAS. Wait for his OK before starting the next PR.
- You can't reach the NAS. Never ask for SSH access, and never ask for or print secrets (tokens,
  passwords, `amahi.env`, `secret_key_base`). Anything that needs the NAS is Troy's to run: give him
  read-only commands and ask for the output.
- Commit as `CatDogBark <troyevangelist@gmail.com>`. Keep `CHANGELOG.md` up to date in each PR
  (Unreleased → "Security & Fixes" or "Architecture & Code Quality"), written for users.
- Don't decide things the plan marks as Troy's decision; ask.

## Tests and CI

CI (`.github/workflows/ci.yml`) blocks merges on all of these:

| Job | Command |
| --- | --- |
| Models | `bundle exec rspec spec/models/ spec/services/ spec/helpers/ --tag ~docker` |
| Lib | `bundle exec rspec spec/lib/ --tag ~integration` |
| Requests | `bundle exec rspec spec/requests/ --tag ~integration` |
| Features | `bundle exec rspec spec/features/ --tag ~js --tag ~archived` |
| MariaDB | models + requests again on MariaDB 10.11 (`DATABASE_URL`), the production database |
| Lint & Security | RuboCop 1.91.0 (+ rails 2.38.0, rspec 3.10.2), Brakeman 8.1.0, bundle-audit 0.9.3, installed as gems, not bundled |

- Prepare the test DB with `RAILS_ENV=test bundle exec rails db:schema:load`. Tests use SQLite.
- RuboCop fails only on new offenses; old ones are in `.rubocop_todo.yml`. Brakeman fails on
  anything not in `config/brakeman.ignore`, and every entry there needs a `note`.
- **Ruby is 3.2 on the NAS (Ubuntu's `ruby3.2`, 3.2.3).** Change `Gemfile.lock` only under Ruby
  3.2.x with Bundler 2.4.19, so the resolver can't pick gems the NAS can't run. Update gems
  minimally (`bundle update --conservative --patch <gem>`).
- In tests `Shell.dummy?` is true, so `Shell.run` commands don't execute, and `Privileged.call`
  records calls in `Privileged.calls` (reset before each example) instead of running the helper.
  Code that runs commands as argument lists through `Open3` must be stubbed. Request specs log in with `login_as_admin`
  or `login_as(user)` (`spec/support/request_helpers.rb`).
- Migrations must be safe to rerun (`if_exists`, `column_exists?`): MariaDB can't roll back DDL.

## Things that have bitten us

- **The LAN UI is plain HTTP**, so browsers don't send `Sec-Fetch-Site`. Server-sent-event streams
  (`*_stream` actions) prove they come from an Amahi page with the CSRF token in the URL
  (`withStreamToken` in `app/assets/javascripts/stream_token.js`). A stream change can break
  System Update itself.
- **A failed System Update rolls back** to the commit that was running (since O; from #21 to #24
  failures went unnoticed for four PRs). After an update, check its last line: "✓ Amahi-kai
  updated and running!", or "✗ Update failed at: <step>. Rolled back to <commit>". Production
  reads the compiled-assets manifest at every boot, which CI never does;
  `spec/lib/assets_manifest_spec.rb` covers it.
- **Migrations must work with the previous version's code**: rollback puts the code back but not
  the database (it's dumped to `/var/lib/amahi-kai/backups` first). Add columns and tables;
  don't rename or drop in the same PR that stops using them.
- **The update that deploys a change runs the old code.** `bin/amahi-update` re-execs itself after
  `git pull` (bash would otherwise keep running the old copy) and passes the commit to roll back
  to. The web UI starts it as its own job (`amahi-kai-update.service`, via the helper's
  `system.update`) and follows `/var/log/amahi-kai/update.log`, reconnecting through the app's
  restart. Run inside `amahi-kai.service` (the web UI before O), it can't check the restarted app.
  If System Update breaks, Troy runs `sudo /opt/amahi-kai/bin/amahi-update` over SSH.
- **Root access goes through the helper.** User accounts, Samba's files, share folders, Settings →
  Servers, the hostname, dnsmasq, swap, reboot/power off, data drives (format, mount, fstab),
  Greyhole, package installs (pinned apt repositories, a fixed package list), the Cloudflare
  Tunnel, Tailscale and the security audit's fixes are changed by `libexec/amahi-helper`
  (`Privileged.call('users.create', ...)`), which validates and logs every call. Add an operation
  there, not a sudoers rule. Sudoers rules (only the helper, the updater and Docker are left) are in
  `config/sudoers/amahi-kai`; `bin/amahi-install-helper` installs them and the helper (the
  installer and the updater both run it) only after `visudo -cf` passes.
- **Root owns the code.** `/opt/amahi-kai` is root's except `tmp/`, `log/`, `public/assets/` and
  `vendor/bundle/` (`bin/amahi-set-ownership`, run by the installer and at the start of every
  update). Root never runs app code: in `bin/amahi-install` and `bin/amahi-update`, every `bundle`,
  `bin/rails` and `rails runner` step goes through `as_app` (a spec checks). Anything the app writes at
  runtime must go in one of those folders or outside the tree.
- **Stylesheets are plain CSS** (no Sass compiler since Q). Bootstrap is the official 5.3.8 build
  in `vendor/assets` (CSS, and JS with Popper); update it by replacing those files. Theme CSS in
  `public/themes/*/stylesheets` is built by hand from `src/` with Dart Sass.
- `Shell.capture` and `Open3` don't set `$?`; use the status they return.
- Build commands from names as argument lists (`Open3.capture3('systemctl', 'show', unit)`), not
  strings through a shell.
- `lib/system_services.rb` is the one list of system services (dashboard, System Status and
  Settings → Servers). The services it gives `actions` to must match the helper's `SERVICES` list
  (a spec checks).
- Production refuses to boot without `SECRET_KEY_BASE` and creates `/var/lib/amahi-kai` at boot.
  To check production boot without root: `unshare -rm` and bind a scratch dir over `/var/lib`.
- Samba config is generated from `Share.samba_conf` and must pass `testparm` before it's installed.
- The detailed code review (findings, file and line references) is a Claude Doc Troy owns:
  https://claude.ai/code/artifact/df32228a-72d8-41b9-b5c1-80e0dea1f32d. Unfixed security
  details stay there, not in this public repo.
