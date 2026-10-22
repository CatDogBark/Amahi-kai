---
layout: default
title: "Networking"
---

# Networking

Amahi-kai can be your network's DNS server, private and checked, with names for your devices,
and it can hand out addresses (DHCP) in place of your router. Both are off until you turn them
on, on **Network → DNS & DHCP** in **Advanced mode**.

---

## Enabling Advanced Mode

DNS and DHCP, DNS aliases, remote access and security are all Advanced mode features:

1. Go to **Settings** tab
2. Toggle **Advanced mode** on

---

## DNS (Network → DNS & DHCP)

The page has three modes:

1. **Off** (the default): nothing listens, and your router does DNS and DHCP as before.
2. **DNS for my network** (recommended): the NAS answers DNS; your router keeps handing out
   addresses.
3. **DNS + DHCP** (advanced): the NAS also hands out addresses, in place of your router (see DHCP,
   below).

DNS turns names like `example.com` into addresses. Normally your router does it, by asking your
internet provider, who can read (and sometimes change) every lookup. With Amahi-kai's DNS on:

- **Lookups leave encrypted.** Your devices ask the NAS, and it asks the provider you pick over
  DNS-over-TLS, so your internet provider sees neither the names nor the answers.
- **Answers are checked.** DNSSEC refuses forged answers for the domains that sign theirs.
- **Repeat lookups are fast,** from the NAS's cache, and names keep working through a short
  outage at the provider.
- **Your devices get names:** the NAS, your fixed hosts and your DNS aliases answer as
  `name.home.arpa` and as plain `name`.
- **Nothing is logged** about which device looked up what.

It runs Unbound, a DNS server from Ubuntu.

### Providers

All of them are free, need no account, encrypt the connection and check DNSSEC:

| Provider | Notes |
|----------|-------|
| Quad9 (default) | Swiss nonprofit. Keeps no record of your address, and blocks known malware domains. |
| Cloudflare | Fast and widely used. Never stores your address on disk, and deletes its logs within 25 hours. |
| AdGuard DNS (unfiltered) | AdGuard's public service, without its blocking. Keeps no personal data. |
| DNS.SB | Small independent service. Logs no lookups and no addresses. |
| Another server | Any DNS-over-TLS server: its addresses and the name on its certificate. |

### Turning it on

1. Go to **Network → DNS & DHCP** and click **Install Unbound**. Installing changes nothing on
   your network: DNS stays off.
2. Pick **DNS for my network**, a provider, and the network interface DNS should answer on (the
   one your LAN is on), then **Save**. The page shows whether it's answering, for local names
   and outside ones.
3. **Give the NAS a fixed address:** in your router's DHCP settings, reserve the NAS's address so
   it never changes. Every device will be pointed at it.
4. **Point devices at it.** To try it first, set one computer's or phone's DNS server to the NAS's
   address by hand. For the whole house, set the DNS server in your router's settings to the
   NAS's address (often under Internet, WAN or DHCP).

**The way back:** set the router's DNS setting back to automatic (or the one device's). While the
NAS is off or restarting, the devices that use it can't look up names.

### Safety

- **It answers your network only:** the devices on the interface you picked, and Tailscale's when
  Tailscale is on. Anyone else is refused, and the firewall lets DNS in to the NAS's DNS
  addresses only.
- **DNS rebinding protection:** an outside name that points at an address inside your network
  gets no answer, so a website can't reach your devices through its own name. Your local names
  are exempt.
- **Firefox** is told to use this DNS rather than its own encrypted DNS (with the standard
  `use-application-dns.net` signal). Other browsers and devices with their own encrypted DNS
  turned on go around it.
- **The NAS's own lookups don't go through it:** the NAS keeps asking your router, so a problem
  with DNS can't stop it from updating.

### Blocking ads, trackers and malware

The **Blocking** card blocks ads, trackers and malware for every device that uses the NAS's DNS:
a blocked name answers `0.0.0.0`, so what it would load never does, and the names under it are
blocked too. It's off until you turn it on, and works while DNS is on.

- **The lists** come from two open projects, HaGeZi and OISD (both GPL-3.0), and refresh every
  day. Two are ticked: **HaGeZi Multi NORMAL** (ads, trackers and malware, made for networks
  nobody watches over) and **HaGeZi Threat Intelligence (mini)** (malware, phishing and scams).
  Together they block about 330,000 domains, which takes Unbound about 160 MB of memory. The
  others are stricter, gentler, or bigger; the page says which.
