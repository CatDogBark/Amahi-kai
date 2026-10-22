# Networking: modernized, and tested without losing the house's internet

Status 2026-10-22: a plan, nothing built yet. CatDogBark wants Amahi-kai's networking modernized,
with secure DNS among other things, to carry over what original Amahi users did with their home
server: put it in front of the network. Until it's been tested as below, the parts that aren't
ready ship labelled "in development" and stay off. That may still include 1.0.

## What's there now

Setup → Network, shown in Advanced mode:

- **Leases**: the addresses dnsmasq's DHCP has handed out.
- **Hosts**: fixed addresses. A MAC always gets the same address and name (`dhcp-host=`).
- **Gateway**: installs dnsmasq, and sets the DHCP range, the router, the lease time and whether
  DHCP and DNS are on.
- **DNS aliases**: extra names for addresses (`address=/name/ip`).
- **Settings**: the upstream DNS (Cloudflare, `1.1.1.1` and `1.0.0.1`, by default).

`DnsmasqService` (`lib/dnsmasq_service.rb`) writes the configuration: `dhcp-range`,
`dhcp-authoritative`, a `dhcp-host` line per fixed address, `local=`, `expand-hosts` and `domain=`
for the local names (`home.arpa` since #163). The root helper checks it with `dnsmasq --test`
before installing it (`network.write_dnsmasq_config`).

Remote Access (Cloudflare Tunnel, Tailscale) and the security audit live on the same tab. They're
in use on the NAS and aren't part of this plan.

None of the DHCP and DNS features has been tested end to end; the storage test run didn't cover
them.

## Why it needs care

DHCP and DNS serve the whole house, not just the NAS. Amahi-kai handing out addresses while the
router's DHCP is still on means two DHCP servers, and devices end up with whichever answers first.
Wrong DNS means no internet for every device that uses it. No other feature can do that much
damage, so:

- **Off unless turned on.** A new install's settings say DHCP and DNS are off (the seeds say on
  today, though nothing runs until dnsmasq is installed: change them to off). Existing installs
  keep what they have.
- **Look before turning DHCP on.** Before DHCP starts, Amahi-kai checks the network for another
  DHCP server (a DHCP discover, as `nmap --script broadcast-dhcp-discover` sends). If one answers,
  it refuses and says to turn the router's DHCP off first.
- **A way back from outside.** The page says how to undo it if the NAS is down: turn the router's
  DHCP on again, from the router's own page.
- **Serve one interface.** DHCP and DNS answer on the interface chosen for them, not on every
  interface the server has. That's also what the test lab below needs.

## Modernizing

To settle before building:

- **Encrypted upstream DNS.** Queries to the upstream (Cloudflare, Quad9 and the like) go over
  DNS-over-TLS or DNS-over-HTTPS, so the ISP can't read or change them. dnsmasq can't do either
  itself. The likely shape is Unbound (in Ubuntu) as the DNS server, with DNS-over-TLS forwarding,
  DNSSEC validation and a cache, and dnsmasq kept only for DHCP, telling Unbound the names it
  hands out. The other route is a forwarding proxy in front of dnsmasq.
- **DNSSEC validation**, so forged answers are refused.
- **Blocklists** (ads, trackers, malware), optional, from lists the owner picks, like Pi-hole's.
- **Local names that just work.** Every device that gets an address is reachable as
  `name.home.arpa`, alongside the fixed hosts and the DNS aliases.
- **Tailscale's devices** can use the NAS's DNS (split DNS), so local names work away from home.
- **Later:** IPv6 (router advertisements, DHCPv6), serving DNS-over-HTTPS to browsers, and
  per-device query stats.

## Testing without losing the internet

The house today: the router (with the WAN) → an OpenWrt wireless bridge → the LAN. forge's guests,
the NAS (`192.168.1.111`) and the test VM (`192.168.1.13`) among them, are on `vmbr0`, the LAN.

### 1. A lab on forge that can't touch the house

Everything, DHCP included, is tried here first.

1. In Proxmox: forge → System → Network → Create → Linux Bridge, `vmbr9`, with **no bridge ports
   and no address**. It's an island: nothing on it reaches the LAN or the router.
2. The test VM gets a second network device on `vmbr9` with a fixed address there, say
   `10.99.0.1/24` (netplan). Its first device stays on the LAN, for SSH and its own internet.
3. Amahi-kai on the test VM serves DHCP and DNS on that second device only (the "serve one
   interface" setting above), for `10.99.0.0/24`.
4. A small client VM (an Ubuntu or Alpine cloud image) has its only network device on `vmbr9`.
   It starts with no address and asks for one.
5. Check, with snapshots before each run:
   - the client gets an address from the range, and shows on Leases;
   - a fixed host gets its fixed address;
   - `name.home.arpa`, the DNS aliases and outside names resolve from the client. The test VM
     forwards upstream through its LAN device, so the client needs no internet of its own;
   - DNSSEC: a deliberately broken domain (such as `dnssec-failed.org`) is refused;
   - with encrypted upstream DNS on, nothing leaves the test VM on port 53 (`tcpdump`);
   - the DHCP check finds a second DHCP server put on the island (a dnsmasq on the client) and
     refuses to start;
   - turning it all off leaves the client unable to renew. That's the expected result on the
     island; on the house LAN the router takes over again.

### 2. DNS on the house LAN, one device at a time

DNS can be tried without touching DHCP or the router: set one computer's DNS server to the NAS
by hand. If something breaks, set that one computer back. Nothing else in the house notices.

### 3. The cut-over, last

DHCP for the house only after the lab and the single-device DNS pass, with the way back written
down first. The main router's DHCP is turned off in its own admin page (the OpenWrt bridge passes
DHCP along and isn't where it's changed); turning it on again undoes everything.
