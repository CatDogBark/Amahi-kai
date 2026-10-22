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

class DnsAlias < ApplicationRecord

  # Unbound answers for the aliases (Network → DNS), so a change rewrites its local names.
  after_commit :rewrite_dns

  scope :user_visible,->{where(["address != ?", ''])}

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9-]*\z/i }
  # Blank points the name at the NAS itself.
  validate :address_is_an_ip

  private

  def address_is_an_ip
    return if address.blank?
    IPAddr.new(address.strip)
    errors.add(:address, 'must be an IP address') if address.include?('/')
  rescue IPAddr::Error
    errors.add(:address, 'must be an IP address')
  end

  def rewrite_dns
    DnsService.rewrite!
  rescue Privileged::Error => e
    # The alias is saved; Unbound catches up the next time its config is written.
    Rails.logger.error("DnsAlias: DNS names not rewritten: #{e.message}")
  end

end
