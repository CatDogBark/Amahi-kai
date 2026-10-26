---
layout: default
title: "Security"
---

# Security

Amahi-kai includes a security audit that checks the server's configuration and can fix most of
what it finds. Run it before turning on [Remote Access](remote-access): the tunnel won't start
while the audit reports a blocker.

---

## Security Audit

Go to **Network → Security** (Advanced mode) and run the audit. Each check is one of:

| Result | Meaning |
|--------|---------|
| **Pass** | Configured securely |
| **Warning** | Worth fixing, but not blocking |
| **Blocker** | Must be fixed before remote access can be turned on |

### Checks

| Check | Severity | What it looks at |
|-------|----------|------------------|
| Admin password changed | Blocker | The `admin` account no longer has the first password the installer printed |
| UFW firewall active | Blocker | UFW is turned on |
| Samba answers only the LAN | Blocker | Samba lets in only the NAS itself, the LAN and Tailscale, and never sits on the router's internet side |
| SSH root login disabled | Warning | Root can't log in over SSH |
| SSH password login disabled | Warning | SSH accepts keys only |
| Fail2ban | Warning | Repeated failed SSH logins get blocked |
| Security updates | Warning | No security update has waited more than a week (Settings → System Dependencies installs them) |
| Automatic security updates | Warning | Ubuntu installs security fixes by itself while the NAS is the router (off is your choice otherwise; the switch is on Settings → System Dependencies) |
| Docker ports | Warning | Lists Docker app ports reachable from the network (see below) |
| Open ports | Info | Lists the ports the server listens on |

The SSH checks read SSH's *effective* settings (`sshd -T`), so a setting in a drop-in file under
`/etc/ssh/sshd_config.d/` counts, as it does for SSH itself.

---

## Fixing issues

Click **Fix All**, or a check's own **Fix** button. The progress streams as it runs.

- **Firewall:** turns on UFW with Amahi-kai's rules: SSH, the web UI (3000), HTTPS and Samba,
  plus DHCP when Amahi-kai runs dnsmasq for your network, and DNS to the NAS's DNS addresses while
  Network → DNS is on. Nothing on the NAS serves HTTPS yet (it comes after 1.0), so its port is
  open with nothing behind it; apps' ports are Docker's and limited to the LAN and Tailscale (see
  below).
- **SSH:** turns off root login and password login. **Password login is only turned off once an
  account that can log in has an SSH key**, so the fix can't lock you out. Set up a key first
  (below).
- **Fail2ban:** installs it; its SSH jail is on by default.
- **Samba's allow list:** Amahi-kai generates Samba's configuration with its allow list built in
  (the NAS itself, the LAN and Tailscale; everyone else is turned away when they connect), so this
  passes on its own unless the configuration was edited by hand. Samba listens on every address,
  because Tailscale's IPv4 address is one it can't be bound to; the list is what keeps others out,
  and in router mode the firewall drops the internet side before Samba sees it.

Not fixed automatically:

- **Admin password:** change it on the Users page (the setup wizard requires it too).
- **Security updates:** install them on Settings → System Dependencies, when you choose to. Nothing
  updates by itself unless you turn automatic updates on there.
- **Docker ports and open ports:** informational; close anything you don't expect.

### Docker and the firewall

Docker writes its own firewall rules for the ports its apps publish, ahead of UFW's, so UFW
doesn't filter them. Amahi-kai adds rules of its own in Docker's chain (`AMAHI-APPS`, each time
Docker starts) so that app ports are reachable from the server's LAN and Tailscale only. The
**Docker ports** check passes when those rules are in place, and warns about published ports
when they aren't (for example, containers started outside Amahi-kai while its rules are missing).

### Setting up an SSH key

```bash
# On your computer (once)
ssh-keygen -t ed25519

# Copy it to your account on the server, then check it works
ssh-copy-id youruser@<server-ip>
ssh youruser@<server-ip>
```

Then run the SSH fix.

---

## How Amahi-kai uses root

The web app runs as its own user, `amahi`, not as root.

- **One root helper.** Everything that needs root (user and Samba accounts, Samba's
  configuration, share folders, services, drives, Greyhole, package installs, the tunnel,
  Tailscale, the audit's fixes, updates, Docker apps) goes through `/usr/local/sbin/amahi-helper`. It accepts
  a fixed list of operations, checks every request itself, and logs each one to
  `/var/log/amahi-kai/helper.log` (passwords and tokens are filtered out).
- **Sudo is limited** to the helper. You can see the rule with `sudo -l -U amahi`.
- **Root owns the code** in `/opt/amahi-kai`, so the web app can't change what root runs.
- **Secrets stay private.** Passwords and the tunnel token are never put on a command line or in
  a log; the tunnel token is in a file only root can read.

Docker apps are installed only through the helper, from Amahi-kai's own catalog: the web app names
an app and the helper builds its container from the app's definition, as the app's own user. The
`amahi` user isn't in the `docker` group (that would be full control of the machine). Docker
itself is still root-level software, so only install apps you trust.

---

## Logins and sessions

- Passwords are stored with bcrypt.
- With **Remember me** ticked, a sign-in lasts until 7 days without use; without it, until the
  browser closes or 12 hours without use. Either way it ends 30 days after it was made.
- **Signing out** signs that account out on every browser. Changing your password signs you out
  everywhere else.
- Sign-in attempts are limited: 5 in 20 seconds from one address, 10 a minute for one login name.
  An address with 20 wrong passwords in an hour can't sign in for the rest of that hour.
- Through the Cloudflare Tunnel, the sign-in cookie is sent over HTTPS only.
- Pages that change the system only accept requests from Amahi-kai's own pages (CSRF protection,
  POST-only actions).
- Amahi-kai only answers to its own addresses (IP, host name, Tailscale name and any names you
  add), which blocks DNS-rebinding tricks. Its names as they are now count too: a new server
  name, its name in the NAS's DNS (`nas.home.arpa`) and the DNS aliases that point at it work
  without a restart.

---

## Best practices

1. Run the security audit and clear the blockers before turning on remote access.
2. Put [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/) in
   front of your tunnel hostname (for example, a one-time code sent to your email).
3. Use SSH keys instead of passwords.
4. Install updates when Amahi-kai says one is waiting (see [Updating](updating)).
5. Keep Samba on the LAN; don't forward its ports on your router.
6. Keep copies of what Amahi-kai doesn't back up: its settings, and shares on the system disk
   ([what to keep](getting-started#what-amahi-kai-doesnt-back-up)).
