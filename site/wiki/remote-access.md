---
layout: default
title: "Remote Access"
---

# Remote Access

Amahi-kai uses [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to securely expose your home server to the internet without opening ports on your router. Traffic flows through Cloudflare's network, and your server connects outbound — no inbound firewall rules needed.

---

## Prerequisites

Before setting up remote access:

1. **A Cloudflare account** (free tier works)
2. **A domain name** added to Cloudflare (can be a cheap domain — Cloudflare manages DNS)
3. **Pass the security audit** — Amahi-kai requires no security blockers before enabling remote access

> The Remote Access page in the web UI shows any security blockers that must be resolved first. See [Security](security) for details.

---

## Setup (Web UI)

The entire setup is done from the web UI:

1. Navigate to **Network > Remote Access** (requires Advanced mode)
2. If `cloudflared` isn't installed, click **Install cloudflared** — the web UI streams the installation

### Creating a Tunnel in Cloudflare Dashboard

1. Log in to the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/)
2. Go to **Networks > Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector type
5. Name your tunnel (e.g., "amahi-home")
6. **Copy the tunnel token** — you'll need this in the next step
7. Add a public hostname:
   - **Subdomain**: e.g., `home` (or whatever you want)
   - **Domain**: Select your Cloudflare domain
   - **Service**: `http://localhost:3000`

### Entering the Token in Amahi-kai

1. Back in the Amahi-kai web UI, paste the tunnel token
2. Click **Setup Tunnel**
3. Watch the streaming progress as it:
   - Installs `cloudflared` (if not already installed)
   - Saves the token securely to `/etc/amahi-kai/tunnel.token`
   - Creates a systemd service at `/etc/systemd/system/cloudflared.service`
   - Enables and starts the tunnel

Once connected, your server is accessible at `https://home.yourdomain.com` (or whatever hostname you configured).

---

## How It Works

The `cloudflared` daemon runs as a systemd service that:

1. Connects outbound to Cloudflare's edge network
2. Establishes a persistent tunnel using your token
3. Cloudflare routes incoming HTTPS requests to your tunnel
4. The tunnel forwards requests to `http://localhost:3000` (Amahi-kai's Puma server)

The systemd unit file:

```ini
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token <your-token>
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### Allowed Hosts

If you've set a domain for remote access, add it to `/etc/amahi-kai/amahi.env`:

```bash
RAILS_ALLOWED_HOST=home.yourdomain.com
```

Then restart Amahi-kai:

```bash
sudo systemctl restart amahi-kai
```

This allows Rails to accept requests from that hostname (Rails 8 blocks unknown hosts by default).

---

## Managing the Tunnel

### Web UI Controls

The Remote Access page shows:
- **Installed**: Whether `cloudflared` is installed
- **Running**: Whether the tunnel is active
- **Connected since**: Timestamp of the current connection
- **Token configured**: Whether a tunnel token is saved

You can **Start** or **Stop** the tunnel from the web UI.

### CLI Commands

```bash
# Check tunnel status
systemctl status cloudflared

# Start/stop/restart
sudo systemctl start cloudflared
sudo systemctl stop cloudflared
sudo systemctl restart cloudflared

# View tunnel logs
journalctl -u cloudflared -f

# Check if cloudflared is installed
cloudflared --version
```

---

## Exposing Docker Apps

When you access Docker apps through the tunnel, they work via Amahi-kai's reverse proxy:

```
https://home.yourdomain.com/app/jellyfin
https://home.yourdomain.com/app/gitea
https://home.yourdomain.com/app/filebrowser
```

For apps that need their own subdomain (Nextcloud, Vaultwarden, etc.), add additional public hostnames in the Cloudflare dashboard pointing to the app's port:

| Hostname | Service |
|----------|---------|
| `home.yourdomain.com` | `http://localhost:3000` |
| `nextcloud.yourdomain.com` | `https://localhost:8443` |
| `vault.yourdomain.com` | `http://localhost:8880` |

---

## Security Considerations

- Cloudflare Tunnel encrypts all traffic end-to-end
- Your server never exposes ports to the internet
- The tunnel token is stored at `/etc/amahi-kai/tunnel.token` with restricted permissions
- Amahi-kai requires login for all pages — unauthenticated users are redirected to the login screen
- Run the [Security Audit](security) before enabling remote access

---

## Troubleshooting

### Tunnel won't connect

```bash
# Check the service
journalctl -u cloudflared -n 20 --no-pager

# Verify the token is saved
ls -la /etc/amahi-kai/tunnel.token

# Test cloudflared manually
cloudflared tunnel --no-autoupdate run --token $(cat /etc/amahi-kai/tunnel.token)
```

### "Bad Gateway" or connection errors

- Verify Amahi-kai is running: `systemctl is-active amahi-kai`
- Check that port 3000 is listening: `ss -tlnp | grep 3000`
- Verify the Cloudflare tunnel hostname points to `http://localhost:3000`

### Removing the tunnel

```bash
sudo systemctl stop cloudflared
sudo systemctl disable cloudflared
sudo rm -f /etc/systemd/system/cloudflared.service
sudo systemctl daemon-reload
sudo rm -f /etc/amahi-kai/tunnel.token
```

Then delete the tunnel in the Cloudflare Zero Trust dashboard.
