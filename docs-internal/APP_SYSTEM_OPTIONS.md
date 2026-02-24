# App System Options

The old Amahi app system is **dead** — it depends on AmahiApi servers that no longer exist.
We need a replacement. Here are the options:

## Option A: Docker-Based Apps (Recommended)

**How it works:** Each app is a Docker container. The UI shows available apps from a local
catalog (YAML/JSON file or git repo). Install = `docker pull` + `docker run`. Uninstall = 
`docker stop` + `docker rm`.

**Pros:**
- Apps are isolated (can't break the host)
- Huge existing ecosystem (Linuxserver.io, selfhosted apps)
- Easy to add new apps (just a docker-compose snippet)
- No dependency conflicts between apps
- Already have `docker-api` gem in Gemfile + Container class in lib/

**Cons:**
- Requires Docker on the host
- More resource overhead than native packages
- Network/storage config more complex (reverse proxy needed)

**Architecture:**
```
apps/catalog.yml          # App definitions (image, ports, volumes, env)
lib/container.rb          # Already exists — needs expansion
app/models/app.rb         # Refactor to use Docker instead of AmahiApi
Traefik/Caddy             # Reverse proxy for app.hda URLs
```

## Option B: Native Package Manager (apt)

**How it works:** Apps are `.deb` packages or PPAs. Install = `apt install`. 

**Pros:**
- Lightweight, no Docker overhead
- Tight system integration

**Cons:**
- Dependency hell
- Need to maintain packages or rely on third-party PPAs
- Apps can conflict with each other
- Much harder to distribute custom apps
- Security risk (apps run on host)

## Option C: Hybrid (Docker + a few native)

Docker for most apps, native packages for things that need bare-metal access
(like Samba, which is already native). This is probably the pragmatic choice.

## Recommendation

**Go Docker-first (Option A/C).** The Container class already exists. The ecosystem
is huge. We can ship a curated catalog of popular self-hosted apps and let users
add custom ones. A reverse proxy (Traefik or Caddy) handles routing `app.hda` URLs
to containers.

## What This Looks Like

1. Replace AmahiApi with a local app catalog (YAML file, maybe a git repo)
2. Expand Container class to handle full lifecycle (create, start, stop, remove, logs, update)
3. Add Traefik/Caddy as the reverse proxy (runs as a container itself)
4. Refactor the Apps plugin UI to show Docker-based apps
5. Keep the progress bar UX — docker pull progress maps nicely to it
