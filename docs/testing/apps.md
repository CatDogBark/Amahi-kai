# App tests on the NAS

Apps through the root helper (P4.1, #58), reaching apps (P4.2, #59), shares for apps (P4.4, #60)
and app updates (P4.5, #62) were built and checked with specs, but no app has been installed on
the NAS yet. This is the list to run when there's
time. Tick each box as it passes; if one doesn't, stop there and send Claude what the page shows
plus the output of the [commands at the end](#if-something-fails).

Run each command on its own. `192.168.1.111` is the NAS's LAN address.

---

## 1. Before you start

- [ ] **Settings → System Status** says **Up to date**.
- [ ] **Apps**: Docker shows **Running**, and the five apps are listed.
- [ ] Amahi-kai's firewall rules for apps are in place. This lists them:

  ```bash
  sudo iptables -S AMAHI-APPS
  ```

  Expect a line with `-s 192.168.1.0/24 -j RETURN`, one with `-i tailscale0 -j RETURN`, and
  `-A AMAHI-APPS -j DROP` last. And Docker's chain jumps to them:

  ```bash
  sudo iptables -S DOCKER-USER
  ```

  Expect `-A DOCKER-USER -j AMAHI-APPS`.
- [ ] The web app's only sudo rule is the helper's, and `amahi` isn't in the `docker` group:

  ```bash
  sudo -l -U amahi
  ```

  ```bash
  id amahi
  ```

## 2. Install each app

For each app: click **Install**. The window ends with "✓ … is installed and running" and "Open it
at http://192.168.1.111:<port>/". The app's row then says **Port …** (or **Ports …**) and has
**Open**. Click it.

Jellyfin, Uptime Kuma and Gitea give the admin account to whoever opens them first, so set each
one up as soon as it's installed.

- [ ] **Uptime Kuma** (port 3001): create the admin account, add a monitor (for example
  `https://www.google.com`), and it goes green.
- [ ] **Jellyfin** (port 8096): the setup wizard runs. Skip adding media: shares come with P4.4.
- [ ] **Gitea** (ports 3300 and 2222): its first page is the installer. Keep SQLite, set the
  **Gitea Base URL** to `http://192.168.1.111:3300/`, create the admin account, then create a
  test repository.
- [ ] **Transmission** (ports 9091 and 51413): it asks for a login. The user is `admin`; the
  password is under **Passwords and keys Amahi-kai made for Transmission** on its row (**Copy**
  works).
- [ ] **bitTube** (port 8484): make its account on the first visit, follow a channel on its
  Channels page (`@veritasium`), and play a video: it starts within a few seconds, seeking works,
  and a sponsor segment (if the video has one) is skipped. In its Settings, tick your streaming
  services and paste a TMDB key: their tabs fill in. Give it a share with **Read and write**
  (Change next to its shares), set its download folder to `/shares/<name>`, and download a video:
  it appears in the share as an MP4.
- [ ] **Vaultwarden** (port 8880): it installs and runs. Its `/admin` page
  (`http://192.168.1.111:8880/admin`) takes the token under **Passwords and keys**. The web vault
  itself needs HTTPS, which comes later through Tailscale, so creating an account there is
  expected to fail for now.

Then check they run as their own users, with their own folders:

```bash
sudo docker ps --filter label=amahi.app --format '{{.Names}} {{.Status}} {{.Ports}}'
```

Each line shows `0.0.0.0:<port>->…`.

```bash
sudo ls -ln /var/lib/amahi-kai/apps
```

Each folder belongs to a different number below 1000.

- [ ] **Network → Security**: the **Docker ports** check passes, listing the apps' ports as
  reachable from the LAN and Tailscale only.

## 3. Reaching apps

- [ ] **On the LAN**: Open works from your PC, and from your phone on Wi-Fi.
- [ ] **Through Tailscale**: on your phone, turn Wi-Fi off, keep Tailscale on, and open
  `http://<the NAS's Tailscale name or 100.x address>:3001`. Uptime Kuma opens.
- [ ] **Through the Cloudflare Tunnel** (Amahi-kai's public address): the Apps page says "Open it
  on your LAN or Tailscale" instead of **Open**, and the dashboard's app tiles go to the Apps page.
- [ ] `http://192.168.1.111:3000/app/uptimekuma` is a Not Found page (the old proxy is gone).

## 4. Shares

- [ ] **Jellyfin**: click **Change** next to **No shares** on its row, tick **Movies** (or any share
  with a video in it), **Save and restart**. The row says **Shares Movies (read only)**. In
  Jellyfin, add `/shares/Movies` as a library: the video plays.
- [ ] Jellyfin can't change the share (it's read only):

  ```bash
  sudo docker exec amahi-jellyfin touch /shares/Movies/test
  ```

  It answers "Read-only file system".
- [ ] **Transmission**: make a share called `Downloads` that Greyhole doesn't pool, then
  **Change** Transmission's shares: tick it with **Read and write**. In Transmission's settings,
  set the download folder to `/shares/Downloads`, and download something small (a Linux ISO's
  torrent).
- [ ] From your PC over SMB, rename and then delete the downloaded file in `Downloads`. Both work.
- [ ] Once there's a pooled share (storage tests, step 4), give it to Jellyfin: its files play,
  and **Read and write** isn't offered for it ("Read only: Greyhole pools it").

## 5. Updates

This needs an app whose catalog version is newer than the one it runs. The first time a version
bump reaches the NAS (`script/app-versions`, then a PR and System Update), install the app
**before** that update, so its row then offers the new version. Uptime Kuma or Vaultwarden is a
good one to try first: they have Docker health checks and small data.

- [ ] The row says **Version <old>** and **Update to <new>**, with **What's new** opening the
  release notes. The dashboard's Apps card says **1 update**.
- [ ] **Update to <new>**: the window copies the data, starts the new version, waits for it to be
  healthy and ends with ✓. The row says **Version <new>**, with **Undo update (until <date>)**.
  The app's own data (Uptime Kuma's monitors) is still there.
- [ ] **Undo update**: the window ends with ✓, the row says **Version <old>** again, and Update is
  offered again.
- [ ] **Settings → Jobs** lists **App update copies**, daily.
- [ ] Optional, rollback: the copy and the version come back by themselves when the new version
  doesn't start. That's hard to cause on purpose; the specs cover it.

## 6. Uninstall and data

- [ ] **Uninstall** Uptime Kuma (it says the data stays). Its row goes back to **Install**, with
  "Its data from an earlier install is kept and used again."
- [ ] **Install** it again: your monitor is still there, on the same port.
- [ ] **Uninstall** it, then **Delete it**. Its folder is gone:

  ```bash
  sudo ls /var/lib/amahi-kai/apps
  ```

## 7. Reboot

- [ ] **Stop** one app, then reboot the VM. The running apps come back running, the stopped one
  stays stopped, and `sudo iptables -S AMAHI-APPS` lists the rules again.

## 8. Optional: a port that's taken

- [ ] Uninstall Uptime Kuma and delete its data. In a second terminal on the NAS, keep port 3001
  busy:

  ```bash
  python3 -m http.server 3001
  ```

  Install Uptime Kuma: the window says "Port 3001 is in use, so it gets port 3002", its row says
  **Port 3002**, and Open goes there. Stop the test server with Ctrl+C.

---

## If something fails

Send Claude what the page showed, and the output of these (each on its own):

```bash
sudo tail -n 40 /var/log/amahi-kai/helper.log
```

```bash
journalctl -u amahi-kai-app-firewall -n 20 --no-pager
```

```bash
sudo docker logs --tail 40 amahi-<app>
```

(`amahi-uptimekuma`, `amahi-jellyfin`, and so on.)
