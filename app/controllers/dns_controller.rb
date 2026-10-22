# Network → DNS & DHCP: Amahi-kai's DNS server for the network (Unbound, through DnsService),
# and in the mode "DNS + DHCP" its DHCP server too (dnsmasq, through DnsmasqService).

class DnsController < ApplicationController
  include SseStreaming

  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :advanced_required
  before_action :set_page_title

  def index
    @installed = DnsService.installed?
    @running = DnsService.running?
    @dnsmasq_installed = DnsmasqService.installed?
    @dnsmasq_running = DnsmasqService.running?
    @mode = DnsService.mode
    @provider = DnsService.provider
    @interfaces = NetworkInterfaces.lan
    @interface = DnsService.interface
    @addresses = DnsService.server_addresses
    @prefix = DnsService.lan_prefix
    @dhcp = DnsmasqService.settings
    @leases = DnsService.dhcp? ? (Leases.all rescue []) : []
    @domain = DnsService.domain
    @nas_name = "#{DnsService.hostname}.#{@domain}"
    @custom_addresses = DnsService.custom_addresses.join(' ')
    @custom_tls_name = DnsService.custom_tls_name
    @check = DnsService.check if @running && DnsService.on?
    @blocking = DnsService.blocking?
    @blocklists = DnsService.blocklists
    @allowlist = DnsService.allowlist
    @blocking_status = DnsService.blocking_status
    @refreshing = @blocking && DnsService.on? && DnsService.blocklists_refreshing?
    @paused_until = DnsService.paused_until if @blocking
  end

  def update
    mode = params[:mode].to_s
    provider = params[:provider].to_s
    interface = params[:interface].to_s
    dhcp = dhcp_params
    problems = problems_with(mode, provider, interface, dhcp)
    if problems.any?
      flash[:alert] = "#{problems.join('. ')}."
      return redirect_to dns_index_path
    end

    Setting.set('dns_mode', mode, KIND)
    Setting.set('dns_provider', provider, KIND)
    Setting.set('dns_interface', interface, KIND)
    if provider == 'custom'
      Setting.set('dns_custom_addresses', params[:custom_addresses].to_s.split(/[\s,]+/).reject(&:empty?).join(' '), KIND)
      Setting.set('dns_custom_tls_name', params[:custom_tls_name].to_s.strip.downcase, KIND)
    end
    if mode == 'dns_dhcp'
      { 'dyn_lo' => :first, 'dyn_hi' => :last, 'gateway' => :router, 'lease_time' => :lease_time }.each do |name, key|
        Setting.set(name, dhcp[key].to_s, KIND)
      end
    end
    DnsService.apply!
    flash[:notice] = { 'off' => 'DNS and DHCP are off.', 'dns' => 'Saved. Unbound is answering with these settings.',
                       'dns_dhcp' => 'Saved. Unbound is answering, and dnsmasq is handing out addresses.' }.fetch(mode)
    redirect_to dns_index_path
  rescue Privileged::Error => e
    flash[:alert] = "Saved, but it couldn't be applied: #{e.message}"
    redirect_to dns_index_path
  end

  # Network → DNS & DHCP's Blocking card: on or off, the lists and the allowlist. Applied now
  # while DNS is on, else when it's turned on.
  def update_blocking
    on = params[:blocking] == '1'
    lists = Array(params[:lists]).map(&:to_s) & DnsService::BLOCKLISTS.keys
    allow, problems = DnsService.parse_allowlist(params[:allowlist])
    problems << 'Choose at least one list' if on && lists.empty?
    if problems.any?
      flash[:alert] = "#{problems.join('. ')}."
      return redirect_to dns_index_path
    end

    Setting.set('dns_blocking', on ? '1' : '0', KIND)
    Setting.set('dns_blocklists', lists.join(' '), KIND)
    Setting.set('dns_allowlist', allow.join("\n"), KIND)
    Setting.set('dns_blocking_paused_until', '0', KIND) unless on
    DnsService.apply_blocking! if DnsService.on? && DnsService.installed?
    flash[:notice] = if !on then 'Blocking is off.'
                     elsif DnsService.on? then "Saved. The lists are downloading; blocking starts when they're in."
                     else 'Saved. Blocking starts when DNS is on.'
                     end
    redirect_to dns_index_path
  rescue Privileged::Error => e
    flash[:alert] = "Saved, but it couldn't be applied: #{e.message}"
    redirect_to dns_index_path
  end

  def pause_blocking
    reply = Privileged.call('dns.pause_blocking')
    Setting.set('dns_blocking_paused_until', reply['until'].to_i.to_s, KIND)
    flash[:notice] = "Blocking is paused until #{Time.at(reply['until'].to_i).strftime('%H:%M')}."
    redirect_to dns_index_path
  rescue Privileged::Error => e
    flash[:alert] = "Couldn't pause blocking: #{e.message}"
    redirect_to dns_index_path
  end

  def resume_blocking
    Privileged.call('dns.resume_blocking')
    Setting.set('dns_blocking_paused_until', '0', KIND)
    flash[:notice] = 'Blocking is back on.'
    redirect_to dns_index_path
  rescue Privileged::Error => e
    flash[:alert] = "Couldn't resume blocking: #{e.message}"
    redirect_to dns_index_path
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

  def problems_with(mode, provider, interface, dhcp)
    problems = []
    problems << 'Choose Off, DNS for my network, or DNS + DHCP' unless DnsService::MODES.include?(mode)
    problems << 'Choose a provider' unless DnsService::PROVIDERS.key?(provider) || provider == 'custom'
    problems.concat(DnsService.custom_problems(params[:custom_addresses], params[:custom_tls_name])) if provider == 'custom'
    interfaces = NetworkInterfaces.lan
    if !interfaces.key?(interface)
      problems << 'Choose the network interface DNS serves'
    elsif mode != 'off' && interfaces[interface].none?(&:ipv4?)
      problems << "#{interface} has no IPv4 address for devices to use"
    end
    problems << 'Install Unbound first' if mode != 'off' && !DnsService.installed?
    return problems unless mode == 'dns_dhcp' && problems.empty?

    dhcp_problems(interface, interfaces[interface], dhcp)
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
