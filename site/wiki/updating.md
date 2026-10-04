---
layout: default
title: "Updating"
---

# Updating

Amahi-kai checks for updates on its own and tells you when one is waiting. You choose when to
install it, from the web UI or the command line. If an update fails, Amahi-kai goes back to the
version that was running.

---

## Seeing what's new

Go to **Settings > System Status**. The **System Update** card shows one of:

- **Update available: N changes**, with each change listed and linked to its pull request on
  GitHub, and an **Update now** button.
- **Up to date (abc1234)**, with a **Repair** button (see below).
- **Not checked yet**, right after installing.

Amahi-kai checks 10 minutes after the server starts and then every 6 hours (the
`amahi-kai-update-check.timer` systemd timer). **Check now** checks straight away. The card says
when it last checked, and why if a check failed (for example, GitHub couldn't be reached).

The check only looks; it never installs anything.

---

## Installing an update

1. Go to **Settings > System Status**.
2. Read the list of changes, then click **Update now**.
3. A window shows each step as it runs, with a timer at the bottom. Amahi-kai restarts near the
   end; the window waits for it and carries on.
4. When it says **✓ Updated in …**, click **Reload page** to load the new version.

The update runs as its own job on the server (`amahi-kai-update.service`), so closing the browser
doesn't stop it. Its log is `/var/log/amahi-kai/update.log`.

An update with nothing new stops right after checking GitHub ("✓ Already up to date"), without
reinstalling or restarting anything.

### Repair

**Repair** (shown when you're up to date) runs every update step again on the version you have:
gems, database migrations, the root helper and its sudo rules, the Samba configuration, file
ownership, compiled assets and a restart. Use it when something about the install looks broken.

---

## From the command line

```bash
sudo /opt/amahi-kai/bin/amahi-update            # install an update
sudo /opt/amahi-kai/bin/amahi-update --repair   # run every step again on the current version
```

This is also the way in if the web UI itself won't load: SSH to the server and run it.

---

## What an update does

1. **Gets the latest code** from GitHub (as root; the code in `/opt/amahi-kai` belongs to root).
   If nothing is new, it stops here. If GitHub can't be reached, it stops and changes nothing.
2. **Installs gems** for the new version.
3. **Backs up the database** to `/var/lib/amahi-kai/backups` (readable by root only; the last 3
   are kept).
4. **Runs database migrations.**
5. **Installs the root helper and the sudo rules** that come with the new version (the rules are
   checked with `visudo` first, so a bad file can't break sudo).
6. **Regenerates the Samba configuration** and restarts Samba.
7. **Rebuilds the web UI's styles and scripts.**
8. **Remounts data drives** (in case one dropped).
9. **Restarts Amahi-kai** and checks that it answers.
10. **Refreshes the update status** on System Status.

### If something fails

If a step fails, or the restarted app doesn't answer, the update puts back the version that was
running: its code, gems, compiled assets, root helper and sudo rules. The last line says so:

```
✗ Update failed at: Running database migrations. Rolled back to abc1234; Amahi-kai is running the version it was.
```

The database isn't rolled back automatically (migrations are written so the previous version
still works with the new schema). If you ever need the backup taken before the update, it's the
newest file in `/var/lib/amahi-kai/backups`.

---

## Troubleshooting

### Read the log

```bash
sudo tail -50 /var/log/amahi-kai/update.log      # the last update's output
journalctl -u amahi-kai-update -n 50 --no-pager  # the update job
journalctl -u amahi-kai -n 50 --no-pager         # the app after its restart
```

### The update window lost track of the update

If the window says it lost track, the update is still running on the server. Wait a minute, then
reload the page, or check the log above.

### Fixing permissions or a half-applied update

Run **Repair**, or `sudo /opt/amahi-kai/bin/amahi-update --repair`. Don't change the ownership of
`/opt/amahi-kai` by hand: root owns the code on purpose, so the web app can't change what root
runs. Repair puts the ownership back the way it should be.

### Checking the update check

```bash
systemctl list-timers amahi-kai-update-check.timer   # when it runs next
sudo cat /var/lib/amahi-kai/update-status.json       # what it found last
```

---

## Automatic updates

Amahi-kai checks automatically but doesn't install updates on its own, so you can read what
changes first and pick a convenient time.
