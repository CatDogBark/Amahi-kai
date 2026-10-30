# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'leases'
require 'network_address'
require 'network_ports'

# Network → Devices: the NAS's own address on each interface (This NAS), and the devices the NAS
# gave addresses to (dnsmasq's leases) with the fixed addresses (Network → Hosts, before), in one
# list. DNS, DHCP and the router are DnsController's; Remote Access and Security have their own.
class NetworkController < ApplicationController
  before_action :admin_required, except: :address_reached
  before_action :set_page_title
  # The moving page's probe comes from a browser whose session cookie is for the old address,
  # and it can do nothing but keep a change already waiting (address_reached).
  skip_before_action :verify_authenticity_token, :check_setup_completed, only: :address_reached

  def index
    @net = DnsService.lan_prefix.presence || '192.168.1'
    @dhcp_on = DnsService.dhcp?
    @domain = DnsService.domain
    @interfaces = NetworkAddress.interfaces
    @ports = NetworkPorts.all(@interfaces.map(&:name))
    @nameservers = NetworkAddress.nameservers
    @router_mode = DnsService.router?
    @dhcp_interface = @dhcp_on ? DnsService.interface : nil
    @address_note = address_note
    hosts = Host.order('name ASC')
    by_mac = hosts.index_by { |host| host.mac.downcase }
    leases = (Leases.all rescue [])
    # A row per device seen, with its fixed address if it has one; then the fixed addresses of
    # devices not seen now.
    @devices = leases.map do |lease|
      mac = lease[:mac].to_s.downcase
      { name: lease[:name].to_s == '*' ? nil : lease[:name], mac: mac, ip: lease[:ip], expires: Time.at(lease[:expiration]), host: by_mac[mac] }
    end
    seen = @devices.map { |device| device[:mac] }
    @unseen_hosts = hosts.reject { |host| seen.include?(host.mac.downcase) }
  end

  # This NAS: an interface's own address. A change to the interface this request came in through
  # is applied after the reply and kept only once the NAS is reached at the new address
  # (address_reached), so a wrong one can't lock the admin out: the page shown meanwhile tries
  # the new address, and the helper puts the old one back after NetworkAddress::WAIT seconds
  # otherwise. A change to another interface is applied and kept at once.
  def update_address
    interface = params[:interface].to_s
    row = NetworkAddress.interfaces.find { |each| each.name == interface }
    return refuse("#{interface} isn't a network interface here") unless row
    return refuse("#{interface} is the internet side; Network → Internet manages it") if row.part == :internet
    mode = params[:mode].to_s
    return refuse('Choose an automatic or a fixed address') unless NetworkAddress::MODES.include?(mode)
    dhcp_here = DnsService.dhcp? && interface == DnsService.interface
    if mode == 'automatic' && dhcp_here
      return refuse("The NAS hands out addresses on #{interface} (Network → DHCP), so it needs a fixed one there")
    end
    prefix = params[:prefix].to_s.strip.presence || '24'
    # DHCP's range and the fixed devices' addresses are the last part of an address on a /24.
    if mode == 'fixed' && dhcp_here && prefix != '24'
      return refuse("The NAS hands out addresses on #{interface} (Network → DHCP), which works on a /24 network: keep the prefix at 24 there")
    end
    address = gateway = nil
    dns = []
    if mode == 'fixed'
      address = "#{params[:address].to_s.strip}/#{prefix}"
      # The NAS is the router: its LAN interface has no router of its own.
      gateway = params[:gateway].to_s.strip.presence unless DnsService.router? && interface == DnsService.interface
      dns = params[:dns].to_s.split(/[\s,]+/).reject(&:blank?)
    end
    arrival = NetworkAddress.arrival_interface(request.env)
    # Through the tunnel or Tailscale, the way in runs over the port with the default route, and
    # the guard can't watch for the browser coming back: a wrong address there would cut the
    # admin off for good. That one is changed from the LAN.
    if %w[lo tailscale0].include?(arrival) && NetworkInterfaces.default_routes.any? { |name, _gateway, _metric| name == interface }
      over = arrival == 'lo' ? 'the Cloudflare Tunnel' : 'Tailscale'
      return refuse("You're connected through #{over}, which runs over #{interface}: a wrong address there would cut you off " \
                    'with nothing to put it back. Change it from a computer on your LAN, where the NAS can check that you still reach it')
    end
    guard = arrival == interface
    NetworkAddress.change!(interface: interface, mode: mode, guard: guard, address: address, gateway: gateway, dns: dns)
    if guard
      @interface = interface
      @mode = mode
      @new_host = mode == 'fixed' ? address.split('/').first : "#{SystemInfo.hostname}.local"
      @until = Time.now.to_i + NetworkAddress::APPLY_WAIT + NetworkAddress::WAIT
      # The page's probe calls the NAS at the new address, another origin, which the site's
      # Content-Security-Policy (connect-src 'self') would forbid: this page alone may call it.
      if (policy = request.content_security_policy&.clone)
        policy.connect_src(:self, helpers.amahi_url(@new_host).chomp('/'))
        request.content_security_policy = policy
      end
      render 'moving'
    else
      flash[:notice] = mode == 'fixed' ? "#{interface} is at #{address.split('/').first}." : "#{interface} takes its address from the network again."
      redirect_to network_index_path
    end
  rescue Privileged::Error => e
    refuse(e.message)
  end

  # The NAS was reached at its new address (the moving page's probe, or the admin arriving): the
  # change waiting is kept. No sign-in, since the browser's cookie is for the old address; it
  # does nothing unless a change is waiting, and only for a request that came in through the
  # changed interface, which is what reaching the NAS there means.
  def address_reached
    state = NetworkAddress.state
    NetworkAddress.keep! if NetworkAddress.pending? && NetworkAddress.arrival_interface(request.env) == state['interface']
    head :no_content
  rescue Privileged::Error => e
    Rails.logger.warn("address_reached: #{e.message}")
    head :no_content
  end

  # Where the last change stands, for the moving page (which may still reach the old address
  # through another interface).
  def address_status
    render json: (NetworkAddress.state || {}).slice('state', 'interface', 'mode', 'address', 'until', 'since')
  end

  # This NAS: the name the admin gives a port, shown beside it wherever a port is named.
  def update_port_label
    interface = params[:interface].to_s
    return refuse("#{interface} isn't a network interface here") unless NetworkInterfaces.lan.key?(interface)
    label = NetworkPorts.set_label!(interface, params[:label])
    flash[:notice] = label ? "#{interface} is #{label}." : "#{interface} has no name of its own."
    redirect_to network_index_path
  rescue ArgumentError => e
    refuse(e.message.sub(/\A./, &:upcase))
  end

  # This NAS: a real port's light blinks for five seconds (the helper, with ethtool), to find
  # its socket on the NAS.
  def blink_port
    interface = params[:interface].to_s
    return refuse("#{interface} isn't a network interface here") unless NetworkInterfaces.lan.key?(interface)
    NetworkPorts.blink!(interface)
    flash[:notice] = "#{NetworkPorts.display(interface)}'s light blinked for five seconds."
    redirect_to network_index_path
  rescue Privileged::Error => e
    refuse(e.message)
  end

  # A fixed address for a device (Fix this address, or the form): a device already named keeps its
  # name unless another is given. Without an address, the form only names it.
  def create_host
    values = params.require(:host).permit(:name, :mac, :address)
    host = known_host(values[:mac]) || Host.new(mac: values[:mac])
    host.assign_attributes(values.slice(:name, :address).to_h.select { |_key, value| value.present? || host.new_record? })
    if host.save
      flash[:notice] = host.fixed? ? "#{host.name} keeps #{lan_prefix}.#{host.address}." : named_notice(host)
    else
      flash[:alert] = "#{host.errors.full_messages.join('. ')}."
    end
    redirect_to network_index_path
  end

  # A name for a device, without a fixed address: DHCP gives it the name wherever it puts it, and
  # DNS answers by it at once (the helper's dns.sync_leases). A device already known is renamed.
  def name_host
    values = params.require(:host).permit(:name, :mac)
    host = known_host(values[:mac]) || Host.new(mac: values[:mac])
    host.name = values[:name].to_s.strip
    if host.save
      flash[:notice] = named_notice(host)
    else
      flash[:alert] = "#{host.errors.full_messages.join('. ')}."
    end
    redirect_to network_index_path
  end

  # Unfix: the device keeps its name, and takes whatever address DHCP gives it from now on.
  def destroy_host
    host = Host.find(params[:id])
    was_lan_only = host.lan_only
    host.update!(address: nil, lan_only: false)
    done = "#{host.name} no longer has a fixed address; its name stays with it"
    # A device kept off the internet loses its rule with the address.
    problem = DnsService.rewrite_router_problem if was_lan_only
    if problem
      flash_failure("#{done}, but the router's rules weren't rewritten (#{problem}), so its address stays kept off the internet until a save " \
                    'on Network → Internet puts them in place.')
    else
      flash[:notice] = "#{done}."
    end
    redirect_to network_index_path
  end

  # Forget: the device's name goes too (a device only named; one with a fixed address is unfixed
  # first).
  def forget_host
    host = Host.find(params[:id])
    if host.fixed?
      flash[:alert] = "#{host.name} has a fixed address: unfix it first."
    else
      host.destroy
      flash[:notice] = "#{host.name} is forgotten: the device answers by the name it asks for again."
    end
    redirect_to network_index_path
  end

  # LAN only: a device with a fixed address keeps the LAN (the shares, DNS, the NAS) but can't
  # reach the internet through the NAS, by a router rule on its address, rewritten here while the
  # NAS is the router (otherwise the flag waits for router mode). When the rules can't follow, the
  # page says the device is still as it was.
  def toggle_lan_only
    host = Host.find(params[:id])
    unless host.update(lan_only: !host.lan_only)
      flash[:alert] = "#{host.errors.full_messages.join('. ')}."
      return redirect_to network_index_path
    end
    if (problem = DnsService.rewrite_router_problem)
      flash_failure("#{host.name} is saved as #{host.lan_only ? 'LAN only' : 'reaching the internet'}, but the router's rules weren't rewritten " \
                    "(#{problem}), so it #{host.lan_only ? 'still reaches the internet' : 'is still kept off the internet'} until a save on " \
                    'Network → Internet puts them in place.')
    else
      flash[:notice] = if host.lan_only
                         "#{host.name} can't reach the internet#{' once the NAS is the router' unless DnsService.router?}; the LAN still works for it."
                       else
                         "#{host.name} reaches the internet again."
                       end
    end
    redirect_to network_index_path
  end

  private

  def set_page_title
    @page_title = t('network')
  end

  # The device known by this hardware address, in whatever case it was saved.
  def known_host(mac)
    Host.where('LOWER(mac) = ?', mac.to_s.strip.downcase).first
  end

  def lan_prefix
    DnsService.lan_prefix.presence || '192.168.1'
  end

  def named_notice(host)
    where = DnsService.dhcp? ? 'wherever it is' : 'once the NAS hands out addresses (Network → DHCP)'
    "#{host.name} answers by its name #{where}: #{host.name}.#{DnsService.domain}."
  end

  def refuse(problem)
    flash[:alert] = "#{problem}."
    redirect_to network_index_path
  end

  # A word on the last change to the NAS's address, while it's recent.
  def address_note
    change = NetworkAddress.recent or return nil
    where = change['mode'] == 'fixed' ? change['address'].to_s.split('/').first : 'an address from the network'
    case change['state']
    when 'pending' then "#{change['interface']} is moving to #{where}; the change is kept once the NAS is reached there."
    when 'kept' then "#{change['interface']} moved to #{where}."
    when 'reverted' then "#{change['interface']} went back: nothing reached the NAS at #{where} in time."
    end
  end
end
