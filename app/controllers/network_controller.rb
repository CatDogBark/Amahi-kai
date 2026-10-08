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

  def install_dnsmasq_stream
    stream_sse do |sse|
      sse.emit("Installing dnsmasq...")

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
          sse.emit(line)
        end
        sse.done
      else
        begin
          sse.emit("Installing dnsmasq (apt-get update, then install)...")
          Privileged.call('packages.install', packages: ['dnsmasq']) { |line| sse.emit("  #{line}") }

          sse.emit("Stopping dnsmasq (safe until configured)...")
          DnsmasqService.stop!
          sse.emit("  ✓ Stopped and disabled (configure settings, then start)")

          sse.emit("")
          sse.emit("✓ dnsmasq installed successfully!")
          sse.done
        rescue Privileged::Error => e
          sse.emit("  ✗ #{e.message}")
          sse.emit("✗ Installation failed.")
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
    Setting.set("dyn_lo", params[:dyn_lo], KIND) if params[:dyn_lo].present?
    Setting.set("dyn_hi", params[:dyn_hi], KIND) if params[:dyn_hi].present?
    Setting.set("lease_time", params[:lease_time], KIND) if params[:lease_time].present?
    Setting.set("gateway", params[:gateway], KIND) if params[:gateway].present?

    # Saved, so the form shows what was chosen (it used to forget the checkboxes) and later
    # rewrites (a static host added) keep them.
    Setting.set('dnsmasq_dhcp', params[:dhcp_enabled] == '1' ? '1' : '0', KIND)
    Setting.set('dnsmasq_dns', params[:dns_enabled] == '1' ? '1' : '0', KIND)

    begin
      DnsmasqService.write_config!(DnsmasqService.settings_options)
      flash[:notice] = "Configuration saved"
      redirect_to network_gateway_path
    rescue Privileged::Error => e
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
