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

# A device known by its hardware address (Network → Devices): by its name in DNS (name.<domain>
# and name) wherever it is, and at a fixed address (+address+, the last part on the LAN's /24) if
# it has one. Without one it keeps the address DHCP gives it, and its name follows it there (the
# helper's dns.sync_leases).
class Host < ApplicationRecord

  before_save :convert_address
  # dnsmasq hands out fixed addresses and names from its config, and Unbound answers for the fixed
  # ones' names (Network → DNS & DHCP), so a change rewrites both. LAN only is a rule of the
  # router's, by the device's address: NetworkController rewrites the router's rules after a change
  # to it, and says when it can't.
  after_commit :rewrite_dnsmasq_config, :rewrite_dns

  # A hostname label: at most 63 characters.
  validates :name, presence: true, format: { with: /\A[a-z][a-z0-9-]{0,62}\z/i }, uniqueness: true
  validate :name_not_dnsmasq_word
  validates :mac, presence: true, uniqueness: true, format: { with: /\A([0-9a-f]{2}:){5}([0-9a-f]{2})\z/i }
  validates :address, uniqueness: true, numericality: { greater_than: 0, less_than: 255, only_integer: true }, allow_blank: true
  validate :lan_only_needs_address

  scope :fixed, -> { where.not(address: [nil, '']) }

  # The devices kept off the internet (Network → Devices, LAN only), as their addresses on
  # +prefix+'s network, for the router's rules.
  def self.lan_only_addresses(prefix)
    fixed.where(lan_only: true).order(:address).map { |host| "#{prefix}.#{host.address}" }
  end

  def fixed?
    address.present?
  end

  protected

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
    self.address = address.present? ? address.to_i.to_s : nil
  end

  # Words dnsmasq reads as orders where a name goes (ignore: no address for the device;
  # infinite: a lease that never ends), in any case, since it's written in lowercase.
  def name_not_dnsmasq_word
    errors.add(:name, 'is a word dnsmasq reads as an order: choose another') if %w[ignore infinite].include?(name.to_s.downcase)
  end

  # LAN only is a router rule on the device's address, so it needs one that stays.
  def lan_only_needs_address
    errors.add(:base, "LAN only needs a fixed address: #{name} has none") if lan_only && !fixed?
  end
end
