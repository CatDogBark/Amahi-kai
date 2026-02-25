---
layout: default
title: "Updating"
---

# Updating

Amahi-kai can be updated from either the web UI or the command line. Updates pull the latest code from GitHub, install any new dependencies, run database migrations, rebuild assets, and restart the service.

---

## Web UI Update

1. Go to **Settings > System Status**
2. Click **Update System**
3. Watch the streaming progress as each step completes

The web UI calls `sudo /opt/amahi-kai/bin/amahi-update --stream` and displays each line of output in real-time.

---

## CLI Update

Run the update script directly:

```bash
sudo /opt/amahi-kai/bin/amahi-update
```

The `--stream` flag produces cleaner output for the web UI's SSE stream:

```bash
sudo /opt/amahi-kai/bin/amahi-update --stream
```

---

## What the Update Does

The `bin/amahi-update` script performs these steps in order:

### 1. Pull Latest Code

If the app directory has a `.git` history:
```bash
git pull origin main
```

If there's no `.git` directory (e.g., installed from a tarball), it clones fresh from GitHub and syncs the files over with rsync, preserving `.git` for future pulls.

### 2. Install Dependencies

```bash
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install --jobs 4
```

This installs any new gems added since the last update.

### 3. Run Database Migrations

```bash
RAILS_ENV=production bin/rails db:migrate
```

Applies any new database schema changes.

### 4. Clear Caches and Precompile Assets

```bash
rm -rf tmp/cache public/assets
RAILS_ENV=production bin/rails assets:precompile
```

Rebuilds all CSS and JavaScript assets.

### 5. Fix File Ownership

```bash
chown -R amahi:amahi /opt/amahi-kai
```

Ensures the `amahi` user owns all application files.

### 6. Restart Service

```bash
systemctl restart amahi-kai
```

After restarting, the script waits 2 seconds and verifies the service is active.

---

## Verifying the Update

After updating, check that everything is running:

```bash
# Service status
systemctl status amahi-kai

# Check the version in logs
journalctl -u amahi-kai -n 5 --no-pager

# Access the web UI
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Should return 302 (redirect to login)
```

---

## Troubleshooting Updates

### Update fails at "Pulling latest code"

```bash
# Check git status
cd /opt/amahi-kai
sudo -u amahi git status

# If there are local changes blocking the pull
sudo -u amahi git stash
sudo /opt/amahi-kai/bin/amahi-update
```

### Update fails at "Installing dependencies"

```bash
# Check for gem build errors
cd /opt/amahi-kai
sudo -u amahi bash -lc "bundle install --jobs 4 2>&1"

# If native extensions fail, you may need dev libraries
sudo apt-get install -y build-essential libmariadb-dev libssl-dev libyaml-dev
```

### Service fails to start after update

```bash
# Check what went wrong
journalctl -u amahi-kai -n 30 --no-pager

# Common fix: re-run migrations
cd /opt/amahi-kai
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails db:migrate"

# Then restart
sudo systemctl restart amahi-kai
```

### Rolling back

If an update breaks things, you can roll back to a previous version:

```bash
cd /opt/amahi-kai
# See recent commits
sudo -u amahi git log --oneline -10

# Check out the previous working commit
sudo -u amahi git checkout <commit-hash>

# Re-run migrations and restart
sudo -u amahi bash -lc "source /etc/amahi-kai/amahi.env && RAILS_ENV=production bin/rails db:migrate"
sudo systemctl restart amahi-kai
```

---

## Automatic Updates

Amahi-kai does not auto-update itself. Updates are intentionally manual so you can choose when to apply them. If you want automatic updates, you could create a cron job:

```bash
# NOT RECOMMENDED for most users, but possible:
echo "0 3 * * 0 root /opt/amahi-kai/bin/amahi-update >> /var/log/amahi-update.log 2>&1" | sudo tee /etc/cron.d/amahi-update
```

This would update every Sunday at 3 AM. However, manual updates are recommended so you can review changes and handle any issues interactively.
