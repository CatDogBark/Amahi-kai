# Network → DNS, DHCP and Internet: Amahi-kai's DNS server (Unbound, through DnsService), its
# DHCP server (dnsmasq, through DnsmasqService) and the NAS as the router. One controller, since
# the three share the LAN interface and the mode (DnsService::MODES): DHCP needs DNS on, and the
# router needs DHCP on.

class DnsController < ApplicationController
  include SseStreaming

  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :advanced_required
  before_action :set_page_title

  # Network → DNS
  def index
    load_common
    @custom_addresses = DnsService.custom_addresses.join(' ')
    @custom_tls_name = DnsService.custom_tls_name
    @check = DnsService.check if @running && @dns_on
    @totals = DnsService.totals if @running && @dns_on
    @ipv6_address = DnsService.ipv6_server_address
    @blocking = DnsService.blocking?
    @blocklists = DnsService.blocklists
    @allowlist = DnsService.allowlist
    @blocking_status = DnsService.blocking_status
    @refreshing = @blocking && @dns_on && DnsService.blocklists_refreshing?
    @paused_until = DnsService.paused_until if @blocking
    @aliases = DnsAlias.order(:name)
  end

  def update
    on = params[:dns_on] == '1'
    provider = params[:provider].to_s
    interface = params[:interface].to_s
    problems = dns_problems(on, provider, interface)
    return refuse(problems, dns_index_path) if problems.any?

    was = DnsService.mode
    Setting.set('dns_mode', on ? (was == 'off' ? 'dns' : was) : 'off', KIND)
    Setting.set('dns_provider', provider, KIND)
    Setting.set('dns_interface', interface, KIND)
    if provider == 'custom'
      Setting.set('dns_custom_addresses', params[:custom_addresses].to_s.split(/[\s,]+/).reject(&:empty?).join(' '), KIND)
      Setting.set('dns_custom_tls_name', params[:custom_tls_name].to_s.strip.downcase, KIND)
    end
    DnsService.apply!
    flash[:notice] = if on then 'Saved. Unbound is answering with these settings.'
                     elsif was == 'off' then 'DNS is off.'
                     elsif was == 'dns' then 'DNS is off.'
                     else 'DNS is off, and with it DHCP and the router.'
                     end
    redirect_to dns_index_path
  rescue Privileged::Error => e
    not_applied(e, dns_index_path)
  end

  # Network → DHCP
  def dhcp
    load_common
    @dnsmasq_installed = DnsmasqService.installed?
    @dnsmasq_running = DnsmasqService.running?
    @dhcp_on = DnsService.dhcp?
    @router_on = DnsService.router?
    @dhcp = DnsmasqService.settings
    @leases = @dhcp_on ? (Leases.all rescue []) : []
  end

  def update_dhcp
    on = params[:dhcp_on] == '1'
    if on
      return refuse(['Turn DNS on first (Network → DNS): DHCP hands out the NAS as the DNS server'], dns_dhcp_path) unless DnsService.on?

      dhcp = dhcp_params
      interface = DnsService.interface
      problems = dhcp_problems(interface, NetworkInterfaces.lan[interface] || [], dhcp)
      return refuse(problems, dns_dhcp_path) if problems.any?

      { 'dyn_lo' => :first, 'dyn_hi' => :last, 'gateway' => :router, 'lease_time' => :lease_time }.each do |name, key|
        Setting.set(name, dhcp[key].to_s, KIND)
      end
      Setting.set('dns_mode', DnsService.router? ? 'router' : 'dns_dhcp', KIND)
    else
      was_router = DnsService.router?
      Setting.set('dns_mode', DnsService.on? ? 'dns' : 'off', KIND)
    end
    DnsService.apply!
    flash[:notice] = if on then 'Saved. dnsmasq is handing out addresses.'
                     elsif was_router then 'DHCP is off, and with it the router.'
                     else 'DHCP is off.'
                     end
    redirect_to dns_dhcp_path
  rescue Privileged::Error => e
    not_applied(e, dns_dhcp_path)
  end

  # Network → Internet
  def internet
    load_common
    @dhcp_on = DnsService.dhcp?
    @router_on = DnsService.router?
    @wan_interface = DnsService.wan_interface
    @router_state = DnsService.router_state
    @wan_addresses = NetworkInterfaces.addresses(@wan_interface.to_s).select(&:ipv4?).map(&:to_s)
    @default_route = NetworkInterfaces.default_route
    @firewall_on = DnsService.firewall_on?
    @forwards = PortForward.order(:protocol, :port)
    @wan_drops = DnsService.wan_drops
    @spoof_drops = DnsService.spoof_drops
    @lan_only = Host.where(lan_only: true).order(:name)
    @force_dns = DnsService.force_dns?
    @tailscale_installed = DnsService.tailscale_installed?
    @blocking = DnsService.blocking?
    @ipv6_advertise = DnsService.ipv6_advertise?
    @radvd_installed = DnsService.radvd_installed?
    @ipv6_address = DnsService.ipv6_server_address
    @own_ipv6_address = DnsService.own_ipv6_address
    @ipv6_check = DnsService.ipv6_check
    @other_ipv6_dns = DnsService.other_ipv6_dns(@ipv6_check)
  end

  def update_internet
    on = params[:router_on] == '1'
    advertise = params[:ipv6_advertise] == '1'
    problems = []
    problems << 'Install radvd first, to announce the NAS over IPv6' if advertise && !DnsService.radvd_installed?
    if on
      problems << 'Turn DHCP on first (Network → DHCP): the router hands out the way to the internet along with the addresses' unless DnsService.dhcp?
      problems.concat(router_problems(DnsService.interface, NetworkInterfaces.lan)) if problems.empty?
    end
    return refuse(problems, dns_internet_path) if problems.any?

    Setting.set('dns_ipv6_advertise', advertise ? '1' : '0', KIND)
    if on
      Setting.set('dns_wan_interface', params[:wan_interface].to_s, KIND)
      Setting.set('dns_force_nas', params[:force_dns] == '1' ? '1' : '0', KIND)
      Setting.set('dns_mode', 'router', KIND)
    elsif DnsService.router?
      Setting.set('dns_mode', 'dns_dhcp', KIND)
    end
    DnsService.apply!
    flash[:notice] = on ? 'Saved. The NAS is the router: DNS, addresses, and the way to the internet.' : 'Saved. The NAS is not the router.'
    redirect_to dns_internet_path
  rescue Privileged::Error => e
    not_applied(e, dns_internet_path)
  end

  # Network → DNS's Blocking card: on or off, the lists and the allowlist. Applied now while DNS
  # is on, else when it's turned on.
  def update_blocking
    on = params[:blocking] == '1'
    lists = Array(params[:lists]).map(&:to_s) & DnsService::BLOCKLISTS.keys
    allow, problems = DnsService.parse_allowlist(params[:allowlist])
    problems << 'Choose at least one list' if on && lists.empty?
    return refuse(problems, dns_index_path(anchor: 'dns-blocking')) if problems.any?

    Setting.set('dns_blocking', on ? '1' : '0', KIND)
    Setting.set('dns_blocklists', lists.join(' '), KIND)
    Setting.set('dns_allowlist', allow.join("\n"), KIND)
    Setting.set('dns_blocking_paused_until', '0', KIND) unless on
    DnsService.apply_blocking! if DnsService.on? && DnsService.installed?
    flash[:notice] = if !on then 'Blocking is off.'
                     elsif DnsService.on? then "Saved. The lists are downloading; blocking starts when they're in."
                     else 'Saved. Blocking starts when DNS is on.'
                     end
    redirect_to dns_index_path(anchor: 'dns-blocking')
  rescue Privileged::Error => e
    not_applied(e, dns_index_path(anchor: 'dns-blocking'))
  end

  def pause_blocking
    reply = Privileged.call('dns.pause_blocking')
    Setting.set('dns_blocking_paused_until', reply['until'].to_i.to_s, KIND)
    # How long, not until when: the server's clock may be in another time zone than the browser.
    flash[:notice] = "Blocking is paused for #{helpers.distance_of_time_in_words(Time.now, Time.at(reply['until'].to_i))}."
    redirect_to dns_index_path(anchor: 'dns-blocking')
  rescue Privileged::Error => e
    flash[:alert] = "Couldn't pause blocking: #{e.message}"
    redirect_to dns_index_path(anchor: 'dns-blocking')
  end

  def resume_blocking
    Privileged.call('dns.resume_blocking')
    Setting.set('dns_blocking_paused_until', '0', KIND)
    flash[:notice] = 'Blocking is back on.'
    redirect_to dns_index_path(anchor: 'dns-blocking')
  rescue Privileged::Error => e
    flash[:alert] = "Couldn't resume blocking: #{e.message}"
    redirect_to dns_index_path(anchor: 'dns-blocking')
  end

  # DNS aliases: extra names on the network (Network → DNS).
  def create_alias
    dns_alias = DnsAlias.new(params.require(:dns_alias).permit(:name, :address))
    if dns_alias.save
      flash[:notice] = "#{dns_alias.name}.#{DnsService.domain} points at #{dns_alias.address.presence || 'the NAS'}."
    else
      flash[:alert] = "#{dns_alias.errors.full_messages.join('. ')}."
    end
    redirect_to dns_index_path(anchor: 'dns-aliases')
  end

  def destroy_alias
    dns_alias = DnsAlias.find(params[:id])
    dns_alias.destroy
    flash[:notice] = "#{dns_alias.name} is no longer a name here."
    redirect_to dns_index_path(anchor: 'dns-aliases')
  end

  # Port forwards (router mode): a port on the internet side let in to a device on the LAN.
  def create_forward
    forward = PortForward.new(params.require(:port_forward).permit(:name, :protocol, :port, :address, :to_port))
    if forward.save
      flash[:notice] = "Forwarding #{forward.label} to #{DnsService.lan_prefix}.#{forward.address}."
    else
      flash[:alert] = "#{forward.errors.full_messages.join('. ')}."
    end
    redirect_to dns_internet_path(anchor: 'dns-forwards')
  end

  def destroy_forward
    forward = PortForward.find(params[:id])
    forward.destroy
    flash[:notice] = "No longer forwarding #{forward.label}."
    redirect_to dns_internet_path(anchor: 'dns-forwards')
  end

  # Asks the network's IPv6 routers what they announce (about 4 seconds).
  def check_routers
    DnsService.check_routers!
    redirect_to dns_internet_path(anchor: 'dns-ipv6')
  rescue Privileged::Error => e
    flash[:alert] = "Couldn't ask the IPv6 routers: #{e.message}"
    redirect_to dns_internet_path(anchor: 'dns-ipv6')
  end

  def install_radvd_stream
    install(%w[radvd], 'radvd', 'radvd', 'the NAS announces itself') { DnsService.on? && DnsService.ipv6_advertise? }
  end

  def install_stream
    install(DnsService::PACKAGES, 'Unbound', 'unbound', 'DNS is turned on') { DnsService.on? }
  end

  # dnsmasq's config is written first, answering no DNS, so the package doesn't start it on
  # port 53 when it's installed.
  def install_dnsmasq_stream
    install(DnsmasqService::PACKAGES, 'dnsmasq', 'dnsmasq', 'DHCP is turned on', before: -> { DnsmasqService.write_config!(DnsmasqService.options) }) do
      DnsService.dhcp?
    end
  end

  private

  def set_page_title
    @page_title = t('network')
  end

  def advanced_required
    redirect_to network_index_path unless advanced?
  end

  # What every one of the three pages shows.
  def load_common
    @installed = DnsService.installed?
    @running = DnsService.running?
    @mode = DnsService.mode
    @dns_on = DnsService.on?
    @provider = DnsService.provider
    @interfaces = NetworkInterfaces.lan
    @interface = DnsService.interface
    @addresses = DnsService.server_addresses
    @prefix = DnsService.lan_prefix
    @domain = DnsService.domain
    @nas_name = "#{DnsService.hostname}.#{@domain}"
  end

  def refuse(problems, path)
    flash[:alert] = "#{problems.join('. ')}."
    redirect_to path
  end

  def not_applied(error, path)
    flash[:alert] = "Saved, but it couldn't be applied: #{error.message}"
    redirect_to path
  end

  # Installs +packages+ through the root helper, then leaves +service+ stopped unless the block
  # says it's needed. Streams the progress to the install window.
  def install(packages, name, service, waits_for, before: nil)
    stream_sse do |sse|
      sse.emit("Installing #{name}...")

      unless Rails.env.production?
        ['Updating package lists...', '  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease',
         "Installing #{packages.join(' ')}...", "  Setting up #{packages.first} ...",
         "Stopping #{name} (it starts when #{waits_for})...", '', "✓ #{name} installed."].each do |line|
          sleep 0.3
          sse.emit(line)
        end
        sse.done
        next
      end

      begin
        before&.call
        Privileged.call('packages.install', packages: packages) { |line| sse.emit("  #{line}") }
        # Ubuntu's packages start their service when installed; it waits until it's needed.
        unless yield
          sse.emit("Stopping #{name} (it starts when #{waits_for})...")
          Privileged.call('services.disable', service: service)
        end
        sse.emit('')
        sse.emit("✓ #{name} installed.")
        sse.done
      rescue Privileged::Error => e
        sse.emit("  ✗ #{e.message}")
        sse.emit('✗ Installation failed.')
        sse.done('error')
      end
    end
  end

  def dhcp_params
    { first: params[:dhcp_first].to_i, last: params[:dhcp_last].to_i, router: params[:dhcp_router].to_i,
      lease_time: params[:lease_time].to_i }
  end

  def dns_problems(on, provider, interface)
    problems = []
    problems << 'Choose a provider' unless DnsService::PROVIDERS.key?(provider) || provider == 'custom'
    problems.concat(DnsService.custom_problems(params[:custom_addresses], params[:custom_tls_name])) if provider == 'custom'
    interfaces = NetworkInterfaces.lan
    if !interfaces.key?(interface)
      problems << 'Choose the network interface DNS serves'
    elsif on && interfaces[interface].none?(&:ipv4?)
      problems << "#{interface} has no IPv4 address for devices to use"
    end
    problems << 'Install Unbound first' if on && !DnsService.installed?
    problems
  end

  # The router needs a second interface for the internet, the firewall on, and not to be set up
  # through the interface that's about to face the internet (that would lock the admin out).
  def router_problems(lan, interfaces)
    wan = params[:wan_interface].to_s
    return ['Choose the interface the internet is on'] unless interfaces.key?(wan)
    return ['The internet interface must differ from the one DNS and DHCP serve'] if wan == lan
    return ["Turn the firewall on first (Network → Security, the firewall's Fix): it's what keeps the internet out of the NAS"] unless DnsService.firewall_on?

    from = IPAddr.new(request.remote_ip)
    if interfaces[wan].any? { |address| address.ipv4? && IPAddr.new(address.network).include?(from) }
      return ["You're connected through #{wan}, which would become the internet side and stop answering you. Connect from the LAN side first"]
    end

    []
  rescue IPAddr::Error
    []
  end

  # DHCP needs dnsmasq, a /24 network, settings that fit it, and no other DHCP server answering
  # there (it asks, the way a device would).
  def dhcp_problems(interface, addresses, dhcp)
    return ['Install dnsmasq first'] unless DnsmasqService.installed?

    lan = addresses.find { |address| address.ipv4? && address.prefix == 24 }
    return ["DHCP needs #{interface}'s network to be a /24 (like 192.168.1.x)"] unless lan

    own = lan.to_s.split('.').last.to_i
    problems = DnsmasqService.settings_problems(dhcp[:first], dhcp[:last], dhcp[:router], dhcp[:lease_time], own)
    return problems if problems.any?

    servers = DnsmasqService.other_servers(interface)
    return [] if servers.empty?

    ["Another DHCP server answers on #{interface} (#{servers.join(', ')}). Turn it off first (on most routers it's " \
     'in the LAN or DHCP settings), then save again']
  rescue Privileged::Error => e
    ["Couldn't check for another DHCP server: #{e.message}"]
  end
end
