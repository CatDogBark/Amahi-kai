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

class DiskUtils
  class << self
    def stats
      disks = lsblk_disks
      disks.each do |disk|
        temp = smartctl_temp(disk[:device])
        disk[:temp_c] = temp > 0 ? temp.to_s : '-'
        disk[:temp_f] = temp > 0 ? (temp * 1.8 + 32).to_i.to_s : '-'
        disk[:tempcolor] = temp_color(temp)
      end
      disks
    rescue => e
      Rails.logger.error("DiskUtils.stats error: #{e.message}") if defined?(Rails)
      []
    end

    def mounts
      output = `df -BK 2>/dev/null`.split(/\r?\n/)[1..-1] || []
      result = []
      output.each do |line|
        fields = line.split(/\s+/)
        next if ['tmpfs', 'devtmpfs', 'none', 'overlay'].include?(fields[0])
        result << {
          filesystem: fields[0],
          bytes: fields[1].to_i * 1024,
          used: fields[2].to_i * 1024,
          available: fields[3].to_i * 1024,
          use_percent: fields[4],
          mount: fields[5]
        }
      end
      result.sort_by { |d| d[:filesystem] }
    end

    private

    def lsblk_disks
      output = `lsblk -dno NAME,MODEL,TYPE 2>/dev/null`.strip
      return [] if output.empty?
      output.split("\n").filter_map do |line|
        fields = line.split(/\s+/, 3)
        next unless fields[2]&.strip == 'disk'
        {
          device: "/dev/#{fields[0]}",
          model: fields[1]&.gsub(/[^A-Za-z0-9\-_\s\.]/, '') || 'Unknown'
        }
      end
    end

    def smartctl_temp(device)
      output = `smartctl -A #{Shellwords.escape(device)} 2>/dev/null`
      # Look for temperature in smartctl output
      match = output.match(/Temperature_Celsius.*?(\d+)\s*$/) ||
              output.match(/Current Drive Temperature:\s*(\d+)/) ||
              output.match(/Temperature:\s*(\d+)/)
      match ? match[1].to_i : 0
    rescue StandardError
      0
    end

    def temp_color(temp)
      return 'cool' if temp <= 0
      return 'hot' if temp > 49
      return 'warm' if temp > 39
      'cool'
    end
  end
end
