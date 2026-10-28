# The NAS's network interfaces and their addresses, read with getifaddrs (no command runs), and
# the interface its default route leaves by. Network → DNS, DHCP and Internet serves one of them.

require 'ipaddr'
require 'socket'

module NetworkInterfaces
  # Not the LAN: loopback, Docker's bridges and their veth ends, Tailscale, VPNs and virtual
  # bridges.
  NOT_LAN = /\A(lo|docker|br-|veth|tailscale|virbr|wg|tun|tap|zt)/
  TAILSCALE = 'tailscale0'
  # Docker's default bridge: the apps' containers' gateway
  DOCKER = 'docker0'
  # Tailscale gives each device an address from these.
  TAILSCALE_NETS = %w[100.64.0.0/10 fd7a:115c:a1e0::/48].freeze
  ROUTES = '/proc/net/route'

  # One address on an interface, with the length of its network's prefix.
  Address = Data.define(:ip, :prefix) do
    def ipv4? = ip.ipv4?
    def link_local? = ip.link_local?
    # An IPv6 unique local address (fc00::/7), which stays the same whatever the ISP hands out.
    def ula? = ip.ipv6? && IPAddr.new('fc00::/7').include?(ip)
    def network = "#{ip.mask(prefix)}/#{prefix}"
    def to_s = ip.to_s
  end

  class << self
    # { "ens18" => [Address, ...] } for every interface, with its IPv4 and IPv6 addresses. One
    # with none (a port with no cable, or not set up yet: the internet interface before router
    # mode gives it an address) has an empty list, so it can still be chosen.
    def all(ifaddrs = Socket.getifaddrs)
      ifaddrs.each_with_object({}) do |ifaddr, list|
        list[ifaddr.name] ||= []
        address = address_of(ifaddr) or next
        list[ifaddr.name] << address
      end
    end

    # The interfaces that can be the LAN, by name.
    def lan(ifaddrs = Socket.getifaddrs)
      all(ifaddrs).reject { |name, _| name.match?(NOT_LAN) }
    end

    def addresses(name, ifaddrs = Socket.getifaddrs)
      all(ifaddrs).fetch(name, [])
    end

    # The interface the IPv4 default route leaves by ("ens18"), or nil.
    def default_name(routes = ROUTES)
      default_route(routes)&.first
    end

    # The IPv4 default route with the lowest metric: ["ens18", "192.168.1.1"], or nil.
    def default_route(routes = ROUTES)
      default_routes(routes).first&.first(2)
    end

    # Every IPv4 default route, the lowest metric first: [["ens18", "192.168.1.1", 100], ...].
    def default_routes(routes = ROUTES)
      File.foreach(routes).drop(1).filter_map do |line|
        name, destination, gateway, flags, _refcnt, _use, metric, = line.split
        next unless destination == '00000000' && (flags.to_i(16) & 1).positive?
        [name, IPAddr.new(gateway.to_i(16), Socket::AF_INET).to_s.split('.').reverse.join('.'), metric.to_i]
      end.sort_by(&:last)
    rescue SystemCallError
      []
    end

    private

    def address_of(ifaddr)
      addr = ifaddr.addr
      return unless addr&.ip? && ifaddr.netmask
      ip = IPAddr.new(addr.ip_address.sub(/%.*\z/, ''))
      Address.new(ip:, prefix: IPAddr.new(ifaddr.netmask.ip_address.sub(/%.*\z/, '')).to_i.to_s(2).count('1'))
    rescue IPAddr::Error
      nil
    end
  end
end
