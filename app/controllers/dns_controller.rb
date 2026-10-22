# Network → DNS: Amahi-kai's DNS server for the network (Unbound, through DnsService).

class DnsController < ApplicationController
  include SseStreaming

  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :set_page_title

  def index
    @installed = DnsService.installed?
    @running = DnsService.running?
    @mode = DnsService.mode
    @provider = DnsService.provider
    @interfaces = NetworkInterfaces.lan
    @interface = DnsService.interface
    @addresses = DnsService.server_addresses
    @domain = DnsService.domain
    @nas_name = "#{DnsService.hostname}.#{@domain}"
    @custom_addresses = DnsService.custom_addresses.join(' ')
    @custom_tls_name = DnsService.custom_tls_name
    @check = DnsService.check if @running && DnsService.on?
  end

  def update
    mode = params[:mode].to_s
    provider = params[:provider].to_s
    interface = params[:interface].to_s
    problems = problems_with(mode, provider, interface)
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
    DnsService.apply!
    flash[:notice] = mode == 'off' ? 'DNS is off.' : 'Saved. Unbound is answering with these settings.'
    redirect_to dns_index_path
  rescue Privileged::Error => e
    flash[:alert] = "Saved, but it couldn't be applied: #{e.message}"
    redirect_to dns_index_path
  end

  def install_stream
    stream_sse do |sse|
      sse.emit('Installing Unbound...')

      unless Rails.env.production?
        ['Updating package lists...', '  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease',
         'Installing unbound dns-root-data...', '  Setting up unbound (1.19.2-1ubuntu3) ...',
         'Stopping Unbound (it starts when DNS is turned on)...', '', '✓ Unbound installed.'].each do |line|
          sleep 0.3
          sse.emit(line)
        end
        sse.done
        next
      end

      begin
        Privileged.call('packages.install', packages: DnsService::PACKAGES) { |line| sse.emit("  #{line}") }
        # Ubuntu's package starts Unbound on the NAS's own address; it waits for DNS to be on.
        sse.emit('Stopping Unbound (it starts when DNS is turned on)...')
        Privileged.call('services.disable', service: 'unbound') unless DnsService.on?
        sse.emit('')
        sse.emit('✓ Unbound installed.')
        sse.done
      rescue Privileged::Error => e
        sse.emit("  ✗ #{e.message}")
        sse.emit('✗ Installation failed.')
        sse.done('error')
      end
    end
  end

  private

  def set_page_title
    @page_title = t('network')
  end

  def problems_with(mode, provider, interface)
    problems = []
    problems << 'Choose whether DNS is on' unless DnsService::MODES.include?(mode)
    problems << 'Choose a provider' unless DnsService::PROVIDERS.key?(provider) || provider == 'custom'
    problems.concat(DnsService.custom_problems(params[:custom_addresses], params[:custom_tls_name])) if provider == 'custom'
    interfaces = NetworkInterfaces.lan
    if !interfaces.key?(interface)
      problems << 'Choose the network interface DNS serves'
    elsif mode != 'off' && interfaces[interface].none?(&:ipv4?)
      problems << "#{interface} has no IPv4 address for devices to use"
    end
    problems << 'Install Unbound first' if mode != 'off' && !DnsService.installed?
    problems
  end
end
