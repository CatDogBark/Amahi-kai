# StorageHealth — what the last storage health check found, and the alerts it calls for.
#
# The root helper's storage.check_health reads the pools and every drive's SMART data and
# writes them to /var/lib/amahi-kai/storage-health.json: amahi-kai-storage-check.timer runs
# it every 15 minutes, and Disks → ZFS Pools has Check now. The dashboard and the Disks
# pages show the alerts (admins only).

require 'json'
require 'time'
require 'storage_pools'
require 'disk_manager'

class StorageHealth
  PATH = '/var/lib/amahi-kai/storage-health.json'
  # SSD wear, from the first of these ATA attributes a drive has: each counts down from 100
  # as the drive wears (Samsung, Micron and Crucial, others).
  WEAR_ATTRIBUTES = %w[177 202 231 233].freeze
  WORN = 90 # % of an SSD's rated wear that calls for a warning

  Alert = Struct.new(:level, :message, :path, keyword_init: true) # level: :danger or :warning

  # Virtual disks (QEMU, VirtualBox, VMware, Hyper-V, virtio) have no SMART data. Drives
  # passed through to a VM are the real drives, with their own model names.
  VIRTUAL_MODEL = /\A(?:QEMU|VBOX|VMware|Virtual)|\bVirtual Disk\b|\bvirtio\b/i

  attr_reader :checked_at, :pools, :drives, :checked_drives

  def self.virtual_disk?(path, model)
    path.to_s.match?(%r{\A/dev/x?vd[a-z]+\z}) || model.to_s.match?(VIRTUAL_MODEL)
  end

  def self.load(path = default_path)
    new(JSON.parse(File.read(path)))
  rescue SystemCallError, JSON::ParserError, TypeError
    new({})
  end

  # Outside production (development and specs) the file lives in tmp/.
  def self.default_path
    defined?(Rails) && !Rails.env.production? ? Rails.root.join('tmp', 'storage-health.json').to_s : PATH
  end

  def initialize(data)
    data = {} unless data.is_a?(Hash)
    @checked_at = parse_time(data['checked_at'])
    @smartctl = data['smartctl'] == true
    @pools = Array(data['pools']).grep(Hash).map { |pool| StoragePools.pool(pool) }
    @checked_drives = data['drives'].is_a?(Hash) ? data['drives'].keys : []
    @drives = data['drives'].is_a?(Hash) ? data['drives'].select { |_path, smart| smart.is_a?(Hash) } : {}
  end

  def checked?
    !checked_at.nil?
  end

  # Whether smartctl was there to read the drives' health.
  def smartctl?
    @smartctl
  end

  # The SMART data for a whole disk (/dev/sda), or nil.
  def drive(path)
    drives[path]
  end

  # Why a drive has no SMART data to show: :not_checked (it wasn't there at the last check),
  # :no_smartctl, :virtual (a virtual disk) or :no_smart (the drive gave none).
  def missing_reason(path, model)
    return :not_checked unless checked_drives.include?(path)
    return :no_smartctl unless smartctl?
    self.class.virtual_disk?(path, model) ? :virtual : :no_smart
  end

  # Everything that needs looking at, worst first.
  def alerts
    list = pools.flat_map { |pool| pool_alerts(pool) }
    drives.each do |path, smart|
      drive_problems(smart).each do |level, text|
        list << Alert.new(level: level, message: "#{drive_name(path, smart)} #{text}", path: drive_page(path))
      end
    end
    list.sort_by { |alert| alert.level == :danger ? 0 : 1 }
  end

  # [[level, text], ...] for one drive's SMART data.
  def drive_problems(smart)
    return [] if smart.nil?
    problems = []
    problems << [:danger, "says it's failing (its own SMART health check)"] if smart['passed'] == false
    { '5' => 'reallocated sectors', '197' => 'sectors waiting to be reallocated', '198' => 'uncorrectable sectors',
      '187' => 'uncorrectable errors reported' }.each do |id, what|
      count = attribute(smart, id, 'raw').to_i
      problems << [:warning, "has #{count} #{what}"] if count.positive?
    end
    nvme = smart['nvme'] || {}
    problems << [:danger, 'reports a critical warning (NVMe)'] if nvme['critical_warning'].to_i.positive?
    problems << [:warning, "has #{nvme['media_errors']} media errors"] if nvme['media_errors'].to_i.positive?
    worn = wear(smart)
    problems << [:warning, "is #{worn}% worn out"] if worn && worn >= WORN
    problems
  end

  # "2% worn · 4,210 hours · firmware SVT02B6Q" for the drive tables, or nil without SMART data.
  def drive_details(path)
    smart = drive(path) or return nil
    worn = wear(smart)
    [("#{worn}% worn" if worn), ("#{smart['power_on_hours'].to_i.to_fs(:delimited)} hours" if smart['power_on_hours']),
     ("firmware #{smart['firmware']}" if smart['firmware'].present?), ('asleep' if smart['asleep'])].compact.join(' · ')
  end

  # :danger, :warning or :ok for a drive's badge.
  def drive_level(path)
    levels = drive_problems(drive(path)).map(&:first)
    levels.include?(:danger) ? :danger : (levels.any? ? :warning : :ok)
  end

  # How much of an SSD's rated wear is used, in %: NVMe's own figure, or 100 minus the first
  # ATA wear attribute's normalized value. nil for drives that don't say.
  def wear(smart)
    used = smart.dig('nvme', 'percentage_used')
    return used.to_i if used
    id = WEAR_ATTRIBUTES.find { |key| attribute(smart, key, 'value') }
    id && (100 - attribute(smart, id, 'value').to_i).clamp(0, 100)
  end

  private

  def pool_alerts(pool)
    path = '/disks/pools'
    list = []
    unless pool.healthy?
      advice = pool.what_to_do
      list << Alert.new(level: :danger, message: "Pool #{pool.name} is #{pool.health}#{". #{advice}" if advice}", path: path)
    end
    list << Alert.new(level: :danger, message: "Pool #{pool.name} has data errors: #{pool.data_errors}", path: path) if pool.data_errors
    pool.drives.each do |d|
      counts = [d['read'], d['write'], d['cksum']].map(&:to_s)
      next if counts.all? { |n| n.empty? || n == '0' }
      name = d['device'] ? DiskManager.base_device(d['device']) : d['name']
      list << Alert.new(level: :warning, message: "#{name} in pool #{pool.name} has read/write/checksum errors (#{counts.join(' / ')})", path: path)
    end
    if (found = scrub_findings(pool.scan))
      list << Alert.new(level: :warning, message: "The last scrub of #{pool.name} #{found}", path: path)
    end
    list
  end

  # What a finished scrub found: "scrub repaired 12K in 00:01:02 with 3 errors on ...".
  def scrub_findings(scan)
    match = scan.to_s.match(/\Ascrub repaired (\S+) in .* with (\d+) errors/) or return nil
    return "found #{match[2]} errors it couldn't repair" if match[2].to_i.positive?
    "repaired #{match[1]} of damaged data" unless match[1] == '0B'
  end

  def attribute(smart, id, field)
    smart.dig('attributes', id, field)
  end

  def drive_name(path, smart)
    smart['model'].present? ? "#{path} (#{smart['model']})" : path
  end

  # Pool drives' alerts lead to ZFS Pools, the others to Devices.
  def drive_page(path)
    in_pool = pools.any? { |pool| pool.drives.any? { |d| d['device'] && DiskManager.base_device(d['device']) == path } }
    in_pool ? '/disks/pools' : '/disks/devices'
  end

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
