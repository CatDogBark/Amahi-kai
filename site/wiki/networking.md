---
layout: default
title: "Networking"
---

# Networking

Amahi-kai can be your network's DNS server, private and checked, with names for your devices; it
can hand out addresses (DHCP) in place of your router; and it can be your router. Each has its
own page under **Network**, in **Advanced mode**: **DNS**, **DHCP** and **Internet**, with
**Devices** for the devices on the network and their fixed addresses. Everything is off until
you turn it on, and each builds on the one before: DHCP needs DNS, the router needs DHCP.

---

## Enabling Advanced Mode

DNS and DHCP, DNS aliases, remote access and security are all Advanced mode features:

1. Go to **Settings** tab
2. Toggle **Advanced mode** on

---

## DNS (Network → DNS)

DNS turns names like `example.com` into addresses. Normally your router does it, by asking your
internet provider, who can read (and sometimes change) every lookup. With Amahi-kai's DNS on:

- **Lookups leave encrypted.** Your devices ask the NAS, and it asks the provider you pick over
  DNS-over-TLS, so your internet provider sees neither the names nor the answers.
- **Answers are checked.** DNSSEC refuses forged answers for the domains that sign theirs.
- **Repeat lookups are fast,** from the NAS's cache, and names keep working through a short
  outage at the provider.
- **Your devices get names:** the NAS, your fixed hosts and your DNS aliases answer as
  `name.home.arpa` and as plain `name`.
- **Nothing is logged** about which device looked up what. The page shows totals only: how many
  lookups, how many the NAS answered itself, and how many answers came signed by their domain and
  checked out. An answer whose signature fails is refused rather than passed on; that's usually a
  domain whose signing is broken, not an attack.

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

1. Go to **Network → DNS** and click **Install Unbound**. Installing changes nothing on your
   network: DNS stays off.
2. Turn on **DNS for my network**, pick a provider and the network interface DNS should answer
   on (the one your LAN is on), then **Save**. The page shows whether it's answering, for local names
   and outside ones.
