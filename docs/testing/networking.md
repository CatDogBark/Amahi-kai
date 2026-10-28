# Networking tests on the NAS and in the house

Everything in Network → DNS (DNS, DHCP, blocking, IPv6, totals) was built in five slices
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
- [ ] **Network** has the tabs Devices, DNS, DHCP, Internet, Remote Access and Security. Leases,
  Hosts, DNS Aliases, Gateway and Settings are gone; their old addresses open the new tabs.
- [ ] **Network → DNS** opens, says **Not installed** (or **Off**), and offers **Install
  Unbound**. Nothing listens on port 53 on the NAS's addresses (the second command above).
- [ ] **Network → Devices** (the fixed addresses) and **Network → DNS** (Names) still list what
  they did.
- [ ] **Network → Devices, This NAS** lists each port with its address, *from the network (DHCP)*
  or *fixed*, and its router. Give the NAS a fixed address on the port you're connected through
  (the one it has now is fine, or one outside the router's DHCP range): the moving page appears,
  reaches the NAS at the new address within a few seconds and lands on Devices there, which says
  the port moved. Then try an address nothing can reach (another network, say `10.250.0.2`):
  the page counts down, says nothing reached the NAS, and brings you back to the old address
  about 90 seconds later. `sudo iptables -t nat -S PREROUTING` on the NAS shows each NAT rule
  once (in `amahi-kai-prerouting`), never a stale copy with an old address.
- [ ] **Settings → Servers** shows Unbound, dnsmasq and radvd as not installed (or *DNS is off*,
  *DHCP is off*, *Not announcing*), not as failed.

## 3. DNS on the NAS, nothing pointed at it yet

- [ ] **Install Unbound**, then turn **DNS for my network** on, pick the NAS's LAN interface
  (`ens18`, `192.168.1.1`) and Quad9, and **Save**. The top card says **Answering**, with local and
  outside names answered.
- [ ] From the laptop, without changing its settings (the NAS's name in place of `nas`):

  ```bash
  dig @192.168.1.1 example.com
  ```

  ```bash
  dig @192.168.1.1 nas.home.arpa
  ```

  ```bash
  dig @192.168.1.1 dnssec-failed.org
  ```

  The first answers with the `ad` flag, the second with the NAS's address, the third with
  `SERVFAIL` (a deliberately broken domain, refused).
- [ ] **The firewall:** if the security audit's firewall is on, the dig above got through it; then
  `sudo ufw show added` lists `allow to 192.168.1.1 port 53`.
- [ ] **Tailscale:** from a device on Tailscale but off the house Wi-Fi (a phone on cellular,
  say), ask the NAS's Tailscale address (Remote Access shows it; a terminal app on the phone, or
  a laptop on a hotspot):

  ```bash
  dig @100.x.y.z example.com
  ```

  It answers. That's the one path the test network couldn't try.
- [ ] **Blocking:** turn it on with the two recommended lists. Within a minute the card says how
  many domains it blocks (about 326,000). From the laptop, `dig @192.168.1.1 app-measurement.com`
  answers `0.0.0.0`.

**The way back:** turn the switch off and **Save**.

## 4. One device, then the house

- [ ] **One computer:** set its DNS server to `192.168.1.1` by hand (IPv4; leave IPv6 alone while
  the router's IPv6 is off). Use it normally for a day: sites load, `nas.home.arpa` opens the
  NAS, and ads are fewer. **The way back:** set it back to automatic.
- [ ] **The house:** in the router's settings, set the DNS server it hands out to `192.168.1.1`
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

- [ ] **The check finds the router:** with the router's DHCP still on, turn **Network → DHCP** on
  and **Save**. It must refuse, naming the router (`192.168.1.1`) as another DHCP server. That's the
  check working against a router, not just dnsmasq.
- [ ] Only if you want the NAS to hand out addresses: turn the router's DHCP **off** in its own
  settings, then save DHCP on with a range that leaves out the NAS, the router and anything
  with a fixed address. Devices get addresses as they renew, show on **Network → Leases**, and
  answer by name (`laptop.home.arpa`).
- **The way back:** turn the router's DHCP **on** again first, then turn DHCP off. While the NAS is off, devices can't get a new address, so don't leave
  this on while the NAS is being worked on.
- [ ] **Names that follow devices** (Network → Devices): **Name** a device without fixing its
  address (`carport-cam`). From a PC, `nslookup carport-cam` answers its address at once.
  Restart the device (or wait for its renewal) so DHCP gives it another address if it can:
  the name answers the new one. A Wyze camera answers by `wyze-cakp2jfus-…` before it's named.
- [ ] **Unfix** a fixed device: it keeps its name and takes an address from the range;
  **Forget** drops the name. A device called `ignore` is refused.
- [ ] **Apps on the NAS's DNS:** with DNS on, an app's container asks the NAS
  (`sudo docker exec amahi-<app> cat /etc/resolv.conf` shows the bridge's address,
  `172.17.0.1`, and the local domain), and finds a named device:
  `sudo docker exec amahi-<app> nslookup carport-cam` (where the image has nslookup).
  Turn DNS off: within a few minutes the apps' containers are made again without it
  (`systemctl status amahi-kai-apps-follow-dns`), and they still reach the internet.
  Turn it on again: they're made again with it.

## 5b. Router mode (only with a second interface for the internet)

Router mode makes the NAS the house's way to the internet. It was built and tried on the island
first (a fake provider on a third bridge); this is the house. Have the laptop tethered to a phone
*and* on the house Wi-Fi for all of it, so the session with Claude survives and the NAS stays
reachable from the LAN side.

The layout (CatDogBark, 2026-10-23): the NAS is the router; the Linksys at .1 becomes an access
point and switch (its **Bridge Mode**: Connectivity → Internet Settings → Connection Type) with its
two SSIDs kept; the OpenWrt bridge at .2 keeps connecting to the Linksys's Wi-Fi as it does now,
so the far room's wired devices stay on the one LAN. For the test, the modem's cable runs to
forge; in the end forge, the Linksys and the modem sit side by side.

- [ ] A spare network port on forge is on its own bridge, and the NAS VM has a NIC on it. The
  provider's gateway is in bridge mode (or the NAS sits behind its NAT, double-NAT, which works
  but keeps the gateway in charge of the internet side).
- [ ] **Dry run first:** the new port cabled to a LAN port of the Linksys instead of the modem.
  Network → Security's firewall is on. Pick **Router**, the internet interface, and **Save**. The
  top card says the NAS has an address from "the provider" (the Linksys). Nothing in the house
  changes yet, since the Linksys still hands out addresses.
- [ ] **A speed test from the main room before the switch**, to compare after: with the modem's
  cable at forge, the main room's internet crosses the wireless bridge.
- [ ] **The house:** the Linksys into Bridge Mode (its DHCP and NAT stop; give it a fixed address on
  Network → Devices), the modem's cable moved to forge's port (power-cycle the modem). Devices
  renew and reach the internet through the NAS; the top card shows the provider's address; the
  speed test again.
- [ ] A port forward to a device works from outside (a phone on cellular, the NAS's internet
  address and the port). Nothing else answers from outside: the web UI and SSH on the internet
  address time out.
- [ ] **A save leaves the connection alone:** adding or removing a port forward changes no network
  file, so the internet port keeps its lease (`journalctl -u systemd-networkd --since -5min` on
  the NAS shows nothing for it) and, while the NAS announces itself over IPv6, its `fd…::53`
  address stays on the LAN port (`ip -6 addr`).
- **The way back:** turn the switch off on Network → Internet, move the cable back to the Linksys's
  internet port, take the Linksys out of Bridge Mode, power-cycle the modem.

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
