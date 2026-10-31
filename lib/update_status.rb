# UpdateStatus — what the last check for updates found.
#
# The root helper's system.check_update looks on the update channel (releases, candidates or
# development; AMAHI_UPDATE_CHANNEL in amahi.env) for the version System Update would install,
# and writes the result to /var/lib/amahi-kai/update-status.json: amahi-kai-update-check.timer
# runs it every 6 hours, System Update refreshes it, and System Status has "Check now".

require 'json'
require 'time'

class UpdateStatus
  PATH = '/var/lib/amahi-kai/update-status.json'

  CHANNELS = { 'releases' => 'releases', 'candidates' => 'releases and release candidates',
               'development' => 'the dev branch' }.freeze

  attr_reader :checked_at, :channel, :current, :current_version, :latest, :latest_version, :tag,
              :behind, :commits, :changelog, :error, :signer, :unsigned_why

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
    @channel = CHANNELS.key?(data['channel']) ? data['channel'] : nil
    @current = data['current'].presence
    @current_version = data['current_version'].presence
    @latest = data['latest'].presence
    @latest_version = data['latest_version'].presence
    @tag = data['tag'].presence
    @available = data['available'] == true
    @behind = data['behind'].to_i
    @commits = Array(data['commits']).select { |c| c.is_a?(Hash) && c['subject'].is_a?(String) }
    @changelog = Array(data['changelog']).grep(String)
    @error = data['error'].presence
    signature = data['signature'].is_a?(Hash) ? data['signature'] : nil
    @signature_checked = !signature.nil?
    @signed = signature&.dig('trusted') == true
    @signer = @signed ? signature['signer'].presence : nil
    @unsigned_why = signature && !@signed ? signature['why'].presence : nil
  end

  # Whether the release on offer was checked for a release key's signature (a release or a
  # candidate: the dev branch has no tags), and whether it has one.
  def signature_checked?
    @signature_checked
  end

  def signed?
    @signed
  end

  # The key that signed it, the way a person says it: "release key A" for release-key-a.
  def signer_label
    letter = signer.to_s[/\Arelease-key-([a-z])\z/, 1]
    letter ? "release key #{letter.upcase}" : signer
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

  # What the update brings, in a line: "Amahi-kai 0.9.2 (you have 0.9.1)" for a release,
  # "3 changes on the dev branch (abc1234 → def5678)" for development.
  def summary
    if tag
      "Amahi-kai #{latest_version || tag.delete_prefix('v')} (you have #{current_version || short(current)})"
    else
      "#{behind} #{behind == 1 ? 'change' : 'changes'}#{' on the dev branch' if channel == 'development'} (#{short(current)} → #{short(latest)})"
    end
  end

  # The running version: "0.9.1, abc1234", or the commit alone.
  def running
    [current_version, short(current)].compact.join(', ')
  end

  # "releases", "releases and release candidates" or "the dev branch".
  def channel_label
    CHANNELS[channel]
  end

  private

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
