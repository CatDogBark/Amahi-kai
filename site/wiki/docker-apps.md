---
layout: default
title: "Docker Apps"
---

# Docker Apps

Amahi-kai includes a built-in Docker app catalog. You can install, start, stop, and uninstall containerized apps directly from the web UI. Each app gets a reverse proxy path at `/app/<identifier>`, so you access everything through the Amahi-kai web UI without remembering port numbers.

---

## Prerequisites

Docker is **not** installed by default. Install it from the web UI:

1. Go to the **Apps** tab
2. Click **Install Docker**
3. Watch the streamed installation progress

Amahi-kai's root helper adds Docker's official apt repository (its signing key is checked
against a pinned fingerprint), installs Docker, lets the `amahi` user manage it, and turns the
service on.

> Access to Docker is full control of the server: a container can be given any file or device.
> Only install apps you trust.

---

## App Catalog

The app catalog is defined in `config/docker_apps/catalog.yml`. Currently available apps:

### Productivity
| App | Description |
|-----|-------------|
| **Nextcloud** | File sync, sharing, and collaboration platform |
| **Vaultwarden** | Lightweight Bitwarden-compatible password manager |
| **Paperless-ngx** | Document management and OCR scanning |

### Media
| App | Description |
|-----|-------------|
| **Jellyfin** | Free media server for movies, TV, and music |
| **Transmission** | Lightweight BitTorrent client with web UI |
| **Audiobookshelf** | Audiobook and podcast server |

### Storage
| App | Description |
|-----|-------------|
| **Syncthing** | Peer-to-peer file synchronization |

Browsing and managing share files from the web is built in: see the file browser on
[File Sharing](file-sharing).

### Networking
| App | Description |
|-----|-------------|
| **Pi-hole** | Network-wide DNS ad blocker |
| **Home Assistant** | Smart home automation platform |

### Monitoring
| App | Description |
|-----|-------------|
| **Uptime Kuma** | Self-hosted service monitoring |
| **Grafana** | Analytics and visualization dashboards |

### Development
| App | Description |
|-----|-------------|
| **Gitea** | Lightweight self-hosted Git service |
| **Portainer** | Docker container management UI |

---

## Installing an App

1. Go to **Apps** tab and click **App Catalog**
2. Browse by category or find your app
3. Click **Install**
4. Watch the streaming terminal as it:
   - Creates config files (if the app needs them)
   - Creates volume directories with appropriate permissions
   - Pulls the Docker image
   - Creates and starts the container

Once installed, the app appears on the **Installed Apps** page and (if configured) on the dashboard.

### What Happens Under the Hood

For each app, Amahi-kai:

1. Creates a `DockerApp` database record tracking status, ports, and volumes
2. Creates host directories for volume mounts (at `/opt/amahi/apps/<identifier>/`)
3. Writes any `init_files` (config files the app needs before first boot)
4. Pulls the Docker image
5. Creates the container with:
   - Name: `amahi-<identifier>`
   - Port mappings from the catalog
   - Volume mounts from the catalog
   - Environment variables from the catalog
   - Restart policy: `unless-stopped`
   - Labels: `amahi.managed=true`, `amahi.app=<identifier>`
6. Starts the container

---

## Accessing Apps

Every installed app is accessible through the built-in reverse proxy at:

```
http://<your-server-ip>:3000/app/<identifier>
```

For example:
- Jellyfin: `http://192.168.1.10:3000/app/jellyfin`
- Gitea: `http://192.168.1.10:3000/app/gitea`
- Grafana: `http://192.168.1.10:3000/app/grafana`

The reverse proxy handles:
- Path rewriting (so apps work under `/app/<name>` paths)
- Header forwarding (`X-Forwarded-For`, `X-Forwarded-Proto`, `X-Real-IP`)
- HTML rewriting for root-absolute paths in app responses
- Cookie path rewriting
- Location header rewriting for redirects
- HTTPS upstream detection (for apps like Nextcloud and Portainer that use internal SSL)
- MIME type correction

### App Compatibility

Most apps work fully through the built-in reverse proxy at `/app/<name>`. Some apps have limitations:

| Status | Apps |
|--------|------|
| **Works fully** | Jellyfin, Grafana, Transmission, Gitea, Syncthing, Pi-hole, Paperless-ngx, Audiobookshelf |
| **Limited** | Nextcloud, Portainer, Home Assistant, Vaultwarden, Uptime Kuma |

**Limited apps** are ones that hardcode absolute URLs, require WebSocket connections on their own hostname, or refuse to run under a sub-path. After installing a limited app, you'll see a notification explaining that it may need direct port access or a dedicated hostname to work fully.

We're actively improving proxy compatibility to support more apps. There are **no plans for multi-container (docker-compose) support** — Amahi-kai runs single-container apps only, keeping things simple and predictable.

---

## Managing Apps

### Start / Stop / Restart

From the **Installed Apps** page, use the control buttons for each app:

```bash
# Or from the command line:
sudo docker start amahi-jellyfin
sudo docker stop amahi-jellyfin
sudo docker restart amahi-jellyfin
```

### Uninstalling

Click **Uninstall** in the web UI. This:
- Stops the container (with a 30-second timeout)
- Removes the container and its anonymous volumes
- Prunes unused Docker images
- Removes the app's host directory (`/opt/amahi/apps/<identifier>/`)
- Resets the database record to `available`

### Checking Status

The web UI shows real-time status. From the CLI:

```bash
sudo docker ps                          # Running containers
sudo docker inspect amahi-jellyfin      # Detailed container info
sudo docker logs amahi-jellyfin         # Container logs
sudo docker logs -f amahi-jellyfin      # Follow logs
```

---

## App Data Storage

Each app stores its data under `/opt/amahi/apps/<identifier>/`. For example:

```
/opt/amahi/apps/
  jellyfin/
    config/
    cache/
  nextcloud/
    config/
    data/
  gitea/
    data/
```

Media apps also mount share folders; for instance, Jellyfin mounts `/opt/amahi/media`.

### App ports and the firewall

Docker writes its own firewall rules for the ports apps publish, ahead of UFW's, so an app's port
is reachable from your LAN even with UFW on. The [security audit](security) lists them. Apps you
only open through `/app/<name>` don't need their ports reachable.

### Backing Up App Data

To back up a Docker app's data:

```bash
# Stop the app first
sudo docker stop amahi-jellyfin

# Copy the data directory
sudo cp -a /opt/amahi/apps/jellyfin /path/to/backup/

# Restart
sudo docker start amahi-jellyfin
```

---

## Troubleshooting

### App shows "Cannot connect"

- Check if the container is running: `sudo docker ps | grep amahi-<app>`
- Check container logs: `sudo docker logs amahi-<app>`
- Verify the port mapping: `sudo docker port amahi-<app>`

### App returns blank page or broken CSS

This usually means the reverse proxy path rewriting isn't matching the app's expectations. Check:
- Whether the app supports running under a sub-path
- The `preserve_prefix` setting in `catalog.yml` (for apps like Grafana that handle their own sub-paths)

### Container won't start after reboot

Containers are created with `--restart unless-stopped`, so they should auto-start. If not:

```bash
sudo docker start amahi-<app>
# Or check why it failed:
sudo docker logs amahi-<app>
```

### Reinstalling a broken app

Uninstall the app from the web UI, then install it again. This creates a fresh container. If you want to preserve data, back up `/opt/amahi/apps/<identifier>/` before uninstalling.
