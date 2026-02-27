# DashboardStats — lightweight system info for the home dashboard
# Heavier details live in SettingsController#system_status

class DashboardStats
  class << self
    def summary
      {
        system: system_info,
        resources: resource_usage,
        services: service_status,
        storage: storage_summary,
        counts: entity_counts,
        drives: drive_usage,
        pool: pool_status
      }
    end

    def system_info
      {
        hostname: (`hostname`.strip rescue 'unknown'),
        uptime: (`uptime -p`.strip.sub(/^up\s+/, '') rescue 'unknown'),
        os: os_name
      }
    end

    def resource_usage
      cpu = cpu_load
      mem = memory_usage
      disk = disk_usage
      { cpu: cpu, memory: mem, disk: disk }
    end

    def service_status
      # Core services (always shown)
      services = [
        { name: 'Samba', unit: 'smbd' },
        { name: 'Samba (nmbd)', unit: 'nmbd' },
        { name: 'MariaDB', unit: 'mariadb' },
      ]

      # Optional services (only shown if installed)
      optional = [
        { name: 'dnsmasq', unit: 'dnsmasq', check: '/usr/sbin/dnsmasq' },
        { name: 'Greyhole', unit: 'greyhole', check: '/usr/bin/greyhole' },
        { name: 'Docker', unit: 'docker', check: '/usr/bin/docker' },
        { name: 'Cloudflare Tunnel', unit: 'cloudflared', check: '/usr/bin/cloudflared' },
      ]

      optional.each do |svc|
        services << svc if File.exist?(svc[:check])
      end

      services.map do |svc|
        # Greyhole uses an LSB init script — systemd can't track the forked daemon,
        # so systemctl is-active returns "failed" even when the daemon is running.
        # Use pgrep to check for the actual process instead.
        if svc[:unit] == 'greyhole'
          running = begin
            require 'greyhole'
            Greyhole.running?
          rescue StandardError
            false
          end
          next { name: svc[:name], unit: svc[:unit], running: running, status: running ? 'active' : 'inactive', since: nil }
        end

        status = begin
          `systemctl is-active #{svc[:unit]} 2>/dev/null`.strip
        rescue StandardError
          'unknown'
        end
        since = if status == 'active'
          begin
            `systemctl show #{svc[:unit]} --property=ActiveEnterTimestamp 2>/dev/null`
              .strip.sub('ActiveEnterTimestamp=', '')
          rescue StandardError
            nil
          end
        end
        { name: svc[:name], unit: svc[:unit], running: status == 'active', status: status, since: since }
      end
    end

    def storage_summary
      shares = Share.all rescue []
      pool_partitions = DiskPoolPartition.all rescue []
      greyhole_installed = Greyhole.installed? rescue false

      total_files = ShareFile.count rescue 0

      {
        shares_count: shares.size,
        total_files: total_files,
        pool_drives: pool_partitions.size,
        greyhole_installed: greyhole_installed
      }
    end

    def pool_status
      installed = begin; Greyhole.installed?; rescue StandardError; false; end
      running = begin; Greyhole.running?; rescue StandardError; false; end
      return { active: false } unless installed && running

      drives = begin; Greyhole.pool_drives; rescue StandardError; []; end
      return { active: false } if drives.empty?

      total = drives.sum { |d| d[:total].to_i }
      used = drives.sum { |d| d[:used].to_i }
      free = drives.sum { |d| d[:free].to_i }
      pct = total > 0 ? (used.to_f / total * 100).round(1) : 0
      copies = (Setting.get('default_pool_copies') rescue '2').to_i
      copies = 2 if copies < 1
      pending = begin
        q = Greyhole.queue_status
        q[:pending] || 0
      rescue StandardError
        0
      end

      {
        active: true,
        drives: drives.size,
        total: total,
        used: used,
        free: free,
        percent: pct,
        copies: copies,
        effective_capacity: copies > 0 ? total / copies : total,
        pending: pending
      }
    end

    def entity_counts
      {
        users: (User.all_users.count rescue 0),
        shares: (Share.count rescue 0),
        dns_aliases: (DnsAlias.count rescue 0),
        docker_apps: (DockerApp.where(status: 'running').count rescue 0)
      }
    end

    private

    def os_name
      if File.exist?('/etc/os-release')
        File.readlines('/etc/os-release')
          .find { |l| l.start_with?('PRETTY_NAME=') }
          &.split('=', 2)&.last&.tr('"', '')&.strip || 'Linux'
      else
        'Linux'
      end
    rescue StandardError
      'Linux'
    end

    def cpu_load
      if File.exist?('/proc/loadavg')
        load1, load5, load15 = File.read('/proc/loadavg').split[0..2].map(&:to_f)
        cores = `nproc`.strip.to_i rescue 1
        cores = 1 if cores < 1
        percent = ((load1 / cores) * 100).round
        { percent: [percent, 100].min, detail: "#{load1} / #{load5} / #{load15}" }
      else
        { percent: 0, detail: 'unavailable' }
      end
    rescue StandardError
      { percent: 0, detail: 'unavailable' }
    end

    def memory_usage
      if File.exist?('/proc/meminfo')
        meminfo = File.read('/proc/meminfo')
        total = meminfo[/MemTotal:\s+(\d+)/, 1].to_i
        available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_i
        if total > 0
          used = total - available
          percent = ((used.to_f / total) * 100).round
          total_gb = (total / 1048576.0).round(1)
          used_gb = (used / 1048576.0).round(1)
          { percent: percent, detail: "#{used_gb} / #{total_gb} GB" }
        else
          { percent: 0, detail: 'unavailable' }
        end
      else
        { percent: 0, detail: 'unavailable' }
      end
    rescue StandardError
      { percent: 0, detail: 'unavailable' }
    end

    def drive_usage
      # Get all mounted filesystems, excluding virtual/system ones
      lines = `df -BG 2>/dev/null`.lines.drop(1)
      drives = []
      lines.each do |line|
        parts = line.split
        next if parts.length < 6
        device, total, used, avail, percent_str, mount = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
        # Only real block devices
        next unless device.start_with?('/dev/')
        # Skip tiny partitions (boot, EFI)
        total_gb = total.to_f
        next if total_gb < 1

        drives << {
          device: device,
          mount: mount,
          total: total.sub(/G$/, '') + ' GB',
          used: used.sub(/G$/, '') + ' GB',
          available: avail.sub(/G$/, '') + ' GB',
          percent: percent_str.to_i,
          label: mount == '/' ? 'System' : File.basename(mount)
        }
      end
      drives
    rescue StandardError
      []
    end

    def disk_usage
      df = `df -h / 2>/dev/null`.lines.last
      if df
        parts = df.split
        { percent: parts[4].to_i, detail: "#{parts[2]} / #{parts[1]}" }
      else
        { percent: 0, detail: 'unavailable' }
      end
    rescue StandardError
      { percent: 0, detail: 'unavailable' }
    end
  end
end
