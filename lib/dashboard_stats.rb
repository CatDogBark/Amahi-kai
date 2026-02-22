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
        counts: entity_counts
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
        status = begin
          `systemctl is-active #{svc[:unit]} 2>/dev/null`.strip
        rescue
          'unknown'
        end
        since = if status == 'active'
          begin
            `systemctl show #{svc[:unit]} --property=ActiveEnterTimestamp 2>/dev/null`
              .strip.sub('ActiveEnterTimestamp=', '')
          rescue
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
    rescue
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
    rescue
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
    rescue
      { percent: 0, detail: 'unavailable' }
    end

    def disk_usage
      df = `df -h / 2>/dev/null`.lines.last
      if df
        parts = df.split
        { percent: parts[4].to_i, detail: "#{parts[2]} / #{parts[1]}" }
      else
        { percent: 0, detail: 'unavailable' }
      end
    rescue
      { percent: 0, detail: 'unavailable' }
    end
  end
end
