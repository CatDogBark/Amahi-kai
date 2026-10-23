# Networking tests on the NAS and in the house

Everything in Network → DNS & DHCP (DNS, DHCP, blocking, IPv6, totals) was built in five slices
and tried on an isolated test network on forge: the test VM as the server, a container as the only
device, nothing reaching the house ([`docs/plans/networking.md`](../plans/networking.md) has what
was checked, slice by slice). Then, with all of it on and the firewall on, it was tried again
through the firewall, and again after a reboot.

What that couldn't cover is this list: the real NAS, Tailscale, the house's router, the devices in
the house, and days of running. Tick each box as it passes; if one doesn't, stop there and send
Claude what the page shows plus the output of the [commands at the end](#if-something-fails).
Run each command on its own.

Nothing here touches the house until step 4, and every step from there has its way back written
next to it.

---

## 1. Before the NAS takes the update

- [ ] dnsmasq isn't answering DNS on the NAS. Since this update, dnsmasq never answers DNS, so if
  it does today, devices relying on it would lose names. On the NAS:

  ```bash
  dpkg -l dnsmasq | grep ^ii
  ```

  ```bash
  sudo ss -lnup | grep ':53 '
  ```

  Fine: dnsmasq isn't installed, and port 53 only shows `127.0.0.53` and `127.0.0.54`
  (systemd-resolved). If dnsmasq shows on port 53, stop and tell Claude first.

## 2. The NAS, with everything still off

- [ ] **System Update** finishes with "✓ Amahi-kai updated and running!".
- [ ] **Network** has the tabs Leases, Hosts, DNS & DHCP, DNS Aliases, Remote Access and
  Security. Gateway and Settings are gone; their old addresses open DNS & DHCP.
- [ ] **Network → DNS & DHCP** opens, says **Not installed** (or **Off**), and offers **Install
  Unbound**. Nothing listens on port 53 on the NAS's addresses (the second command above).
- [ ] **Network → Hosts** and **DNS Aliases** still list what they did.
- [ ] **Settings → Servers** shows Unbound, dnsmasq and radvd as not installed (or *DNS is off*,
  *DHCP is off*, *Not announcing*), not as failed.

## 3. DNS on the NAS, nothing pointed at it yet

- [ ] **Install Unbound**, then pick **DNS for my network**, the NAS's LAN interface (`ens18`,
  `192.168.1.111`) and Quad9, and **Save**. The top card says **Answering**, with local and
  outside names answered.
- [ ] From the laptop, without changing its settings (the NAS's name in place of `nas`):

  ```bash
  dig @192.168.1.111 example.com
  ```

  ```bash
  dig @192.168.1.111 nas.home.arpa
  ```

  ```bash
  dig @192.168.1.111 dnssec-failed.org
  ```

  The first answers with the `ad` flag, the second with the NAS's address, the third with
  `SERVFAIL` (a deliberately broken domain, refused).
- [ ] **The firewall:** if the security audit's firewall is on, the dig above got through it; then
  `sudo ufw show added` lists `allow to 192.168.1.111 port 53`.
- [ ] **Tailscale:** from a device on Tailscale but off the house Wi-Fi (a phone on cellular,
  say), ask the NAS's Tailscale address (Remote Access shows it; a terminal app on the phone, or
  a laptop on a hotspot):

  ```bash
  dig @100.x.y.z example.com
  ```

  It answers. That's the one path the test network couldn't try.
- [ ] **Blocking:** turn it on with the two recommended lists. Within a minute the card says how
  many domains it blocks (about 326,000). From the laptop, `dig @192.168.1.111 app-measurement.com`
  answers `0.0.0.0`.

**The way back:** pick **Off** and **Save**.

## 4. One device, then the house

