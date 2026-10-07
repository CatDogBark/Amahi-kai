# The catalog that comes with Amahi-kai

The app catalog lives in its own repo,
[CatDogBark/amahi-kai-apps](https://github.com/CatDogBark/amahi-kai-apps), which every NAS fetches
with its update check (the root helper's `system.check_update`) and checks before using. Its
README lists every manifest field, and the wiki's
[Making Apps](https://amahi-kai.com/wiki/making-apps) explains how to make one.

This folder is the copy that comes with Amahi-kai: what a NAS offers before its first fetch, and
the manifest of an app the catalog no longer lists. The fetched catalog always comes first.
Bring the copy up to date now and then, from a checkout of the catalog beside this one:

```bash
cp ../amahi-kai-apps/apps/*.yml config/apps/
```

Changes to apps go to the catalog's repo, not here. `script/app-versions` writes new versions
there:

```bash
script/app-versions --catalog ../amahi-kai-apps/apps --update gitea
```
