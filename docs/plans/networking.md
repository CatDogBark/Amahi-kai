# Networking: modernized, private, and tested without losing the house's internet

Status 2026-10-22: the island is built. Slice 1 (DNS) is on `dev` and passed its island checks
(from the client over IPv4 and IPv6, `tcpdump` showing lookups leave on 853 only, UFW's rules
following the interface). Slice 2 (DHCP) is on `dev` and passed too: the client got an address,
the NAS as DNS server and `home.arpa`; its name followed its lease in and out of DNS; a fixed
host got its address; a second DHCP server on the island was named and refused; and the way back
stopped dnsmasq, the watcher and the names while DNS kept answering. The island found two bugs,
both fixed (the lease watcher never fired; the check stopped listening before dnsmasq's offers
came). Slice 3 (blocklists) is on `dev` and passed too: the default lists downloaded and built in 8
seconds (326,252 domains, 155 MB for Unbound), blocked names and their subdomains answered
`0.0.0.0` and `::`, the allowlist let a domain through, a pause let everything through and
resumed by itself after five minutes, and off removed the blocklist and its timer. Slice 4 (IPv6)
is on `dev` and passed too: with no router on the island the check said so; announcing put the
NAS's own address up, and the client heard RDNSS, DNSSL and the range (router lifetime 0), took
an address in it and asked the NAS over IPv6; a second announcer on the client was listed and
warned about, the NAS's own left out; and the way back took radvd, the address and (after a fix:
the config was written before the address left the interface) Unbound's use of it away. Slice 5
(totals) is on `dev` and passed: after lookups from the client, the page showed them, how many
the NAS answered itself, and DNSSEC's checked answers and the one forged one refused. All five
slices are built and tried on the island. Then, with all of it on (DNS + DHCP, blocking,
announcing) and UFW turned on, through the firewall: the client's lease, DNS over IPv4 and IPv6,
blocking and names all worked, and other ports were dropped; and after a reboot of the test VM
every piece came back and worked again from scratch. One more find: the test VM had kept a route
for the announced range on `lo` (left from the bug fixed in `0aee8c1`, we think; it couldn't be
reproduced), which sent replies to devices in the range back into the NAS; the address unit now
clears such a route before it starts. A one-device test on the house LAN adds little over the
island; what's left is the house (below), and Tailscale's answers on the NAS. CatDogBark wants Amahi-kai's networking modernized
for privacy and safety, carrying over what original Amahi users did with their home server: put it
in front of the network. It ships in 1.0, DHCP included, once it passes the tests below.

## Decided (CatDogBark, 2026-10-22)

- **Engine:** Unbound (Ubuntu's package) for DNS; dnsmasq kept only for DHCP. AdGuard Home is
  out of scope.
- **Lookups:** encrypted forwarding to a provider chosen from a list. Every provider on it is open
  and needs no account.
- **Blocklists:** included, with one switch to turn them on and off.
- **DHCP:** ships in 1.0, behind the safety checks below.
- **IPv6:** handled from the start. Most ISPs hand out IPv6, and devices use it for DNS when they
  can.

## What it does

### Three modes

1. **Off** (the default on a new install). Nothing listens.
2. **DNS for my network** (the one to recommend). The NAS is the house's DNS server, and the
   router's own DHCP keeps handing out addresses. The page shows how to point the router's DNS
   setting at the NAS, or a single device's.
3. **DNS + DHCP** (advanced). The NAS also hands out addresses, in place of the router.

### DNS (Unbound)

- **Encrypted lookups:** DNS-over-TLS to the chosen provider, so the ISP can't read or change
  them. The list, with no account needed for any of them:
  - Quad9 (the default: Swiss, no logging, blocks known malware domains)
  - Cloudflare
  - AdGuard DNS (its public, unfiltered service)
  - DNS.SB
  - a custom one: its addresses and TLS name.

  Each provider's IPv4 and IPv6 addresses and TLS name were checked against the provider's own
  page on 2026-10-22, and each answered over TLS on port 853 and validated DNSSEC in a test.
  Mullvad DNS was on the list, but Mullvad shuts its public encrypted DNS down on 2026-11-02
  (its help page says so, and it points people to Quad9).
- **DNSSEC:** answers are checked, and forged ones refused.
- **A cache**, so repeat lookups are fast and fewer leave the house.
- **Local names:** `name.home.arpa` for the fixed hosts, the DNS aliases and, with DHCP on, every
  device that gets an address.
- **Blocklists** (one switch): ads, trackers and malware, from lists the owner picks, with sensible
  ones ticked; an allowlist; and "pause blocking for 5 minutes" for when a site breaks. Lists
  refresh daily.
- **Private by default:** no record of which device looked up what. The page shows totals only:
  lookups, how many the NAS answered itself (its cache, its names and its blocklist), and DNSSEC's
  checked and refused answers, since Unbound's counters last started. Not how many lookups were
  blocked: Unbound counts blocklist answers as cache hits, and only a response policy zone (RPZ)
  counts them apart. Measured with the default lists on Unbound 1.19, RPZ took 419 MB and 5.2
  seconds to start against local zones' 155 MB and 1.4 seconds, and 5.4 seconds to reload the
  lists against under 0.2; logging each block would record names and devices. The page shows how
  many domains are blocked instead.
- **Firefox's own encrypted DNS** is turned off for the network with its standard signal (the
  `use-application-dns.net` canary domain), so Firefox uses the house's DNS. Other devices and
  browsers that ignore the house's DNS need the router's firewall; the page says so.

