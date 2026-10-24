# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'leases'

# Network → Devices: the devices the NAS gave addresses to (dnsmasq's leases) and the fixed
# addresses (Network → Hosts, before), in one list. DNS, DHCP and the router are DnsController's;
# Remote Access and Security have their own.
class NetworkController < ApplicationController
  before_action :admin_required
  before_action :set_page_title

  def index
    @net = DnsService.lan_prefix.presence || '192.168.1'
    @dhcp_on = DnsService.dhcp?
    @domain = DnsService.domain
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

  def create_host
    host = Host.new(params.require(:host).permit(:name, :mac, :address))
    if host.save
      flash[:notice] = "#{host.name} keeps #{DnsService.lan_prefix.presence || '192.168.1'}.#{host.address}."
    else
      flash[:alert] = "#{host.errors.full_messages.join('. ')}."
    end
    redirect_to network_index_path
  end

  def destroy_host
    host = Host.find(params[:id])
    host.destroy
    flash[:notice] = "#{host.name} no longer has a fixed address."
    redirect_to network_index_path
  end

  private

  def set_page_title
    @page_title = t('network')
  end
end
