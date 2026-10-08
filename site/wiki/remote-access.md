---
layout: default
title: "Remote Access"
---

# Remote Access

Amahi-kai can be reached from outside your home two ways, both set up from **Network → Remote
Access** (Advanced mode):

- **[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/):**
  a public address like `https://home.yourdomain.com`, with no ports opened on your router. Your
  server connects out to Cloudflare, and Cloudflare passes visitors through.
- **[Tailscale](https://tailscale.com/):** a private network between your own devices. Nothing is
  public; your phone or laptop reaches the server as if it were on your LAN.

You can use either or both.

---

## Cloudflare Tunnel

### Before you start

1. A Cloudflare account (the free plan works) and a domain managed by Cloudflare.
2. **No security blockers.** Run the [Security](security) audit first: Amahi-kai refuses to set
   up or start the tunnel while the audit reports a blocker (stopping it is always allowed).

### Create the tunnel in Cloudflare

1. In the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/), go to
   **Networks → Tunnels** and click **Create a tunnel**.
2. Choose **Cloudflared**, and name it (for example, "amahi-home").
3. **Copy the tunnel token.**
4. Add a public hostname: pick a subdomain (for example `home`) and your domain, and set the
   service to `http://localhost:3000`.

### Connect Amahi-kai

1. On **Network → Remote Access**, paste the token and click **Setup Tunnel**.
2. The progress window shows Amahi-kai installing `cloudflared` (if needed), saving the token,
   and starting the tunnel.

Your server is then at `https://home.yourdomain.com`. No other setting is needed: requests through
the tunnel come from the server itself, so Amahi-kai accepts them for any hostname you route to
it.

The token is saved in `/etc/amahi-kai/tunnel.token`, which only root can read, and `cloudflared`
reads it from there. It isn't kept in a service file or shown on a command line.

### Protect the hostname

Anyone who knows the address reaches your login page. Put
[Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/) in front of the
hostname so only you get through (for example, a one-time code sent to your email address). This
is set up in the Cloudflare dashboard; Amahi-kai doesn't need to know about it.

### Managing the tunnel

The Remote Access page shows whether `cloudflared` is installed and connected, and since when.
**Start**, **Stop** and **Restart** show their progress and result. From the command line:

```bash
systemctl status cloudflared        # is it running
sudo systemctl restart cloudflared  # restart it
journalctl -u cloudflared -f        # follow its log
```

### Docker apps through the tunnel

Installed apps open under the same hostname through Amahi-kai's links:

```
https://home.yourdomain.com/app/jellyfin
```

Apps that don't work under a path (see [Docker Apps](docker-apps)) can get a hostname of their
own: add another public hostname in the tunnel pointing at the app's port, for example
`http://localhost:8096`.

### Removing the tunnel

Stop it on the Remote Access page, then delete the tunnel in the Cloudflare dashboard. To remove
it from the server completely:

```bash
sudo systemctl disable --now cloudflared
sudo rm -f /etc/systemd/system/cloudflared.service /etc/amahi-kai/tunnel.token
sudo systemctl daemon-reload
```

### Troubleshooting

- **Tunnel won't connect:** `journalctl -u cloudflared -n 30 --no-pager` usually says why (an
  expired or mistyped token, for example). Paste a new token with **Setup Tunnel**.
- **"Bad gateway":** Amahi-kai isn't answering. Check `systemctl is-active amahi-kai`, and that the
  tunnel's hostname points at `http://localhost:3000`.

---

## Tailscale

1. On **Network → Remote Access**, click **Install Tailscale** and watch the progress.
2. Click **Start**. The first time, the page shows a link to log in to Tailscale and approve the
   server; open it and sign in.
3. Install Tailscale on your phone or laptop and sign in to the same account.

The server then shows up in your tailnet with a name like `amahi-kai.tail1234.ts.net`. Amahi-kai
recognizes that name automatically, and Samba accepts connections from your tailnet, so the web
UI and your shares work from anywhere your devices are signed in.

**Stop** disconnects; **Log out** removes the server from your tailnet.

If you already reach your LAN through another device's Tailscale subnet route, you don't need
Tailscale on the server itself.