### Safety

- **Answers the LAN and Tailscale only**, never the internet: the firewall (UFW) opens port 53 to
  those networks alone, and Unbound refuses everyone else too.
- **DNS rebinding protection:** a public name can't resolve to an address inside the house (a known
  way for websites to attack home devices). Local names are exempt.
- **Before DHCP starts,** the NAS checks the network for another DHCP server (a DHCP discover) and
  refuses while one answers, saying to turn the router's DHCP off first.
- **A way back:** the page says how to undo it if the NAS is down: point the router's DNS back at
  itself, or turn the router's DHCP on again.
- **One interface:** DNS and DHCP serve the interface chosen for them, not every interface the
  server has.
- **If the NAS is down, so is DNS** for every device that uses it. The page explains the trade-off
  of a second DNS server on the router: a backup, but devices then use either one, which bypasses
  the blocking and the privacy whenever they pick the router's.

### IPv6

- **Unbound listens on IPv6 too**, at a stable address: a ULA (`fd…`) the NAS keeps whatever
  prefix the ISP hands out today. The ISP's prefix can change, and the DNS address mustn't.
- **Devices must learn that address,** or they keep asking the router's IPv6 DNS and go around the
  NAS. In order of preference:
  1. The router advertises the NAS's address as its IPv6 DNS server (OpenWrt can; many ISP
     routers can't).
  2. The router stops advertising an IPv6 DNS server, so devices use the IPv4 one (the NAS).
  3. The NAS advertises itself (router advertisements carrying a DNS server, `RDNSS`) next to the
     router's. That's an advanced option, since two advertisers can confuse some devices.
- **The page checks** which IPv6 DNS servers the network advertises, and warns when it isn't the
  NAS.
- **DHCPv6** (handing out IPv6 addresses) stays out: the router keeps that, and devices mostly use
  SLAAC anyway.

### DHCP (dnsmasq, DHCP only)

- Its DNS is switched off (`port=0`); it only hands out addresses. Unbound learns the names it
  hands out: Amahi-kai writes them into Unbound's local data and reloads it.
- What's there today stays: the range, the router, the lease time, fixed hosts (MAC → address and
  name), and the lease list.
- Hands out the NAS as the DNS server, and `home.arpa` as the search domain.

### Later

- Tailscale devices using the NAS for DNS (split DNS), so blocklists and local names work away
  from home.
- Serving DNS-over-TLS and DNS-over-HTTPS to devices on the LAN (Android's Private DNS needs a
  certificate for a name; it comes with the HTTPS work on the roadmap).
- Per-device stats, opt-in.

## How it's built

- **Packages:** `unbound` and `dns-root-data` (DNSSEC's root key, which Ubuntu's Unbound copies
  into place when it starts), installed by the helper like the others.
