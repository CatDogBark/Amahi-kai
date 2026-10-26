# Contributing to Amahi-kai

## Setting up

For a real install (recommended for anything that touches the system), use a dedicated Ubuntu
24.04 machine or VM:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

For working on the code and running tests, you need Ruby 3.2 and SQLite:

```bash
bundle install
RAILS_ENV=test bundle exec rails db:schema:load
```

## Branches

`main` holds released code. Work goes into `dev`: small fixes straight onto it, bigger topics on a
branch of their own through a pull request into `dev`. `dev` merges into `main` for a release,
through a pull request, with a merge commit (not a squash), so the two branches share their
history.

Once 1.0 is out, every merge into `main` is a release. Changes to the website alone (`site/`,
deployed from `main`) are the usual exception.

## Tests

Tests use SQLite and never change the system: outside production `Privileged.call` records
calls instead of running the root helper. Commands that only read the system (`Shell.output`,
`Shell.success?`) do run, so specs stub them. CI runs these groups (and the first and third again
on MariaDB):

```bash
bundle exec rspec spec/models/ spec/services/ spec/helpers/
bundle exec rspec spec/lib/
bundle exec rspec spec/requests/
bundle exec rspec spec/system/      # a real browser; needs Chrome or Chromium (or BROWSER_PATH)
```

Lint and security checks (installed as gems, not in the bundle): RuboCop 1.91.0 with
rubocop-rails 2.38.0 and rubocop-rspec 3.10.2, Brakeman 8.1.0, bundle-audit 0.9.3. RuboCop fails
on any offense; Brakeman fails on anything not in `config/brakeman.ignore`, and every entry there
needs a note.

Run the whole suite locally before pushing; `CLAUDE.md` (Tests and CI) has the commands and the
Ruby they need. On GitHub:

- **Pull requests into `dev`** run nothing: the local run is their check.
- **Pushes to `dev` and `main`, and pull requests into `main`**, run everything in
  `.github/workflows/ci.yml`: the specs on SQLite and on MariaDB, the specs that need root, the
  browser specs, RuboCop, Brakeman and bundle-audit, and the migrations from nothing.
- Any branch can be checked by hand: `gh workflow run ci.yml --ref <branch>`.

## Making a change

- One change per pull request, with specs; CI must pass.
- Add a line to `CHANGELOG.md` (Unreleased), written for the people who use Amahi-kai.
- Anything that needs root is an operation in `libexec/amahi-helper` (arguments, validation and
  logging), called with `Privileged.call`. Don't add sudoers rules.
- Run commands as argument lists (`Open3.capture3('systemctl', 'show', unit)`), not strings through
  a shell.
- Migrations must be safe to run twice and must work with the previous version's code: an update
  that fails rolls the code back, not the database.
- Change `Gemfile.lock` only under Ruby 3.2 with Bundler 2.4.19, so it resolves gems the servers'
  Ruby can run.
- Views are Slim or ERB; JavaScript is plain JavaScript and Stimulus (`app/assets/javascripts`);
  every fetch sends the CSRF token (`csrfHeaders()`).

## Versions

Versions are `X.Y.Z`, and a release candidate is `X.Y.ZrcN`, published as a pre-release. The
`VERSION` file at the top of the repository names the release the code is, or comes after. System
Status shows it, and System Update reads it so it never goes back to an older version.

## Cutting a release

1. **`CHANGELOG.md`:** the Unreleased section becomes `## [X.Y.Z] — date`, with a new, empty
   `## [Unreleased]` above it. A release candidate keeps its changes under Unreleased (or under
   its release's section, once there is one).
2. **`VERSION`:** `X.Y.Z` (or `X.Y.ZrcN`).
3. **A pull request from `dev` into `main`:** merge it once CI is green, with a merge commit, and
   wait for CI to go green again on `main`.
4. **Tag the merge commit and push the tag:**

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z — one line on what it is"
   git push origin vX.Y.Z
   ```

   The tag starts `.github/workflows/release.yml`, which refuses a tag that doesn't match
   `VERSION` or isn't on `main`, waits for CI's run on that commit to pass (up to 30 minutes,
   and refuses if it failed), then publishes the GitHub Release with the changelog section as
   its notes (a pre-release for an `rc` tag).

Servers on the `releases` channel offer the new version at their next check (every 6 hours, or
**Check now**); `candidates` servers offer release candidates too.

## Update channels

Each server follows one channel, chosen on Settings → System Status (Follows) and kept as
`AMAHI_UPDATE_CHANNEL` in `/etc/amahi-kai/amahi.env` (root's; the helper's
`system.set_update_channel` changes that line only):

- `releases`, the default: published releases.
- `candidates`: releases and release candidates.
- `development`: the newest commit on `dev`, for testing. A server installed with
  `AMAHI_BRANCH=dev` starts here.

The site's wiki has the details for owners: [Updating](https://amahi-kai.com/wiki/updating).

## The public name

The repository is public: its owner is CatDogBark, the contact is catdogbark@pm.me, and the
copyright is Enlightened Solutions LLC's. Commit as `CatDogBark <186357707+CatDogBark@users.noreply.github.com>`.

## License

GNU AGPL v3. Contributions must be compatible with it.
