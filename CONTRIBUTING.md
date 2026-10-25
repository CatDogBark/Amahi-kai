# Contributing

## Branches

`main` holds released code. Work goes into `dev`: small fixes straight onto it, bigger topics on a
branch of their own through a pull request into `dev`. `dev` merges into `main` for a release,
through a pull request, with a merge commit (not a squash), so the two branches share their
history.

Once 1.0 is out, every merge into `main` is a release. Changes to the website alone (`site/`,
deployed from `main`) are the usual exception.

## Checks

Run the whole suite locally before pushing; see `CLAUDE.md` (Tests and CI) for the commands and the
Ruby they need. On GitHub:

- **Pull requests into `dev`** run nothing: the local run is their check.
- **Pushes to `dev` and `main`, and pull requests into `main`**, run everything in
  `.github/workflows/ci.yml`: the specs on SQLite and on MariaDB, the browser specs, RuboCop,
  Brakeman and bundle-audit.
- Any branch can be checked by hand: `gh workflow run ci.yml --ref <branch>`.

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
