# The container engine

Amahi-kai runs its apps with Docker Engine (Docker's own packages for Ubuntu, `docker-ce`). Every
command Docker is given, and everything Amahi-kai reads back from it, is in one part of the root
helper: [`libexec/amahi-helper.d/engine.rb`](../libexec/amahi-helper.d/engine.rb). The apps part
(`apps.rb`) decides what each container gets (its user, memory, ports, folders, shares, DNS); the
engine part only says it in Docker's words. `spec/lib/amahi_helper_engine_spec.rb` fails if any
other part of the helper names Docker, runs it, or spells one of its flags.

This is so the engine can change, in Amahi-kai or in a fork for another distribution, without
going through the whole helper. Another engine (Podman, say) replaces `engine.rb`, keeping its
methods and what they return. Its header lists the parts of `docker inspect` the rest of the
helper reads.

## The other places that know about Docker

Outside the engine part, these are tied to Docker and would change with it:

| Where | What |
| --- | --- |
| `libexec/amahi-helper.d/core.rb` (`APT_SOURCES['docker']`) | Docker's apt repository and its signing key's fingerprints |
| `libexec/amahi-helper.d/system.rb` (the package list) | `docker-ce`, `docker-ce-cli`, `containerd.io` as packages the helper may install |
| `libexec/amahi-helper.d/apps.rb` (`do_app_firewall`) | The app firewall hangs off the chain Docker leaves for it (`ENGINE_FIREWALL_HOOK`): Docker publishes ports with its own rules, ahead of UFW's |
| `lib/docker_service.rb`, `lib/system_services.rb` | Whether Docker is installed and running (its packages, its `docker` service) |
| `lib/network_interfaces.rb`, `lib/dns_service.rb` | Docker's bridge (`docker0`), where Unbound answers the apps |
| `lib/security_audit.rb` | The check that no app port is open past the firewall |
| `config/systemd/amahi-kai-app-firewall*.service`, `amahi-kai-app-shares.service` | Ordered around `docker.service` |
| `bin/amahi-install-helper`, `bin/amahi-install` | Keep the app's account out of the `docker` group (that group is root's equal) |
| `bin/amahi-update` | Moves the apps' share mounts when Docker is there |

The web app never talks to Docker: it asks the helper (`apps.*`), and names in it like `DockerApp`
are only names. App images come from container registries (`lib/app_versions.rb` reads Docker Hub
and GitHub's), which any engine can pull from.
