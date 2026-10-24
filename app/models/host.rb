# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."

class Host < ApplicationRecord

  before_save :convert_address
  # dnsmasq hands out static addresses from its config, and Unbound answers for their names
  # (Network → DNS & DHCP), so a change rewrites both; LAN only is a rule of the router's.
  after_commit :rewrite_dnsmasq_config, :rewrite_dns, :apply_router_rules

  # A hostname label: at most 63 characters.
  validates :name, presence: true, format: { with: /\A[a-z][a-z0-9-]{0,62}\z/i }, uniqueness: true
  validates :mac, presence: true, uniqueness: true, format: { with: /\A([0-9a-f]{2}:){5}([0-9a-f]{2})\z/i }
  validates :address, presence: true, uniqueness: true, numericality: { greater_than: 0, less_than: 255, only_integer: true }

  # The devices kept off the internet (Network → Devices, LAN only), as their addresses on
  # +prefix+'s network, for the router's rules.
  def self.lan_only_addresses(prefix)
    where(lan_only: true).order(:address).map { |host| "#{prefix}.#{host.address}" }
  end

  protected

  # LAN only is kept by the router's rules, by the device's address: turning it on or off, a
  # kept-off device's address changing, or its removal, rewrites them while the NAS is the
  # router. Off the router, the flag waits for it.
  def apply_router_rules
    return unless (lan_only || saved_change_to_lan_only?) && DnsService.router?
    DnsService.apply_router!
  rescue Privileged::Error => e
    Rails.logger.error("Host #{name}: router rules not rewritten: #{e.message}")
  end

  def rewrite_dnsmasq_config
    DnsmasqService.rewrite_config!
  rescue Privileged::Error => e
    Rails.logger.error("Host #{name}: dnsmasq config not rewritten: #{e.message}")
  end

  def rewrite_dns
    DnsService.rewrite!
  rescue Privileged::Error => e
    Rails.logger.error("Host #{name}: DNS names not rewritten: #{e.message}")
  end

  def convert_address
    self.address = self.address.to_i.to_s
  end
end
