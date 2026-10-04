# UpdateStatus — what the last check for updates found.
#
# The root helper's system.check_update fetches main (as System Update pulls it) and writes
# the result to /var/lib/amahi-kai/update-status.json: amahi-kai-update-check.timer runs it
# every 6 hours, System Update refreshes it, and System Status has "Check now".

require 'json'
require 'time'

class UpdateStatus
  PATH = '/var/lib/amahi-kai/update-status.json'

  attr_reader :checked_at, :current, :latest, :behind, :commits, :changelog, :error

  # The status on this machine; an empty one if nothing has been checked yet.
  def self.load(path = default_path)
    new(JSON.parse(File.read(path)))
  rescue SystemCallError, JSON::ParserError, TypeError
    new({})
  end

  # Outside production (development and specs) the file lives in tmp/.
  def self.default_path
    defined?(Rails) && !Rails.env.production? ? Rails.root.join('tmp', 'update-status.json').to_s : PATH
  end

  def initialize(data)
    data = {} unless data.is_a?(Hash)
    @checked_at = parse_time(data['checked_at'])
    @current = data['current'].presence
    @latest = data['latest'].presence
    @available = data['available'] == true
    @behind = data['behind'].to_i
    @commits = Array(data['commits']).select { |c| c.is_a?(Hash) && c['subject'].is_a?(String) }
    @changelog = Array(data['changelog']).grep(String)
    @error = data['error'].presence
  end

  def checked?
    !checked_at.nil?
  end

  def available?
    @available && behind.positive?
  end

  def short(sha)
    sha.to_s[0, 7].presence
  end

  private

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
