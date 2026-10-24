# The NAS's own IPv4 address on each interface (Network → Devices, This NAS): what each has and
# how it got it, and changing one through the helper (network.set_address), which rewrites the
# interface's netplan entry. A change to the interface the admin is connected through is applied
# after the reply and kept only once something reaches the NAS at the new address within WAIT
# seconds (the page shown meanwhile tries it, and a request arriving through that interface is
# what keeps it: keep!); otherwise the helper's timer puts the old settings back. The helper's
# STATE file says where a change stands.

require 'ipaddr'
require 'json'
require 'network_interfaces'
require 'privileged'
require 'shell'

module NetworkAddress
  STATE = '/var/lib/amahi-kai-dns/address.json'
  # How long the helper waits to be reached (its ADDRESS_KEEP_WAIT), after the moment it applies
  # the change (ADDRESS_APPLY_WAIT after the reply).
  WAIT = 90
  APPLY_WAIT = 2
  # A change is worth a word on the page this long after.
  RECENT = 15 * 60
  # systemd-resolved's view of the DNS servers the NAS itself uses.
  RESOLV_CONF = '/run/systemd/resolve/resolv.conf'
  MODES = %w[automatic fixed].freeze

  # One interface that can be the LAN: its IPv4 addresses, whether it took its address from a
  # DHCP server, the router it has (its default route's gateway), and its part: :lan (the one
  # DNS serves), :internet (the router mode's), or nil.
  Interface = Data.define(:name, :addresses, :automatic, :gateway, :part) do
    def fixed? = !automatic && addresses.any?
  end

  class << self
    def interfaces
      router = DnsService.router_state
      lan = DnsService.interface
      routes = NetworkInterfaces.default_routes
      NetworkInterfaces.lan.map do |name, addresses|
        Interface.new(name: name, addresses: addresses.select(&:ipv4?), automatic: automatic?(name),
                      gateway: routes.find { |route| route.first == name }&.at(1),
                      part: router && router['wan'] == name ? :internet : (name == lan ? :lan : nil))
      end
    end

    # Whether the interface's IPv4 address came from a DHCP server: the kernel marks such an
    # address dynamic.
    def automatic?(name)
      JSON.parse(Shell.output('ip', '-j', '-4', 'addr', 'show', 'dev', name)).any? do |link|
        Array(link['addr_info']).any? { |address| address['dynamic'] }
      end
    rescue JSON::ParserError
      false
    end

    # The IPv4 DNS servers the NAS itself asks, for the form's suggestion.
    def nameservers(path = RESOLV_CONF)
      File.foreach(path).filter_map do |line|
        server = line[/\Anameserver\s+(\S+)/, 1]
        server if server && IPAddr.new(server).ipv4?
      rescue IPAddr::Error
        nil
      end
    rescue SystemCallError
      []
    end

    # { 'state' => 'pending' | 'kept' | 'reverted', 'interface', 'mode', 'address', 'until', ... },
    # or nil before any change.
    def state
      JSON.parse(File.read(STATE))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # A change applied, or about to be, that nothing has reached yet.
    def pending?
      current = state
      current&.dig('state') == 'pending' && (current['until'].nil? || current['until'].to_i + 30 > Time.now.to_i)
    end

    # The last change, while it's recent enough to be worth a word.
    def recent
      current = state
      current if current && Time.now.to_i - current['since'].to_i < RECENT
    end

    # Asks the helper for the change. Without +guard+ (another interface than the admin came in
    # through) it's applied and kept at once, and what follows the address follows now.
    def change!(interface:, mode:, guard:, address: nil, gateway: nil, dns: [])
      args = { interface: interface, mode: mode, guard: guard }
      args.merge!(address: address, gateway: gateway.presence, dns: dns) if mode == 'fixed'
      Privileged.call('network.set_address', **args)
      settle! unless guard
    end

    # The NAS was reached at the new address: the change stays.
    def keep!
      Privileged.call('network.keep_address')
      settle!
    end

    # What's built on the NAS's address follows it: the net and self-address settings (Samba's
    # hosts allow, lmhosts, the aliases), then DNS, DHCP and the router's rules, and Samba.
    def settle!
      if (address = DnsService.lan_address)
        parts = address.to_s.split('.')
        Setting.set('net', parts.first(3).join('.'))
        Setting.set('self-address', parts.last)
      end
      DnsService.apply!
      SambaService.push_config
    end

    # The address a request came in on (Puma's socket), or nil (a test, a UNIX socket).
    def arrival_address(env)
      socket = env['puma.socket']
      return nil unless socket.respond_to?(:local_address)
      socket.local_address.ip_address.sub(/\A::ffff:/, '').sub(/%.*\z/, '')
    rescue SystemCallError, SocketError
      nil
    end

    # The interface a request came in through, by the address it arrived on.
    def arrival_interface(env)
      address = arrival_address(env) or return nil
      NetworkInterfaces.all.find { |_name, addresses| addresses.any? { |a| a.to_s == address } }&.first
    end
  end
end
