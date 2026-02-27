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

  DEFAULT_GROUP = "users"

  DNSMASQ = true

  def self.dnsmasq?
    DNSMASQ ? true : false
  end

  PLATFORMS = ['ubuntu', 'debian']

  SERVICES = {
    'ubuntu' => {
      :apache => 'apache2',
      :dhcp => 'isc-dhcp-server',
      :named => 'bind9',
      :smb => 'smbd',
      :nmb => 'nmbd',
      :mysql => 'mariadb',
    },
    'debian' => {
      :apache => 'apache2',
      :dhcp => 'isc-dhcp-server',
      :named => 'bind9',
      :smb => 'smbd',
      :nmb => 'nmbd',
      :mysql => 'mariadb',
    },
  }

  FILENAMES = {
    'ubuntu' => {
      :apache_pid => 'apache2.pid',
      :dhcpleasefile => dnsmasq? ? '/var/lib/dnsmasq/dnsmasq.leases' : '/var/lib/dhcp3/dhcpd.leases',
      :samba_pid => 'samba/smbd.pid',
      :dhcpd_pid => 'dhcp-server/dhcpd.pid',
      :monit_dir => '/etc/monit/conf.d',
      :monit_conf => '/etc/monit/monitrc',
      :monit_log => '/var/log/monit.log',
      :syslog => '/var/log/syslog',
    },
    'debian' => {
      :apache_pid => 'apache2.pid',
      :dhcpleasefile => dnsmasq? ? '/var/lib/misc/dnsmasq.leases' : '/var/lib/dhcp/dhcpd.leases',
      :samba_pid => 'samba/smbd.pid',
      :dhcpd_pid => 'dhcp-server/dhcpd.pid',
      :monit_dir => '/etc/monit/conf.d',
      :monit_conf => '/etc/monit/monitrc',
      :monit_log => '/var/log/monit.log',
      :syslog => '/var/log/syslog',
    },
  }

  class << self
    def reload(service)
      Shell.run("systemctl reload #{service2name service}.service")
    end

    def file_name(service)
      file2name(service)
    end

    def service_name(service)
      service2name(service)
    end

    def platform
      @@platform
    end

    def ubuntu?
      @@platform == 'ubuntu'
    end

    def debian?
      @@platform == 'debian'
    end

    def install(pkgs, sha1 = nil)
      pkginstall(pkgs, sha1)
    end

    def uninstall(pkgs)
      pkguninstall(pkgs)
    end

    def service_start_command(name)
      "/usr/bin/systemctl start #{service_name(name)}.service"
    end

    def service_stop_command(name)
      "/usr/bin/systemctl stop #{service_name(name)}.service"
    end

    def service_enable_command(name)
      "/usr/bin/systemctl enable #{service_name(name)}.service"
    end

    def service_disable_command(name)
      "/usr/bin/systemctl disable #{service_name(name)}.service"
    end

    # Monit removed — method kept as no-op for any remaining callers
    def watchdog_restart_command
      "true"  # no-op
    end

    def make_admin(username, is_admin)
      admin_groups = is_admin ? ",sudo" : ''
      esc_user = Shellwords.escape(username)
      Shell.run("usermod -G #{DEFAULT_GROUP}#{admin_groups} #{esc_user}")
    end

    def update_user_pubkey(username, key)
      fname = TempCache.unique_filename "key"
      File.open(fname, "w") { |f| f.write(key) }
      esc_user = Shellwords.escape(username)
      home = "/home/#{esc_user}"
      Shell.run(
        "mkdir -p #{home}/.ssh/",
        "mv #{fname} #{home}/.ssh/authorized_keys",
        "chown -R #{esc_user}:#{DEFAULT_GROUP} #{home}/.ssh",
        "chmod u+rwx,go-rwx #{home}/.ssh",
        "chmod u+rw,go-rwx #{home}/.ssh/authorized_keys"
      )
    end

    def platform_versions
      { platform: 'amahi-kai', core: 'shell' }
    end
  end

  private

  class << self
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

    def service2name(service)
      name = SERVICES[@@platform][service.to_sym]
      name || service
    end

    def file2name(fname)
      name = FILENAMES[@@platform][fname]
      raise "unknown filename '#{fname}' for '#{@@platform}'" unless name
      name
    end

    def pkginstall(pkgs, sha1 = nil)
      esc_pkgs = Shellwords.escape(pkgs)
      Shell.run!("DEBIAN_FRONTEND=noninteractive apt-get -y install #{esc_pkgs}")
    end

    def pkguninstall(pkgs)
      esc_pkgs = Shellwords.escape(pkgs)
      Shell.run!("DEBIAN_FRONTEND=noninteractive apt-get -y remove #{esc_pkgs}")
    end
  end

  set_platform

end
