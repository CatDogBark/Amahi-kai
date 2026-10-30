# What Settings → Help says about this server, and a problem's report quotes: Amahi-kai's
# version, the system, its hardware, the system disk, its storage, the apps and the services.
# Each part says "unknown" rather than stopping the page when its source can't be read.
module ServerSummary
  CPUINFO = '/proc/cpuinfo'.freeze

  module_function

  # [[label, value], ...] in the order the pages show them.
  def rows
    [['Amahi-kai', amahi], ['System', system], ['Hardware', hardware], ['System disk', system_disk],
     ['Storage', storage], ['Apps', apps_summary], ['Services', services_summary]]
  end

  # The rows as text, then each app on a line of its own, for a problem's report.
  def text
    lines = rows.map { |label, value| "#{label}: #{value}" }
    apps.each { |app| lines << "  #{app[:name]}: #{app[:state]}#{" (#{app[:detail]})" if app[:detail].present?}" }
    lines.join("\n")
  end

  def amahi
    version = Rails.root.join('VERSION').read.strip.presence || 'unknown'
    commit = SystemServices.app_commit
    channel = UpdateStatus.load.channel.presence || 'releases'
    "#{version}#{" (#{commit})" if commit} · #{channel}"
  rescue SystemCallError
    'unknown'
  end

  def system
    "#{SystemInfo.os_name} · kernel #{SystemInfo.kernel}"
  end

  def hardware
    cpu = cpu_model
    threads = cpu_threads
    memory = SystemInfo.memory
    ram = memory ? "#{gigabytes(memory[:total])} RAM, #{gigabytes(memory[:total] - memory[:used])} free" : 'RAM unknown'
    [cpu ? "#{cpu}#{" (#{threads} threads)" if threads}" : nil, ram].compact.join(' · ')
  end

  def system_disk
    disk = SystemInfo.root_disk
    disk ? "#{size(disk[:free])} free of #{size(disk[:size])}" : 'unknown'
  end

  # df -h's "58G" as "58 GB".
  def size(value)
    value.to_s.sub(/\A([\d.]+)([KMGTP])\z/) { "#{Regexp.last_match(1)} #{Regexp.last_match(2)}B" }
  end

  def storage
    parts = []
    status = StoragePools.status
    status[:pools].select(&:managed?).each do |pool|
      parts << "ZFS pool #{pool.name}: #{pool.health}#{", #{pool.used} used, #{pool.available} free" if pool.used.present?}"
    end
    status[:offline].each { |pool| parts << "ZFS pool #{pool.name}: #{pool.state}" }
    if Greyhole.installed?
      drives = DiskPoolPartition.count
      parts << "Greyhole #{Greyhole.running? ? 'running' : 'stopped'}, #{drives} #{drives == 1 ? 'drive' : 'drives'}"
    end
    parts.presence&.join(' · ') || 'shares on the system disk'
  rescue StandardError => e
    "unknown (#{e.message})"
  end

  # [{ name:, state:, detail: }]: each app as its page names its state.
  def apps
    DockerApp.order(:name).map do |app|
      state = { 'running' => 'running', 'stopped' => 'stopped', 'error' => 'needs attention',
                'installing' => 'installing', 'pulling' => 'installing' }.fetch(app.status, app.status)
      { name: app.name, state: state, detail: (app.error_message if app.status == 'error') }
    end
  end

  def apps_summary
    list = apps
    return 'none installed' if list.empty?

    list.group_by { |app| app[:state] }.map { |state, group| "#{group.size} #{state}" }.join(' · ')
  end

  # The system services Amahi-kai depends on that should run and don't.
  def services_summary
    down = SystemServices.all.reject { |service| service.running? || service.idle? }.map(&:name)
    down.empty? ? 'all running' : "not running: #{down.join(', ')}"
  rescue StandardError => e
    "unknown (#{e.message})"
  end

  def cpu_model
    File.foreach(CPUINFO) { |line| return line.split(':', 2).last.strip.squeeze(' ') if line.start_with?('model name') }
    nil
  rescue SystemCallError
    nil
  end

  def cpu_threads
    count = File.foreach(CPUINFO).count { |line| line.start_with?('processor') }
    count.positive? ? count : nil
  rescue SystemCallError
    nil
  end

  # +kilobytes+ (as /proc/meminfo counts) as "15.5 GB".
  def gigabytes(kilobytes)
    "#{(kilobytes / 1024.0 / 1024.0).round(1)} GB"
  end
end
