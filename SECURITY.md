# Security

## Reporting a problem

Please don't post a security problem anywhere public: not in an issue, and not through Amahi-kai's
**Report a problem**, which opens a public GitHub issue (it takes names and addresses out, but the
problem itself would still be there for anyone to read). Report it privately instead:

- **Report a vulnerability** on this repository's
  [Security tab](https://github.com/CatDogBark/Amahi-kai/security/advisories/new), or
- email catdogbark@pm.me.

Say what you found, how to make it happen, and the Amahi-kai version (Settings → System Status).

## What happens next

A fix ships in a release, and the advisory is published once servers can update to it, crediting
you if you'd like. Amahi-kai is looked after by one person, so there's no set time for an answer.

## What's covered

- Amahi-kai itself: its web app, the root helper that makes every change as root, the installer,
  and System Update.
- The app catalog ([amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps)): a manifest
  that gives an app more than it should, for example.

Not covered: a problem inside an app Amahi-kai installs (Jellyfin, Gitea and the rest). Please
report those to that app's own project.

## Supported versions

Only the latest release gets fixes; System Update installs it.

## How Amahi-kai is built

Every change Amahi-kai makes as root goes through one root helper, which checks each request and
logs it; the web app itself runs as an ordinary user. Apps run in containers as users of their own,
without raw sockets or device files, and get only the folders and shares they're given. The design
is in [docs/security/PRIVILEGE-ESCALATION-MITIGATION.md](docs/security/PRIVILEGE-ESCALATION-MITIGATION.md),
and Network → Security checks a server's own setup.
