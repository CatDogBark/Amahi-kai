# Amahi-kai: notes for Claude sessions

Amahi-kai is a Rails 8.1 NAS web app for Ubuntu 24.04, modernized from the 2013 Amahi platform,
for other people to install. The repo is public (`CatDogBark/Amahi-kai`); its maintainer is
CatDogBark (catdogbark@pm.me).

Read **`docs/plans/roadmap.md`** first, then the plan for the work you're on: storage is
**`docs/plans/storage.md`**, apps **`docs/plans/apps.md`** (the app catalog is its own repo,
[CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps), fetched with the update
check), backups **`docs/plans/backups.md`**. The privilege model is in
`docs/security/PRIVILEGE-ESCALATION-MITIGATION.md`, and the test checklists are in `docs/testing/`.
The Content-Security-Policy is enforced: no inline scripts or handlers (inline styles are still
allowed).

## Workflow

- **Development is on `dev`**; `main` is the release branch. Commit to `dev` and push → CI green
  on `dev` → PR `dev` → `main`, merged with a merge commit (not squash, so the two keep one
  history) → tagged and released as `CONTRIBUTING.md` says (Cutting a release). Pull requests
  into `dev` run no CI. Merges into `main` and releases are the maintainer's call.
- **System Update follows an update channel** (`AMAHI_UPDATE_CHANNEL` in the server's
  `amahi.env`): `releases`, `candidates` or `development` (the `dev` branch). A push to `dev` is
  tried on a test install that follows `development` before it goes into a release.
