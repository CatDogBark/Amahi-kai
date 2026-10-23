# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'leases'

class NetworkController < ApplicationController
  before_action :admin_required
  before_action :set_page_title

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
    unless advanced?
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

  # DNS and DHCP are on Network → DNS & DHCP (DnsController); Remote Access and Security on
  # RemoteAccessController and SecurityController.

  private

  def set_page_title
    @page_title = t('network')
  end

  # Fixed hosts' addresses are on DHCP's network: the NAS's on the interface DNS & DHCP serves.
  def get_hosts
    @hosts = Host.order('name ASC')
    @net = DnsService.lan_prefix.presence
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
