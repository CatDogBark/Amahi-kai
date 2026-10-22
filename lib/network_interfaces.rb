# The NAS's network interfaces and their addresses, read with getifaddrs (no command runs), and
# the interface its default route leaves by. Network → DNS listens on one of them.

require 'ipaddr'
require 'socket'

module NetworkInterfaces
  # Not the LAN: loopback, Docker's bridges and their veth ends, Tailscale, VPNs and virtual
  # bridges.
  NOT_LAN = /\A(lo|docker|br-|veth|tailscale|virbr|wg|tun|tap|zt)/
  TAILSCALE = 'tailscale0'
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
    # { "ens18" => [Address, ...] } for every interface with an IPv4 or IPv6 address.
    def all(ifaddrs = Socket.getifaddrs)
      ifaddrs.each_with_object({}) do |ifaddr, list|
        address = address_of(ifaddr) or next
        (list[ifaddr.name] ||= []) << address
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
      File.foreach(routes).drop(1).each do |line|
        name, destination, _gateway, flags, = line.split
        return name if destination == '00000000' && (flags.to_i(16) & 1).positive?
      end
      nil
    rescue SystemCallError
      nil
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
