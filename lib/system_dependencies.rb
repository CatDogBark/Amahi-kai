require 'open3'

# Settings → System Dependencies (admins): what this NAS runs that Amahi-kai depends on, the
# version of each, and the updates waiting for it, so updating is a choice made there. Reading
# needs no root (dpkg-query, apt list, /etc/os-release); refreshing apt's package lists
# (packages.refresh) goes through the root helper.
module SystemDependencies
  # The software Amahi-kai installs or runs. Each shows its first installed package; source is
  # where its updates come from (Ubuntu's archive, or its maker's own repository).
  CATALOG = [
    { key: 'ruby', name: 'Ruby', role: 'Runs Amahi-kai', packages: %w[ruby3.2], source: 'Ubuntu' },
    { key: 'samba', name: 'Samba', role: 'Network shares (SMB)', packages: %w[samba], source: 'Ubuntu' },
    { key: 'greyhole', name: 'Greyhole', role: 'Storage pool', packages: %w[greyhole], source: 'Greyhole' },
    { key: 'php', name: 'PHP', role: 'Runs Greyhole', packages: %w[php8.3-cli php8.3-mysql php8.3-mbstring], source: 'Ubuntu' },
    { key: 'zfs', name: 'ZFS', role: 'ZFS pools', packages: %w[zfsutils-linux zfs-zed], source: 'Ubuntu' },
    { key: 'smartmontools', name: 'smartmontools', role: 'Drive health', packages: %w[smartmontools], source: 'Ubuntu' },
    { key: 'mariadb', name: 'MariaDB', role: "Amahi-kai's database", packages: %w[mariadb-server mariadb-client], source: 'Ubuntu' },
    { key: 'docker', name: 'Docker', role: 'Apps', packages: %w[docker-ce docker-ce-cli containerd.io], source: 'Docker' },
    { key: 'tailscale', name: 'Tailscale', role: 'Remote access (VPN)', packages: %w[tailscale], source: 'Tailscale' },
    { key: 'cloudflared', name: 'cloudflared', role: 'Remote access (Cloudflare Tunnel)', packages: %w[cloudflared], source: 'Cloudflare' },
    { key: 'avahi', name: 'Avahi', role: 'Names on the LAN (mDNS)', packages: %w[avahi-daemon], source: 'Ubuntu' },
    { key: 'dnsmasq', name: 'dnsmasq', role: 'DHCP and DNS', packages: %w[dnsmasq], source: 'Ubuntu' },
    { key: 'fail2ban', name: 'fail2ban', role: 'Blocks repeated failed logins', packages: %w[fail2ban], source: 'Ubuntu' },
    { key: 'openssh', name: 'OpenSSH server', role: 'SSH', packages: %w[openssh-server], source: 'Ubuntu' }
  ].freeze

  APT_LISTS = '/var/lib/apt/lists'.freeze
  REBOOT_REQUIRED = '/var/run/reboot-required'.freeze
  OS_RELEASE = '/etc/os-release'.freeze

  # An update apt has for an installed package.
  Update = Struct.new(:package, :installed, :available, :security, keyword_init: true)

  # One row of the page: a piece of software, its packages' versions and their updates.
  Dependency = Struct.new(:key, :name, :role, :source, :version, :updates, keyword_init: true) do
    def installed?
      !version.nil?
    end

    def security?
      updates.any?(&:security)
    end
  end

  class << self
    # Everything the page shows: { dependencies:, other: [Update], os:, kernel:, restart:,
    # runtime:, checked_at: }.
    def status
      updates = upgradable
      by_package = updates.to_h { |u| [u.package, u] }
      versions = installed_versions(CATALOG.flat_map { |e| e[:packages] })
      dependencies = CATALOG.map do |entry|
        package = entry[:packages].find { |p| versions[p] }
        Dependency.new(**entry.slice(:key, :name, :role, :source), version: package && versions[package],
                       updates: entry[:packages].filter_map { |p| by_package[p] })
      end
      tracked = CATALOG.flat_map { |e| e[:packages] }
      { dependencies: dependencies, other: updates.reject { |u| tracked.include?(u.package) }, os: os_name,
        kernel: kernel, restart: restart_needed, runtime: runtime, checked_at: lists_checked_at }
    end

    # apt's updates for installed packages, from its package lists (as fresh as the last
    # refresh). An update from a -security pocket is a security fix.
    def upgradable
      out, _err, status = Open3.capture3({ 'LANG' => 'C' }, 'apt', 'list', '--upgradable')
      return [] unless status.success?
      parse_upgradable(out)
    rescue SystemCallError
      []
    end

    # "name/noble-updates,noble-security 1.2-3 amd64 [upgradable from: 1.2-1]"
    def parse_upgradable(text)
      text.lines.filter_map do |line|
        match = line.match(%r{\A([^/\s]+)/(\S+)\s+(\S+)\s+\S+\s+\[upgradable from: ([^\]]+)\]})
        next unless match
        Update.new(package: match[1], available: match[3], installed: match[4],
                   security: match[2].split(',').any? { |pocket| pocket.end_with?('-security') })
      end
    end

    def installed_versions(packages)
      out, _err, _status = Open3.capture3('dpkg-query', '-W', '-f=${Package}\t${Version}\t${db:Status-Abbrev}\n', *packages)
      out.lines.each_with_object({}) do |line, found|
        name, version, state = line.chomp.split("\t")
        found[name] = version if state.to_s.start_with?('ii')
      end
    rescue SystemCallError
      {}
    end

    def os_name
      File.read(OS_RELEASE)[/^PRETTY_NAME="?([^"\n]+)"?/, 1]
    rescue SystemCallError
      nil
    end

    def kernel
      out, _err, status = Open3.capture3('uname', '-r')
      status.success? ? out.strip : nil
    rescue SystemCallError
      nil
    end

    # The packages whose update needs a restart to take effect ([] if none was named), or nil
    # when no restart is waiting.
    def restart_needed
      return nil unless File.exist?(REBOOT_REQUIRED)
      File.exist?("#{REBOOT_REQUIRED}.pkgs") ? File.readlines("#{REBOOT_REQUIRED}.pkgs", chomp: true).reject(&:empty?).uniq : []
    rescue SystemCallError
      []
    end

    # What Amahi-kai runs on, which updates with Amahi-kai itself (System Update).
    def runtime
      { amahi_kai: SystemServices.app_commit, ruby: RUBY_VERSION, rails: Rails.version, gems: Gem.loaded_specs.size }
    end

    # When apt's package lists were last refreshed: its newest Release file.
    def lists_checked_at
      Dir.glob(File.join(APT_LISTS, '*Release')).map { |file| File.mtime(file) }.max
    rescue SystemCallError
      nil
    end

    # Refreshes apt's package lists (apt-get update) through the root helper, passing its
    # output on line by line. Raises Privileged::Error.
    def refresh!(&progress)
      Privileged.call('packages.refresh') { |line| progress&.call(line) }
    end
  end
end
