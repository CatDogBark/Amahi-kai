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


require 'date'
require 'platform'

class Leases

  # We use dnsmasq by default as of 2013

  LEASEFILE = Platform.file_name(:dhcpleasefile)

  def self.all
    read_lease(LEASEFILE)
  end

  def self.read_lease(file)
    res = []
    return res unless File.exist?(file)
    current = {}
    File.foreach(file) do |line|
      next if line =~ /^\s*\#/
      if line =~ /^(\d+)\s+(([0-9a-f]{2}:){5}[0-9a-f]{2})\s+(\d+\.\d+\.\d+\.\d+)\s+([^\s]+)\s+/i
        res << { :expiration => $1.to_i, :mac => $2, :ip => $4, :name => $5 }
      else
        Rails.logger.error("DNMASQ lease parser failed for line: '#{line}'")
      end
    end
    res.sort { |x, y| x[:expiration] <=> y[:expiration] }
  end

  private_class_method :read_lease
end