- [ ] **One computer:** set its DNS server to `192.168.1.111` by hand (IPv4; leave IPv6 alone while
  the router's IPv6 is off). Use it normally for a day: sites load, `nas.home.arpa` opens the
  NAS, and ads are fewer. **The way back:** set it back to automatic.
- [ ] **The house:** in the router's settings, set the DNS server it hands out to `192.168.1.111`
  (often under LAN or DHCP). Devices pick it up as they renew; turning Wi-Fi off and on hurries
  one. **The way back:** set it back to the router's own (or automatic).
- [ ] **Each kind of device** gets names from the NAS and loses its ads where it should. These
  can go around the NAS and are worth a look one by one:
  - **Browsers' own secure DNS** (Chrome, Edge, Brave: Settings → Privacy → Secure DNS). Firefox
    is told not to by the network; the others aren't. "Use your current service provider" keeps
    the NAS.
  - **Android's Private DNS:** *Automatic* falls back to the NAS; a named provider goes around
    it.
  - **iPhones and Macs** with iCloud Private Relay, or a VPN.
  - **Smart TVs and streaming boxes** with DNS addresses of their own.
- [ ] **Something a list breaks:** if a site or app misbehaves, try **Pause for 5 minutes**; if
  that fixes it, put its domain in the **Allowlist** and tell Claude which one, for the list's
  project.

## 5. DHCP from the NAS (optional, advanced)

- [ ] **The check finds the router:** with the router's DHCP still on, pick **DNS + DHCP** and
  **Save**. It must refuse, naming the router (`192.168.1.1`) as another DHCP server. That's the
  check working against a router, not just dnsmasq.
- [ ] Only if you want the NAS to hand out addresses: turn the router's DHCP **off** in its own
  settings, then save **DNS + DHCP** with a range that leaves out the NAS, the router and anything
  with a fixed address. Devices get addresses as they renew, show on **Network → Leases**, and
  answer by name (`laptop.home.arpa`).
- **The way back:** turn the router's DHCP **on** again first, then set the page to **DNS for my
  network** or **Off**. While the NAS is off, devices can't get a new address, so don't leave
  this on while the NAS is being worked on.

## 5b. Router mode (only with a second interface for the internet)

Router mode makes the NAS the house's way to the internet. It was built and tried on the island
first (a fake provider on a third bridge); this is the house. Have the laptop tethered to a phone
*and* on the house Wi-Fi for all of it, so the session with Claude survives and the NAS stays
reachable from the LAN side.

- [ ] A spare network port on the NAS's host is on its own bridge, and the NAS VM has a NIC on it.
  The provider's gateway is in bridge mode (or the NAS sits behind its NAT, double-NAT, which
  works but keeps the gateway in charge of the internet side).
- [ ] **Dry run first:** the new port cabled to a LAN port of the house router instead of the
  provider. Network → Security's firewall is on. Pick **Router**, the internet interface, and
  **Save**. The top card says the NAS has an address from "the provider" (the house router).
  Nothing in the house changes yet, since the house router still hands out addresses.
- [ ] **The house:** the house router's DHCP off, the provider's cable moved to the NAS's port
  (power-cycle the modem), the router's internet port empty. Devices renew and reach the
  internet through the NAS; the top card shows the provider's address.
- [ ] A port forward to a device works from outside (a phone on cellular, the NAS's internet
  address and the port). Nothing else answers from outside: the web UI and SSH on the internet
  address time out.
- **The way back:** set the page to DNS + DHCP or Off, move the cable back to the router, turn
  its DHCP on, power-cycle the modem.

## 6. IPv6

- [ ] With the router's IPv6 off (as now), **IPv6 → Check now** says no router answered, and
  devices use the NAS's IPv4 address for DNS. Nothing else to do.
- [ ] If IPv6 is ever turned on at the router: **Check now** again. If it warns that the router
  announces another DNS server, set the router's announced IPv6 DNS to the NAS, or have it
  announce none; **Announce the NAS** is the fallback for a router that can do neither.

## 7. Over the following days

- [ ] **The daily refresh:** the next day, the Blocking card says the lists were downloaded hours
  ago, not days (it runs once a day, around 4 am by the NAS's clock).
- [ ] **Totals** grow, and the share answered on the NAS settles somewhere above half.
- [ ] **Memory:** Settings → Servers shows Unbound using about 160 MB with the recommended lists.
- [ ] **A reboot of the NAS:** afterwards the card says **Answering**, with blocking on, and devices
  never noticed more than the minute it was down.

---

## If something fails

Send Claude what the page shows, and the output of these (each on its own):

```bash
systemctl status unbound dnsmasq radvd --no-pager
```

```bash
sudo journalctl -u unbound -n 40 --no-pager
```

```bash
sudo unbound-checkconf
```

```bash
sudo ufw show added
```

```bash
ip -br addr
```

```bash
ip -6 route
```