- Never ask for or print secrets (tokens, passwords, `amahi.env`, `secret_key_base`).
- In this repo, its docs, pull requests and commit messages, the maintainer is CatDogBark. Keep
  `CHANGELOG.md` up to date in each PR (Unreleased → "Security & Fixes" or "Architecture & Code
  Quality"), written for users.
- Don't decide things a plan marks as the maintainer's decision; ask.

## Tests and CI

CI (`.github/workflows/ci.yml`) blocks merges on all of these:

| Job | Command |
| --- | --- |
| Models | `bundle exec rspec spec/models/ spec/services/ spec/helpers/` |
| Lib | `bundle exec rspec spec/lib/` |
| Requests | `bundle exec rspec spec/requests/` |
| MariaDB | models + requests again on MariaDB 10.11 (`DATABASE_URL`), the production database |
| Lint & Security | RuboCop 1.91.0 (+ rails 2.38.0, rspec 3.10.2), Brakeman 8.1.0, bundle-audit 0.9.3, installed as gems, not bundled |
| Browser | `bundle exec rspec spec/system`: Chrome, headless, loads the pages as an admin and clicks (`docs/plans/browser-tests.md`) |

- Prepare the test DB with `RAILS_ENV=test bundle exec rails db:schema:load`. Tests use SQLite.
- RuboCop fails on any offense (there's no list of old ones to skip). Brakeman fails on
  anything not in `config/brakeman.ignore`, and every entry there needs a `note`.
- **Browser specs** (`spec/system`, `spec/support/browser_specs.rb`) need Chrome or Chromium on the
  PATH, or `BROWSER_PATH`; without one they skip. Every example fails on anything the browser
  logs at error level (a refused inline script, an exception, a failed request), so a page
  passes only when it loads clean. They sign in through the real form as the seeded admin, and
  run with truncation (the server thread can't see a transaction); a failure's screenshot is in
  `tmp/capybara/`.
- Every spec runs in CI: there are no tags that CI skips. A spec that needs root
  skips itself (`skip 'needs root' unless Process.euid.zero?`).
- **Ruby is 3.2 where Amahi-kai runs (Ubuntu 24.04's `ruby3.2`, 3.2.3).** Change `Gemfile.lock`
  only under Ruby 3.2.x with Bundler 2.4.19, so the resolver can't pick gems an install can't
  run. Update gems minimally (`bundle update --conservative --patch <gem>`).
- Outside production `Shell.simulated?` is true (no setting changes it), so `Privileged.call`
  records calls in `Privileged.calls` (reset before each example) instead of running the helper.
  Commands that only read the system (`Shell.output`, `Shell.success?`, `Open3`) do run in tests,
  so stub them. Request specs log in with `login_as_admin` or `login_as(user)`
  (`spec/support/request_helpers.rb`).
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
- **A new install loads `db/schema.rb`; an old NAS ran the migrations.** Rails 8.1's `db:migrate`
  loads the schema file into an empty database instead of running the migrations, so the two
  paths must make the same tables: CI runs the migrations from nothing and diffs the schema they
  write against `db/schema.rb` (keep the two in step; never edit one alone).
- **The update that deploys a change runs the old code.** `bin/amahi-update` re-execs itself after
  `git pull` (bash would otherwise keep running the old copy) and passes the commit to roll back
  to; the new copy keeps the update lock and doesn't look the version up again. Any stop after
  the checkout rolls back (an EXIT trap), and `/var/lib/amahi-kai/deployed-commit` names the
  commit fully in place, so an update cut off even before that is finished by the next one
  instead of reading as up to date. The web UI starts it as its own job (`amahi-kai-update.service`, via the helper's
  `system.update`) and follows `/var/log/amahi-kai/update.log`, reconnecting through the app's
  restart. Run inside `amahi-kai.service` (the web UI before O), it can't check the restarted app.
  Puma finishes open requests before it stops, so a stream that waits on the update must end
  when Puma is stopping (`server_stopping?` in `SettingsController`), or the restart waits for
  systemd to kill Puma (90 seconds; `force_shutdown_after` in `config/puma.rb` now caps it).
  If System Update itself breaks, run `sudo /opt/amahi-kai/bin/amahi-update` on the server.
- **Root access goes through the helper.** User accounts, Samba's files, share folders, Settings →
  Servers, the hostname, dnsmasq, swap, reboot/power off, data drives (format, mount, fstab),
  ZFS pools, Greyhole, package installs (pinned apt repositories, a fixed package list), the Cloudflare
  Tunnel, Tailscale, Docker apps and the security audit's fixes are changed by `libexec/amahi-helper`
  (`Privileged.call('users.create', ...)`), which validates and logs every call. Add an operation
  there, not a sudoers rule. The helper's is the only sudoers rule left (since P4.1), in
  `config/sudoers/amahi-kai`; `bin/amahi-install-helper` installs it and the helper (the
  installer and the updater both run it) only after `visudo -cf` passes.
- **Root owns the code.** `/opt/amahi-kai` is root's except `tmp/`, `log/`, `public/assets/` and
  `vendor/bundle/` (`bin/amahi-set-ownership`, run by the installer and at the start of every
  update). Root never runs app code: in `bin/amahi-install` and `bin/amahi-update`, every `bundle`,
  `bin/rails` and `rails runner` step goes through `as_app` (a spec checks). Anything the app writes at
  runtime must go in one of those folders or outside the tree.
- **Stylesheets are plain CSS** (no Sass compiler since Q). Bootstrap is the official 5.3.8 build
  in `vendor/assets` (CSS, and JS with Popper); update it by replacing those files. There's one
  look and no themes: `app/assets/stylesheets/theme.css` is the last file `application.css`
  joins, so it wins; its October 2026 refresh block (mint, Space Grotesk, the glass panels) is at
  its end. Every page is dark (`data-theme="dark"` in the layouts).
- `Open3` doesn't set `$?`; use the status it returns (or `Shell.success?`).
- **`systemctl enable --now` / `disable --now` only start and stop native units.** Greyhole's is an
  init script (a generated unit): `--now` switched its boot start but left the daemon as it
  was. Switch a unit with two commands (enable then start, disable then stop), as the helper's
  `switch_unit` and `services.enable` do. Checking a process over SSH, `pgrep -f` inside
  `bash -c '…'` matches that shell's own command line: use `ps -eo args | grep '[g]reyhole'`.
- **`lsblk -J` only nests partitions and volumes under their disk when NAME is the first
  column**; with PATH first it lists every device flat, and a disk looks empty (#45: the helper's
  system-disk check didn't hold). Ask for `NAME,PATH,...`; the helper refuses a flat list, and
  specs run the real `lsblk`. Check fixtures against a real command's output.
- **Pages name drives by their `/dev/disk/by-id` link** (`:ref`, `DiskManager.by_id_refs`), never
  the kernel name, which can belong to another drive after a restart or a swap; the controller (or
  `StoragePools`) turns it back into the kernel name with `DiskManager.resolve` just before acting.
  Only pools that mount at `/srv/pools/<name>` are Amahi-kai's (`managed_pool` in the helper,
  `Pool#managed?`): the others are shown, never changed.
- **App jobs run as units of their own.** `apps.install/update/undo_update/uninstall` re-run
  themselves under `systemd-run` as `amahi-kai-appjob-<id>` (the helper's `relay_app_job`), so a
  restart of the web app can't cut one off; the unit name keeps one job per app, and Start/Stop
  and `apps.follow_pool` wait for it. Containers are rebuilt from the definition they were made
  from (`APP_DEFINITIONS`), never from a newer catalog manifest with the old image.
- Build commands from names as argument lists (`Shell.output('systemctl', 'show', unit)`), never
  backticks or strings through a shell. Read what Ruby or `/proc` can give directly
  (`SystemInfo`).
- **Addresses are made in one place.** Every link to an app goes through `DockerApp#url`, every
  link to Amahi-kai itself through `ApplicationHelper#amahi_url`; never hand-build
  `http://host:port` (`spec/lib/addresses_spec.rb` fails CI if you do). HTTPS is planned as an
  optional front door, with plain HTTP staying fully working (CatDogBark, 2026-10-06; roadmap), and it
  depends on this.
- **App versions and new apps are PRs on the catalog's repo** (`amahi-kai-apps`), not here:
  `script/app-versions --catalog ../amahi-kai-apps/apps --update <app>`. `config/apps` is only the
  copy that comes with Amahi-kai (`config/apps/README.md`); the wiki's `site/wiki/making-apps.md`
  is the guide to making one.
- `lib/system_services.rb` is the one list of system services (dashboard, System Status and
  Settings → Servers). The services it gives `actions` to must match the helper's `SERVICES` list
  (a spec checks).
- Production refuses to boot without `SECRET_KEY_BASE` and creates `/var/lib/amahi-kai` at boot.
  To check production boot without root: `unshare -rm` and bind a scratch dir over `/var/lib`.
- Samba config is generated from `Share.samba_conf` and must pass `testparm` before it's installed.
