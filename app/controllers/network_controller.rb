# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'leases'
require 'shell'
require 'dnsmasq_service'

class NetworkController < ApplicationController
  include SseStreaming

  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :set_page_title
  IP_RANGE = 10

  def index
    @leases = Leases.all rescue {}
  end

  def hosts
    get_hosts
  end

  def create_host
    @host = Host.create(params_host)
    get_hosts
    respond_to do |format|
      if @host.errors.any?
        format.html { render :hosts, status: :unprocessable_entity }
      else
        format.html { redirect_to network_hosts_path }
      end
      format.json
    end
  end

  def destroy_host
    @host = Host.find(params[:id])
    @host.destroy
    render json: { status: :ok, id: @host.id }
  end

  def dns_aliases
    unless @advanced
      redirect_to network_index_path
    else
      get_dns_aliases
    end
  end

  def create_dns_alias
    @dns_alias = DnsAlias.create(params_create_alias)
    get_dns_aliases
    respond_to do |format|
      if @dns_alias.errors.any?
        format.html { render :dns_aliases, status: :unprocessable_entity }
      else
        format.html { redirect_to network_dns_aliases_path }
      end
      format.json
    end
  end

  def destroy_dns_alias
    @dns_alias = DnsAlias.find(params[:id])
    @dns_alias.destroy
    render json: { status: :ok, id: @dns_alias.id }
  end

  def settings
    unless @advanced
      redirect_to network_index_path
    else
      @net = Setting.get 'net'
      @dns = Setting.find_or_create_by(KIND, 'dns', 'cloudflare')
      @dns_ip_1, @dns_ip_2 = DnsIpSetting.custom_dns_ips
      @dnsmasq_dhcp = Setting.find_or_create_by(KIND, 'dnsmasq_dhcp', '1')
      @dnsmasq_dns = Setting.find_or_create_by(KIND, 'dnsmasq_dns', '1')
      @lease_time = Setting.get("lease_time") || "14400"
      @gateway = Setting.find_or_create_by(KIND, 'gateway', '1').value
      @dyn_lo = Setting.find_or_create_by(KIND, 'dyn_lo', '100').value
      @dyn_hi = Setting.find_or_create_by(KIND, 'dyn_hi', '254').value
    end
  end

  def update_dns
    case params[:setting_dns]
    when 'cloudflare', 'google', 'custom'
      @saved = Setting.set("dns", params[:setting_dns], KIND)
      DnsmasqService.restart!
    else
      @saved = true
    end
    render json: { status: @saved ? :ok : :not_acceptable }
  end

  def update_dns_ips
    Setting.transaction do
      @ip_1_saved = DnsIpSetting.set("dns_ip_1", params[:dns_ip_1], KIND)
      @ip_2_saved = DnsIpSetting.set("dns_ip_2", params[:dns_ip_2], KIND)
      Setting.set("dns", 'custom', KIND)
      DnsmasqService.restart!
    end
    if @ip_1_saved && @ip_2_saved
      render json: { status: :ok }
    else
      render json: { status: :not_acceptable, ip_1_saved: @ip_1_saved, ip_2_saved: @ip_2_saved }
    end
  end

  def update_lease_time
    @saved = params[:lease_time].present? && params[:lease_time].to_i > 0 ? Setting.set("lease_time", params[:lease_time], KIND) : false
    render json: { status: @saved ? :ok : :not_acceptable }
    DnsmasqService.restart!
  end

  def update_gateway
    @saved = params[:gateway].to_i > 0 && params[:gateway].to_i < 255 ? Setting.set("gateway", params[:gateway], KIND) : false
    if @saved
      @net = Setting.get 'net'
      render json: { status: :ok, data: @net + '.' + params[:gateway] }
    else
      render json: { status: :not_acceptable }
    end
  end

  def toggle_setting
    id = params[:id]
    s = Setting.find(id)
    s.value = (1 - s.value.to_i).to_s
    if s.save
      render json: { status: 'ok' }
      DnsmasqService.restart!
    else
      render json: { status: 'error' }
    end
  end

  def update_dhcp_range
    if params[:id] == "min"
      dyn_lo = params[:dyn_lo].to_i
      dyn_hi = Setting.find_by_name("dyn_hi").value.to_i
    else
      dyn_lo = Setting.find_by_name("dyn_lo").value.to_i
      dyn_hi = params[:dyn_hi].to_i
    end
    @saved = dyn_lo > 0 && dyn_hi < 255 && dyn_hi - dyn_lo > IP_RANGE
    if @saved
      Setting.set("dyn_lo", dyn_lo, KIND)
      Setting.set("dyn_hi", dyn_hi, KIND)
      DnsmasqService.restart!
      render json: { status: :ok }
    else
      render json: { status: :not_acceptable }
    end
  end

  # --- Gateway (dnsmasq DHCP/DNS) ---

  def gateway
    unless @advanced
      redirect_to network_index_path
      return
    end
    @dnsmasq_installed = DnsmasqService.installed?
    @dnsmasq_running = DnsmasqService.running?
    @net = Setting.get('net') || '192.168.1'
    @gateway_ip = Setting.find_or_create_by(KIND, 'gateway', '1').value
    @dnsmasq_dhcp = Setting.find_or_create_by(KIND, 'dnsmasq_dhcp', '1')
    @dnsmasq_dns = Setting.find_or_create_by(KIND, 'dnsmasq_dns', '1')
    @dyn_lo = Setting.find_or_create_by(KIND, 'dyn_lo', '100').value
    @dyn_hi = Setting.find_or_create_by(KIND, 'dyn_hi', '254').value
    @lease_time = Setting.get("lease_time") || "14400"
    @dns = Setting.find_or_create_by(KIND, 'dns', 'cloudflare')
  end

  def install_dnsmasq
    redirect_to network_gateway_path
  end

  def install_dnsmasq_stream
    stream_sse do |sse|
      sse.send("Installing dnsmasq...")

      unless Rails.env.production?
        lines = [
          "Updating package lists...",
          "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
          "Installing dnsmasq...",
          "  Reading package lists...",
          "  Building dependency tree...",
          "  The following NEW packages will be installed:",
          "    dnsmasq dnsmasq-base",
          "  Setting up dnsmasq (2.90-4) ...",
          "Stopping dnsmasq (will not start until configured)...",
          "  Stopped.",
          "",
          "✓ dnsmasq installed successfully!",
          "  Configure DHCP/DNS settings below, then start the service."
        ]
        lines.each do |line|
          sleep 0.3
          sse.send(line)
        end
        sse.done
      else
        success = true

        steps = [
          { label: "Updating package lists...", cmd: "sudo apt-get update 2>&1" },
          { label: "Installing dnsmasq...", cmd: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq 2>&1" },
        ]

        steps.each do |step|
          sse.send(step[:label])
          IO.popen(step[:cmd]) do |io|
            io.each_line { |line| sse.send("  #{line.chomp}") }
          end
          unless $?.success?
            sse.send("  ✗ Command failed")
            success = false
            break
          end
        end

        if success
          sse.send("Stopping dnsmasq (safe until configured)...")
          DnsmasqService.stop!
          sse.send("  ✓ Stopped and disabled (configure settings, then start)")

          sse.send("")
          sse.send("✓ dnsmasq installed successfully!")
          sse.done
        else
          sse.send("✗ Installation failed.")
          sse.done("error")
        end
      end
    end
  end

  def start_dnsmasq
    DnsmasqService.start!
    redirect_to network_gateway_path
  end

  def stop_dnsmasq
    DnsmasqService.stop!
    redirect_to network_gateway_path
  end

  def update_dnsmasq_config
    net = Setting.get('net') || '192.168.1'

    Setting.set("dyn_lo", params[:dyn_lo], KIND) if params[:dyn_lo].present?
    Setting.set("dyn_hi", params[:dyn_hi], KIND) if params[:dyn_hi].present?
    Setting.set("lease_time", params[:lease_time], KIND) if params[:lease_time].present?
    Setting.set("gateway", params[:gateway], KIND) if params[:gateway].present?

    dhcp_enabled = params[:dhcp_enabled] == '1'
    dns_enabled = params[:dns_enabled] == '1'

    dyn_lo = (params[:dyn_lo] || Setting.get("dyn_lo") || "100").to_i
    dyn_hi = (params[:dyn_hi] || Setting.get("dyn_hi") || "254").to_i
    gateway = params[:gateway] || Setting.get("gateway") || "1"
    lease_time = (params[:lease_time] || Setting.get("lease_time") || "14400").to_i

    begin
      DnsmasqService.write_config!(
        net: net,
        dyn_lo: dyn_lo,
        dyn_hi: dyn_hi,
        gateway: gateway,
        lease_time: lease_time,
        domain: Setting.get('domain') || 'local',
        dhcp_enabled: dhcp_enabled,
        dns_enabled: dns_enabled
      )
      flash[:notice] = "Configuration saved"
      redirect_to network_gateway_path
    rescue StandardError => e
      flash[:alert] = "Failed to save: #{e.message}"
      redirect_to network_gateway_path
    end
  end

  # Remote Access and Security moved to RemoteAccessController and SecurityController

  private

  def set_page_title
    @page_title = t('network')
  end

  def get_hosts
    @hosts = Host.order('name ASC')
    @net = Setting.get 'net'
    @net ||= '192.168.1' if Rails.env.development?
  end

  def get_dns_aliases
    @dns_aliases = DnsAlias.order('name ASC')
    @net = Setting.get 'net'
    @net ||= '192.168.1' if Rails.env.development?
  end

  def params_create_alias
    params.require(:dns_alias).permit(:name, :address)
  end

  def params_host
    params.require(:host).permit(:name, :mac, :address)
  end
end
