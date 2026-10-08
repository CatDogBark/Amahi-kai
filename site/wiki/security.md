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

Go to **Network > Security** (Advanced mode) and run the audit. Each check is one of:

| Result | Meaning |
|--------|---------|
| **Pass** | Configured securely |
| **Warning** | Worth fixing, but not blocking |
| **Blocker** | Must be fixed before remote access can be turned on |

### Checks

| Check | Severity | What it looks at |
|-------|----------|------------------|
| Admin password changed | Blocker | The `admin` account no longer accepts the default password |
| UFW firewall active | Blocker | UFW is turned on |
| Samba bound to LAN | Blocker | Samba only listens on the LAN (and Tailscale) |
| SSH root login disabled | Warning | Root can't log in over SSH |
| SSH password login disabled | Warning | SSH accepts keys only |
| Fail2ban | Warning | Repeated failed SSH logins get blocked |
| Security updates | Warning | No security update has waited more than a week (Settings → System Dependencies installs them) |
| Docker ports | Warning | Lists Docker app ports reachable from the network (see below) |
| Open ports | Info | Lists the ports the server listens on |

The SSH checks read SSH's *effective* settings (`sshd -T`), so a setting in a drop-in file under
`/etc/ssh/sshd_config.d/` counts, as it does for SSH itself.

---

## Fixing issues

Click **Fix All**, or a check's own **Fix** button. The progress streams as it runs.

- **Firewall:** turns on UFW with Amahi-kai's rules: SSH, the web UI (3000), HTTPS and Samba,
  plus DNS and DHCP when Amahi-kai runs dnsmasq for your network.
- **SSH:** turns off root login and password login. **Password login is only turned off once an
  account that can log in has an SSH key**, so the fix can't lock you out. Set up a key first
  (below).
- **Fail2ban:** installs it; its SSH jail is on by default.
- **Samba binding:** Amahi-kai generates Samba's configuration with the LAN binding built in, so
  this passes on its own unless the configuration was edited by hand.

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
- Sessions end after 7 days without use. Changing your password signs you out everywhere else.
- Login attempts are rate-limited per address and per username.
- Pages that change the system only accept requests from Amahi-kai's own pages (CSRF protection,
  POST-only actions).
- Amahi-kai only answers to its own addresses (IP, host name, Tailscale name and any names you
  add), which blocks DNS-rebinding tricks.

---

## Best practices

1. Run the security audit and clear the blockers before turning on remote access.
2. Put [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/) in
   front of your tunnel hostname (for example, a one-time code sent to your email).
3. Use SSH keys instead of passwords.
4. Install updates when Amahi-kai says one is waiting (see [Updating](updating)).
5. Keep Samba on the LAN; don't forward its ports on your router.
6. Back up `/etc/amahi-kai/amahi.env` and your app data (`/var/lib/amahi-kai/apps/`).
