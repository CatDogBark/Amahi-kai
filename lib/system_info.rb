require 'etc'
require 'socket'
require 'shell'

# What the dashboard, System Status, Settings → Details and the setup wizard show about the
# server itself. Read in Ruby and from /proc where that's enough, and otherwise from commands
# run as argument lists (Shell.output), never through a shell.
module SystemInfo
  module_function

  # Whether Ubuntu's package +name+ is installed, as dpkg's status says.
  def package_installed?(name)
    Shell.output('dpkg-query', '-W', '-f=${Status}', name).strip == 'install ok installed'
  end

  def hostname
    Socket.gethostname
  rescue SystemCallError
    'unknown'
  end

  # The first address `hostname -I` lists: on the NAS, its LAN address.
  def ip_address
    Shell.output('hostname', '-I').split.first || 'unknown'
  end

  def kernel
    Etc.uname[:release]
  end

  # The distribution's name from os-release ("Ubuntu 24.04.3 LTS"), or Linux.
  def os_name(file = '/etc/os-release')
    line = File.readlines(file).find { |l| l.start_with?('PRETTY_NAME=') }
    line&.split('=', 2)&.last&.tr('"', '')&.strip.presence || 'Linux'
  rescue SystemCallError
    'Linux'
  end

  # The load averages with the CPU count, and the 1-minute load as a percentage of the cores
  # (capped at 100): { one:, five:, fifteen:, cores:, percent: }, or nil without /proc.
  def load(file = '/proc/loadavg')
    one, five, fifteen = File.read(file).split[0..2].map(&:to_f)
    cores = self.cores
    { one: one, five: five, fifteen: fifteen, cores: cores, percent: [((one / cores) * 100).round, 100].min }
  rescue SystemCallError
    nil
  end

  # Memory in kB, as /proc/meminfo counts it, with the share in use (what isn't available):
  # { total:, available:, used:, percent: }, or nil without /proc or with no total.
  def memory(file = '/proc/meminfo')
    text = File.read(file)
    total = text[/MemTotal:\s+(\d+)/, 1].to_i
    available = text[/MemAvailable:\s+(\d+)/, 1].to_i
    return nil unless total.positive?
    used = total - available
    { total: total, available: available, used: used, percent: ((used.to_f / total) * 100).round }
  rescue SystemCallError
    nil
  end

  def machine
    Etc.uname[:machine]
  end

  def cores
    [Etc.nprocessors.to_i, 1].max
  end

  # How long the server has been up, as `uptime -p` says it, without its "up":
  # "3 days, 2 hours, 5 minutes".
  def uptime(file = '/proc/uptime')
    seconds = File.read(file).split.first.to_f.to_i
    days, rest = seconds.divmod(86_400)
    hours, rest = rest.divmod(3600)
    parts = { 'day' => days, 'hour' => hours, 'minute' => rest / 60 }.filter_map do |unit, n|
      "#{n} #{unit}#{'s' unless n == 1}" if n.positive?
    end
    parts.empty? ? '0 minutes' : parts.join(', ')
  rescue SystemCallError
    'unknown'
  end

  # The swap files and partitions in use, from /proc/swaps: [{ name: '/swap.img', bytes: 2147483648 }].
  def swaps(file = '/proc/swaps')
    File.readlines(file).drop(1).filter_map do |line|
      name, _type, kib = line.split
      { name: name, bytes: kib.to_i * 1024 } if name
    end
  rescue SystemCallError
    []
  end

  # The system disk as `df -h /` gives it: { size: '98G', used: '24G', free: '70G', percent: 26 },
  # or nil if df can't say.
  def root_disk
    line = Shell.output('df', '-h', '/').lines.drop(1).last
    return unless line

    _filesystem, size, used, free, percent = line.split
    { size: size, used: used, free: free, percent: percent.to_i }
  end
end
