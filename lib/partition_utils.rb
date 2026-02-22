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


class PartitionUtils
	attr :file
	attr :info

	def initialize
		@file = '/etc/mtab'
		@info = []
		begin
			f = File.open('/etc/mtab')
		rescue => e
			return @info
		end
		while f.gets
			if ($_.match(/^\/dev/))
				# data = ($_.split)[0..3]
				p = ($_.split)[0..3]
				data = Hash.new
				device = part2device(p[0])
				path = cleanup_path(p[1])
				next if ['/', '/boot', '/boot/efi'].include?(path)
				data[:device] = device
				(total, free) = disk_stats(path)
				data[:bytes_total] = total
				data[:bytes_free] = free
				data[:path] = path
				@info.push(data)
			end
		end
		f.close
	end

	private

	# return device
	def part2device(part)
		part[/.?[^0-9]*/]
	end

	def cleanup_path(path)
		path.gsub(/\\040/, ' ')
	end

	def disk_stats(path)
		require 'sys/filesystem'
		stat = Sys::Filesystem.stat(path)
		total = stat.block_size * stat.blocks
		free  = stat.block_size * stat.blocks_available
		[total, free]
	rescue => e
		Rails.logger.error("disk stats error for #{path}: #{e.inspect}")
		[0, 0]
	end

end