- **The allowlist** is for a site a list breaks: a domain there, and the names under it, get
  through (unless a list blocks one of those names itself).
- **Pause for 5 minutes** lets everything through for a while, then blocking comes back by
  itself. Devices remember answers for a minute or two, so a change can take that long to show.
- A list that can't be downloaded keeps its last copy, and the page says so.

### Generated configuration

Amahi-kai writes `/etc/unbound/unbound.conf.d/amahi-kai.conf` through its root helper, which only
accepts the lines Amahi-kai generates, and only after `unbound-checkconf` accepts the file.
Changes made to it by hand are lost the next time it's written. The blocklist is
`amahi-kai-blocklist.conf` beside it, and the names of the devices DHCP gave addresses to are in
`amahi-kai-leases.conf`.

---

## DNS Aliases

DNS aliases are extra names on your network: `files` for the NAS, or `printer` for your printer's
address.

1. Go to **Network → DNS Aliases** (Advanced mode)
2. Enter a **name** (e.g., `files`): it must start with a letter, and can contain letters, numbers
   and hyphens
3. Enter an **address** (IPv4 or IPv6), or leave it blank to point the name at the NAS
4. Click **Create**

The name answers as `files.home.arpa` and as `files`, for devices that use the NAS's DNS
(above). If a name is taken, the NAS's own name comes first, then the fixed hosts, then the
aliases.

---

## Static Hosts

Static hosts give a device the same IP address and name every time. Manage them on
**Network → Hosts**:

- **Name**: the device's name on the network (letters, numbers and hyphens, up to 63 characters)
- **MAC**: the device's MAC address
- **Address**: the last part of the IP address to give it (the network part is filled in)

The name answers in DNS (`printer.home.arpa`, and `printer`) while DNS is on. While the NAS hands
out addresses (DNS + DHCP), the device always gets this one.

---

## DHCP (DNS + DHCP)

In the mode **DNS + DHCP**, the NAS also hands out addresses to the devices on your network, in
place of your router's DHCP. Your router almost certainly does this already, so it's optional:
it puts the NAS in charge of the network, and gives every device a name in DNS.

1. On **Network → DNS & DHCP**, pick **DNS + DHCP** and click **Install dnsmasq** (installing
   changes nothing on your network).
2. **Turn your router's DHCP off** in its own settings (often under LAN or DHCP). Leave the
   router's own address as it is.
3. Set the addresses to hand out (a range on the interface's network, at least 10 addresses, not
   taking in the NAS's own), the router's address, and how long devices keep an address, then
   **Save**. The NAS first checks the network for another DHCP server, the way a device would,
   and won't start while one answers.

Devices pick up an address from the NAS the next time they connect or renew; turning a device's
Wi-Fi off and on hurries it along. Each one is given the NAS as its DNS server and `home.arpa` as
its domain, and answers by the name it gives (`laptop.home.arpa`, and `laptop`). Fixed addresses
for chosen devices are on **Network → Hosts**.

DHCP serves the interface DNS answers on, and nowhere else, and the firewall lets DHCP in on that
interface only.

**The way back:** turn your router's DHCP on again, then set the page to DNS for my network or
Off. Devices move back to the router as they renew. While the NAS is off, devices can't get a new
address.

---

## Network Leases

The **Network** index page shows the devices that got an address from the NAS: each one's name,
MAC address, IP address and when its lease runs out.

---

## Troubleshooting

### Names don't resolve from a device

1. Check **Network → DNS & DHCP**: it should say **Answering**.
2. Check the device asks the NAS: on the device, `nslookup example.com <NAS address>` should
   answer. If it does but plain `nslookup example.com` doesn't use the NAS, the device (or the
   router) is still set to another DNS server.
3. Browsers with their own encrypted DNS turned on (Chrome's or Edge's "secure DNS", for
   example) don't ask the NAS. Turn that off, or set it to "use your current provider".

### Unbound won't start

```bash
sudo journalctl -u unbound -n 30 --no-pager
sudo unbound-checkconf
```

Don't turn off systemd-resolved's stub listener for this: Amahi-kai's DNS listens on the NAS's
network addresses, not on `127.0.0.53`, so the two don't clash.

### Devices don't get addresses from the NAS

- Check **Network → DNS & DHCP** is in DNS + DHCP, and says it's handing out addresses
- Check the DHCP range doesn't overlap with static assignments
- Make sure no other DHCP server is running (turn your router's DHCP off)
- Check the lease file: `cat /var/lib/misc/dnsmasq.leases`
