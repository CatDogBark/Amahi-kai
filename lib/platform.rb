# Amahi Home Server
# Copyright (C) 2007-2011 Amahi
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

require 'shellwords'
require 'shell'

class Platform

  PLATFORMS = ['ubuntu', 'debian']

  # Where this platform keeps the files Amahi-kai reads: the DHCP leases (dnsmasq's, for
  # Network → Leases) and the system log (the debug tab).
  FILENAMES = {
    'ubuntu' => { dhcpleasefile: '/var/lib/dnsmasq/dnsmasq.leases', syslog: '/var/log/syslog' },
    'debian' => { dhcpleasefile: '/var/lib/misc/dnsmasq.leases', syslog: '/var/log/syslog' }
  }.freeze

  class << self
    def file_name(name)
      file2name(name)
    end

    def platform
      @@platform
    end

    # Sets the system hostname from a server name: lowercase, spaces and other
    # characters a hostname can't hold become hyphens ("My NAS" -> "my-nas").
    # Returns true, or false with the reason logged.
    def set_hostname!(name)
      hostname = name.to_s.downcase.gsub(/[^a-z0-9-]+/, '-').gsub(/\A-+|-+\z/, '')[0, 63].to_s.chomp('-')
      privileged('network.set_hostname', hostname: hostname)
    end

    # Reboot and power off go through the root helper (sudo had no rule for them, so
    # the buttons used to do nothing). Return true, or false with the reason logged.
    def reboot!
      privileged('system.reboot')
    end

    def poweroff!
      privileged('system.poweroff')
    end

    def platform_versions
      { platform: 'amahi-kai', core: 'shell' }
    end
  end

  private

  class << self
    def privileged(operation, **args)
      Privileged.call(operation, **args)
      true
    rescue Privileged::Error => e
      Rails.logger.error("Platform: #{operation} failed: #{e.message}")
      false
    end

    def set_platform
      if File.exist?('/etc/issue')
        line = File.read('/etc/issue').to_s
        @@platform = "debian" if line.include?("Debian")
        @@platform = "ubuntu" if line.include?("Ubuntu")
      end
      @@platform ||= nil
      @@platform ||= "debian" if File.exist?('/usr/bin/apt-get')
      raise "unsupported platform: only Ubuntu and Debian are supported" unless PLATFORMS.include?(@@platform)
    end

    def file2name(fname)
      name = FILENAMES[@@platform][fname]
      raise "unknown filename '#{fname}' for '#{@@platform}'" unless name
      name
    end
  end

  set_platform

end