- **The NAS's own lookups don't change:** it keeps asking the server it had (systemd-resolved, and
  the router behind it). If Unbound ever breaks, the NAS can still reach the internet to update
  itself. (Ubuntu's Unbound would register itself with `resolvconf`, but its hook stands down
  when `resolvconf` is systemd's, as on Ubuntu 24.04.)
- **Where Unbound listens:** the addresses of the chosen interface (its IPv4 addresses and its
  ULA), Tailscale's when Tailscale is on, and the NAS's own `127.0.0.1` and `::1`, written as
  addresses with `ip-freebind` so Unbound starts before the network is up. Not `0.0.0.0`:
  systemd-resolved holds `127.0.0.53:53`. The NAS needs a fixed address for this anyway, since
  every device is pointed at it.
- **Who gets answers:** the subnets on the chosen interface (IPv4 and IPv6) and Tailscale's;
  everyone else is refused. UFW lets in port 53 to the listening addresses only.
- **dnsmasq answers no DNS any more** (`port=0`), from the first slice on. The test VM has no
  dnsmasq (checked 2026-10-22); the NAS is checked before it takes the update.
- **Through the helper:** every configuration file is written by the root helper and checked
  before it's installed (`unbound-checkconf`, `dnsmasq --test`), as dnsmasq's is today.
  Blocklists are downloaded by the helper over HTTPS, checked (size, syntax), and turned into
  Unbound `local-zone` entries.
- **Settings:** the mode, the provider, blocklists on and off, the chosen lists, the allowlist,
  the interface, and IPv6 advertising. The page is Setup → Network, reorganized around the three
  modes.
- **New installs** start Off (`dns_mode` off). DHCP is a mode now, so the `dnsmasq_dhcp` switch is
  retired, and Network → Gateway and Network → Settings are folded into Network → DNS & DHCP.
- **DHCP's network** is the chosen interface's /24 (DHCP refuses others), not the `net` setting:
  Samba's `hosts allow` reads `net`, so it isn't changed by picking an interface. Fixed hosts'
  addresses follow the same prefix.
- **The names DHCP hands out:** a systemd path unit (`PathModified`: dnsmasq keeps the file open
  and rewrites it in place, so `PathChanged` never fires) watches dnsmasq's lease file
  (`/var/lib/misc/dnsmasq.leases`; Amahi-kai's Ubuntu path pointed at a folder Ubuntu doesn't
  use) and runs the helper's `dns.sync_leases`. It writes the names to a second Unbound file and
  reloads Unbound with `reload_keep_cache`, only when the names change. Names are one label, on
  IPv4; the NAS, the fixed hosts and the aliases come first. dnsmasq runs no script.
- **Blocklists:** HaGeZi (LIGHT, NORMAL, PRO, Threat Intelligence mini and medium) and OISD
  (small, big), in their domains-only wildcard formats, so a line is a domain that covers its
  subdomains, as Unbound's `local-zone` does. NORMAL and Threat Intelligence mini are ticked
  (about 327,000 domains). StevenBlack is out: it lists exact names, which a `local-zone` would
  widen. URLhaus is out: its download is gone (410) and its terms bar scripts. AdGuard's filter is
  out: adblock syntax only. Checked 2026-10-22.
- **How blocking is built:** each domain becomes `local-zone: "d." always_null` (0.0.0.0 and ::),
  a domain under another listed one is left out, and the allowlist becomes `transparent` zones,
  which win over a blocked parent. Measured on Unbound 1.19: the default lists take about 155 MB
  and start in 1.4 seconds; NORMAL with Threat Intelligence medium (825,000) about 365 MB. At
  most 1,000,000 domains. A reload keeping the cache takes under 200 ms.
- **Where blocking lives:** the helper downloads (HTTPS only, at most 64 MB a list) into a
  root-only folder, `/var/lib/amahi-kai-dns`, with the choice, the status the app reads, and the
  blocklist while paused; not an app-owned folder, since what's there becomes Unbound's config.
  A list that fails keeps its last copy. A timer refreshes daily around 04:00 (lists less than
  20 hours old aren't downloaded again); the whole config is checked before Unbound reloads, and
  the previous blocklist stays if it's refused. Pausing moves the blocklist out, and a transient
  systemd timer runs `dns.resume_blocking` five minutes later.
- **IPv6, as built:** the NAS's own range is a random /48 made once (RFC 4193, kept as
  `dns_ula_prefix`), and its DNS address is `<prefix>::53`. A oneshot unit
  (`amahi-kai-ula.service`) puts it on the interface at boot (`ip -6 addr replace`), not netplan,
  so nothing reconfigures the link. Unbound lists it (with `ip-freebind`) and answers its /64.
  radvd announces RDNSS and DNSSL for it, and the /64 as on-link and autonomous, so devices get an
  address in it and reach the NAS from it, with `AdvDefaultLifetime 0`: never a default router.
  The check sends a router solicitation (hop limit 255) on a raw ICMPv6 socket and reads the
  advertisements for 4 seconds, leaving out the NAS's own. Operation names can't have digits, so
  they're `dns.set_own_address`, `dns.check_routers` and so on.
- **Totals:** the helper's `dns.stats` reads `unbound-control stats_noreset` (with
  `extended-statistics`). A reload starts the counters again but not Unbound's uptime, so the
  helper notes each reload it makes, and the page counts from the later of the two ("34 in about
  1 hour").
- **The check for another DHCP server:** the helper broadcasts a DHCPDISCOVER on the interface
  (from its MAC, asking for broadcast replies) and listens up to 6 seconds for an offer, leaving
  out the NAS's own. Not 3: dnsmasq, which many routers run, pings an address for 3 seconds
  before it offers it (seen on the island: both offers came 3.0 seconds after the discover).
- **Settings replaced:** the old DNS provider choice (`dns`, `dns_ip_1`, `dns_ip_2`) was saved
  but never used by dnsmasq's config; it goes, and `dns_provider` takes its place.

### Build order

Each slice lands on `dev`, passes CI, and is tried on the island before the next starts.

1. **DNS:** Unbound through the helper, the modes Off and "DNS for my network", the provider
   list, DNSSEC, the cache, local names (the NAS, fixed hosts, DNS aliases), rebinding
   protection, Firefox's canary, who gets answers, the firewall, and Network → DNS with a
   working check. dnsmasq stops answering DNS.
2. **DHCP:** the mode "DNS + DHCP", the DHCP settings moved onto the same page, the names
   dnsmasq hands out written into Unbound, the check for another DHCP server, and the way back.
3. **Blocklists:** the switch, the lists, the allowlist, pausing, the daily refresh.
4. **IPv6:** the stable ULA, advertising the DNS server, and the check of what the network
   advertises.
5. **Totals:** lookups, blocked lookups and the cache's hit rate.

## Testing without losing the internet

The house: the main router (the WAN, and its DHCP) → an OpenWrt wireless bridge → the LAN. forge's
guests, the NAS (`192.168.1.111`) and the test VM (`192.168.1.13`) among them, are on `vmbr0`, the
LAN.

### 1. An island on forge

Everything, DHCP and IPv6 included, is tried here first. Nothing on the island reaches the house's
network.

1. **The bridge:** in Proxmox, forge → System → Network → Create → Linux Bridge, `vmbr9`, with
   **no bridge ports and no address**.
2. **The test VM as the island's server:** a second network device on `vmbr9` with fixed addresses
   (netplan): `10.99.0.1/24` and `fd99::1/64`. Its first device stays on the LAN, for SSH and the
   encrypted lookups out.
3. **A client:** a Debian 13 container (512 MB), its only network device on `vmbr9`, set to DHCP
   and SLAAC. It starts with no address; it's reached over SSH through the test VM, at its IPv6
   link-local address, which needs no DHCP. It has no internet, so packages for the tests
   (dnsmasq, radvd) are fetched on forge (also Debian 13) and copied in.
4. **forge stays off the island:** the bridge has no address, and forge's own IPv6 is off on it
   (`post-up sysctl -w net.ipv6.conf.vmbr9.disable_ipv6=1`), so router advertisements there can't
   give forge an address or a route.
5. **Snapshots** of both before each run.

What to check there:

- **DHCP:** the client gets an address from the range, its name resolves as `client.home.arpa`,
  and it shows on the lease list. A fixed host gets its fixed address.
- **DNS:** outside names, local names and DNS aliases resolve from the client, over IPv4 and IPv6.
- **Encryption:** with `tcpdump` on the test VM's LAN device, nothing leaves on port 53; lookups go
  out on 853 to the chosen provider. Switching providers takes effect.
- **DNSSEC:** a deliberately broken domain (`dnssec-failed.org`) is refused; a good one resolves.
- **Blocklists:** a listed domain is blocked with the switch on, resolves with it off, resolves
  while paused, and resolves when allowlisted.
- **Rebinding:** a public name that answers with a private address is refused.
- **Firefox's canary** (`use-application-dns.net`) gets no answer.
- **Only the island and Tailscale get answers:** a query from the test VM's LAN side, from another
  LAN machine, is refused.
- **The DHCP check:** a second DHCP server put on the island (dnsmasq on the client) makes the NAS
  refuse to start DHCP.
- **IPv6 advertising:** with the NAS advertising its DNS server, the client picks up `fd99::1`.
  With a second advertiser on the island (the client's own `radvd`), the page warns.
- **Turning it off** stops everything, and the client can't renew. That's expected on the island;
  on the house LAN, the router takes over again.

### 2. DNS on the house LAN, one device at a time

Mode "DNS for my network", without touching the router: set one computer's DNS server (IPv4 and
IPv6) to the NAS by hand. If anything breaks, set that one computer back; nothing else in the house
notices. Check the blocklists, local names and encrypted lookups from there, and how the network's
IPv6 advertising looks (the page's check).

### 3. The house

The way back written down first, then:

1. **DNS for the whole house:** point the main router's DNS setting (IPv4, and IPv6 if it has
   one) at the NAS. Undo: point it back.
2. **DHCP**, if wanted: turn the main router's DHCP off in its own admin page (the OpenWrt bridge
   passes DHCP along and isn't where it's changed), then turn the NAS's on. Undo: the router's DHCP
   on again, the NAS's off.