3. **Give the NAS a fixed address** on **Network → Devices** ([This NAS](#this-nas-its-own-address)),
   or reserve its address in your router's DHCP settings, so it never changes. Every device will
   be pointed at it.
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

### Router (Network → Internet)

**The NAS is the router** makes the NAS the house's way to the internet: DNS and DHCP, plus a
second network interface that takes the provider's connection. Your devices reach the internet
through the NAS, and your old router becomes an access point (its DHCP off, its internet port
empty, your devices on its LAN ports and Wi-Fi as before).

1. The NAS needs a **second network interface** with the provider's cable in it (a spare port on
   the machine, or a NIC added to the VM). If the provider's box is a gateway with its own router
   inside, put it in bridge mode, or the NAS sits behind its NAT.
2. **Turn the firewall on** first (Network → Security, the firewall's Fix). Router mode refuses
   without it: the firewall is what keeps the internet out of the NAS.
3. On **Network → Internet**, turn the switch on, pick the internet interface, and **Save**, from a device on the LAN side (the page
   refuses if you're connected through the interface that would become the internet side, since
   it would stop answering you).

The NAS's own network settings for the LAN interface are adjusted for you: an address it got
from the old router is kept as a fixed one, and a route it had through the old router steps
behind the internet's. The file is put back when you leave router mode.

**Every device uses the NAS's DNS** (on unless you untick it): some devices ask a DNS server of
their own choosing (Roku, Google's, some TVs), skipping yours and its blocking. In router mode
the NAS answers those lookups anyway, keeps a device's own encrypted DNS from getting out, and
blocks the known encrypted-DNS services by name (the *Encrypted DNS providers* list is added to
Blocking, so turn Blocking on for that part). If Tailscale is installed, its port is let in on
the internet side so its connections stay direct; the Cloudflare Tunnel needs nothing.

Nothing from the internet reaches the NAS or your devices except the **ports you let in**, on
the card that appears: a port, a protocol, the device (give it a fixed address on Network → Devices
first) and its port. The NAS's own services (SSH, the web UI, Samba, DNS) never answer the
internet side.

The NAS doesn't answer pings from the internet either, nor takes or sends route changes
(ICMP redirects) there. A NAS that is the router faces the internet, so the page also says
whether Ubuntu's security updates install by themselves; the switch is on Settings → System
Dependencies (security fixes only, from Ubuntu's security channel, never new versions of
anything; the installer leaves it off, and the security audit warns while the NAS is the router
without it).
The page counts what the internet side
dropped: **connection attempts** at the NAS from the internet, pings among them, since the
rules were loaded (every save of this page, and a restart, starts the count over; attempts are
normal, the internet knocks on every address), and **forged packets**, ones
arriving from the internet that claim an address inside your own network, which the kernel
drops before anything sees them. It also lists the devices kept **LAN only** (Network →
Devices).

**The way back:** turn the switch off, move the provider's cable back to your router, and turn
its DHCP on again. While the NAS is off or restarting, the house has no
internet. A System Update doesn't do that: it restarts only the web page and Samba, and DNS,
DHCP and the router keep running.

IPv6 for the house (an address range from the provider), PPPoE and a static address come later.

## IPv6

Most internet providers hand out IPv6 too, and devices on IPv6 learn their DNS server from the
network's announcements (router advertisements), usually the router's. If a device learns the
router as its IPv6 DNS server, it may ask the router instead of the NAS, going around its privacy
and blocking. The **IPv6** card shows what your routers announce (**Check now**), and warns when
one announces a DNS server that isn't the NAS. Three ways to fix it, best first:

1. **The router announces the NAS.** If your router lets you set the IPv6 DNS server it announces
   (OpenWrt does), set it to the NAS's IPv6 address.
2. **The router announces no IPv6 DNS server.** Devices then use the IPv4 one, the NAS.
3. **The NAS announces itself** (*Announce the NAS as the IPv6 DNS server*, in Settings): it
   announces an address of its own (`fd…::53`, in a private range it makes once), which stays the
   same whatever your internet provider hands out, and never announces itself as a router. Some
   devices handle two announcers poorly, so the first two are better where the router allows. It
   needs radvd, which the page installs.

### Blocking ads, trackers and malware

The **Blocking** card blocks ads, trackers and malware for every device that uses the NAS's DNS:
a blocked name answers `0.0.0.0`, so what it would load never does, and the names under it are
blocked too. It's off until you turn it on, and works while DNS is on.

- **The lists** come from two open projects, HaGeZi and OISD (both GPL-3.0), and refresh every
  day. Two are ticked: **HaGeZi Multi NORMAL** (ads, trackers and malware, made for networks
  nobody watches over) and **HaGeZi Threat Intelligence (mini)** (malware, phishing and scams).
  Together they block about 330,000 domains, which takes Unbound about 160 MB of memory. The
  others are stricter, gentler, or bigger; the page says which.
- **Devices you have:** per-vendor lists (Samsung, LG, Roku, Amazon, Apple, Windows and Office,
  TikTok, Xiaomi) that block a vendor's own telemetry hosts and keep the hosts its devices need.
  Tick the kinds you own. A list can't separate telemetry from the service when both use the same
  host, so this is as far as a network can go; the allowlist is there if something breaks.
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

## Names (DNS aliases)

Extra names on your network: `files` for the NAS, or `printer` for your printer's address. They're
the **Names** card on **Network → DNS**.

1. Go to **Network → DNS**, the Names card
2. Enter a **name** (e.g., `files`): it must start with a letter, and can contain letters, numbers
   and hyphens
3. Enter an **address** (IPv4 or IPv6), or leave it blank to point the name at the NAS
4. Click **Create**

The name answers as `files.home.arpa` and as `files`, for devices that use the NAS's DNS
(above). If a name is taken, the NAS's own name comes first, then the fixed hosts, then the
aliases.

---

## This NAS: its own address

The top of **Network → Devices** shows the NAS's own address on each network port, and how it
got it: **from the network** (your router's DHCP, which can give it a different one some day) or
**fixed**. The shares, DNS, DHCP and the router all rely on the NAS's address, so a fixed one is
the better choice. **Change** on a port sets it:

- **From the network (DHCP)**: the router hands the NAS an address.
- **Fixed**: the address, its network size (`/24` is the usual home network), the router's address
  and the DNS servers the NAS itself should ask. Pick an address your router doesn't hand out
  (outside its DHCP range), or reserve the address on the router, so no device is given the same
  one later.

Changing the address of the port you're connected through moves the page with it: a page
appears that keeps trying the NAS at the new address and goes there once it answers (you may
have to sign in again there). That answer is what keeps the change; if nothing reaches the NAS
at the new address within 90 seconds, the NAS goes back to the old address by itself, and the
page follows. A wrong address can't lock you out. Changing another port's address happens at
once.

Through the Cloudflare Tunnel or Tailscale, the port they run over (the one with the NAS's way
out to the internet) can't be changed: the NAS can't watch for you coming back that way, so a
wrong address there would cut you off with nothing to put it back. Change that one from a
computer on your LAN.

While the NAS is the router (Network → Internet), the internet side's address comes from the
provider and is managed there, and the LAN port has no router of its own (the NAS is it). The
port the NAS hands out addresses on (Network → DHCP) needs a fixed address.

Afterwards, bookmarks and devices that used the old address need the new one; DNS, DHCP, the
router and the shares follow it by themselves.

Under each port the page says what it is (the network card's model, or a *virtual port* on a
server that runs as a virtual machine, which has no socket of its own), whether a cable is in
and at what speed, and its hardware (MAC) address. **Name** gives the port a name of your own
("Modem", "Office") that then shows wherever the port comes up, on the DNS, DHCP and Internet
pages too; a server with several ports is hard to follow by `enp3s0f1` alone. **Find port**
blinks a real port's light for five seconds, to see which socket it is on the back of the
server.

## Devices and fixed addresses

**Network → Devices** lists the devices the NAS has given an address to, and lets you fix a
device's address so it keeps it every time (**Fix this address** on a device in the list, or add
one by hand):

- **Name**: the device's name on the network (letters, numbers and hyphens, up to 63 characters)
- **MAC**: the device's MAC address
- **Address**: the last part of the IP address to give it (the network part is filled in)

The name answers in DNS (`printer.home.arpa`, and `printer`) while DNS is on. While the NAS hands
out addresses (DNS + DHCP), the device always gets this one.

**LAN only** on a fixed device keeps it off the internet while the NAS is the router (Network →
Internet): it still reaches the shares, DNS, the NAS and every other device on the LAN, but
nothing beyond. For a TV, a camera or a toy that has no business out there. *Internet again*
undoes it. The device needs a fixed address because the rule is by address. While the NAS
isn't the router yet, the setting waits for when it is. Network → Internet lists the devices
kept off.

---

## DHCP (Network → DHCP)

With **The NAS hands out addresses** on, the NAS hands out addresses to the devices on your network, in
place of your router's DHCP. Your router almost certainly does this already, so it's optional:
it puts the NAS in charge of the network, and gives every device a name in DNS.

1. On **Network → DHCP**, click **Install dnsmasq** (installing changes nothing on your network).
2. **Give the NAS a fixed address** on **Network → Devices** ([This NAS](#this-nas-its-own-address)).
   A NAS that hands out addresses can't take its own from DHCP: its lease would run out with
   nothing to renew it, and the house's DHCP and DNS with it. The switch says so until it has one.
3. **Turn your router's DHCP off** in its own settings (often under LAN or DHCP). Leave the
   router's own address as it is.
4. Turn the switch on, set the addresses to hand out (a range on the interface's network, at
   least 10 addresses, not taking in the NAS's own), the router's address, and how long devices
   keep an address, then **Save**. The NAS first checks the network for another DHCP server, the way a device would,
   and won't start while one answers.

Devices pick up an address from the NAS the next time they connect or renew; turning a device's
Wi-Fi off and on hurries it along. Each one is given the NAS as its DNS server and `home.arpa` as
its domain, and answers by the name it gives (`laptop.home.arpa`, and `laptop`). Fixed addresses
for chosen devices are on **Network → Devices**.

DHCP serves the interface DNS answers on, and nowhere else, and the firewall lets DHCP in on that
interface only.

**The way back:** turn your router's DHCP on again, then turn the switch off. Devices move back to the router as they renew. While the NAS is off, devices can't get a new
address.

---

## Troubleshooting

### Names don't resolve from a device

1. Check **Network → DNS**: it should say **Answering**.
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

- Check **Network → DHCP** is on and says it's handing out addresses
- Check the DHCP range doesn't overlap with static assignments
- Make sure no other DHCP server is running (turn your router's DHCP off)
- Check the lease file: `cat /var/lib/misc/dnsmasq.leases`
