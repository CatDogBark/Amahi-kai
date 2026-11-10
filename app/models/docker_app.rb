# An app installed from the catalog (AppCatalog, config/apps). The root helper does the work
# (apps.* operations, docs/plans/apps.md); the record keeps what the pages show: the app's
# status, the host ports the helper gave it (host_port is its web page's; all of them, as JSON,
# in port_mappings), the shares it was given (JSON in volume_mappings, P4.4) and whether it's on
# the dashboard. (Its old environment column is no longer used.)
class DockerApp < ApplicationRecord
  # A helper operation on the app failed. AppsController reports it to the page.
  class ContainerError < StandardError; end

  validates :identifier, presence: true, uniqueness: true
  validates :name, presence: true
  validates :image, presence: true
  validates :status, inclusion: { in: %w[available pulling installing running stopped error] }

  scope :running, -> { where(status: 'running') }
  scope :dashboard, -> { where(show_in_dashboard: true) }
  scope :by_category, ->(cat) { where(category: cat) }

  # The version it runs ("1.37.3"), from the image it was installed or updated with.
  def version
    AppCatalog.tag(image)
  end

  # An update is waiting: the catalog has a newer version of it, or the update check found one.
  def update_available?
    catalog_update? || newer_found.present?
  end

  # The catalog has a newer version of it (P4.5): a newer manifest came with the catalog (for an
  # app of your own, its file names one its container doesn't run yet). One with a lower version
  # number isn't an update (the root helper refuses it too).
  def catalog_update?
    entry = AppCatalog.find(identifier)
    entry.present? && image.present? && entry[:image] != image && !AppCatalog.version_below?(AppCatalog.tag(entry[:image]), version)
  end

  def catalog_version
    AppCatalog.tag(AppCatalog.find(identifier)&.dig(:image))
  end

  # A newer version the update check found that it doesn't run yet (P4.9, AppUpdateCheck), or
  # nil: { tag:, image:, kind: 'newer' or 'rebuilt' (a newer build of the tag it runs), major: (a
  # new major version), notes: (its release notes) }. Not one it runs already, or older than one
  # an update has brought since.
  def newer_found
    return nil if newer_image.blank? || newer_tag.blank? || newer_image == image
    return nil if newer_kind == 'newer' && (newer_tag == version || AppCatalog.version_below?(newer_tag, version))
    return nil if newer_kind == 'rebuilt' && newer_tag != version

    { tag: newer_tag, image: newer_image, kind: newer_kind, major: newer_major == true, notes: newer_notes }
  end

  # What Update brings, or nil: { tag:, kind:, major:, notes:, from: :catalog or :check }, the
  # newer of the catalog's version and the one the update check found (P4.9). A catalog app's
  # update to the one found asks the helper for that tag; an app of your own's saves it in its
  # file first (CustomAppsController#version).
  def update_target
    catalog = { tag: catalog_version, kind: 'newer', major: false, notes: nil, from: :catalog } if catalog_update?
    found = newer_found&.merge(from: :check)
    return catalog || found unless catalog && found

    AppCatalog.version_below?(catalog[:tag], found[:tag]) || (catalog[:tag] == found[:tag] && found[:kind] == 'rebuilt') ? found : catalog
  end

  # The tag apps.update asks for, for a catalog app whose update is one the check found; nil for
  # the catalog's own version, and for an app of your own (its file says its version).
  def update_tag
    target = update_target
    target[:tag] if target && target[:from] == :check && !custom?
  end

  # What the update check found is spent once an update brings that version, or another.
  def forget_newer!
    update_columns(newer_tag: nil, newer_image: nil, newer_kind: nil, newer_major: false, newer_notes: nil)
  end

  # An app of the owner's own (CustomApp), not the catalog's.
  def custom?
    AppCatalog.find(identifier)&.dig(:custom) == true
  end

  # A custom app's file was saved with changes its container doesn't have yet, on the version it
  # runs (a new version is update_available?): the update that applies them didn't run, or
  # didn't come up healthy and went back.
  def changes_waiting?
    return false unless custom?

    made = AppCatalog.definition(identifier) or return false
    saved = YAML.safe_load(AppCatalog.custom_file(identifier).to_s)
    saved.is_a?(Hash) && made.except('image') != saved.except('image')
  rescue Psych::Exception
    false
  end

  # Its logo's address on the NAS (AppCatalog.logo_url): the catalog's, which comes with its
  # signed versions, or an app of the owner's own; never a link to elsewhere (the one saved at
  # install isn't used), so a page loads no picture from another site.
  def logo_url
    AppCatalog.logo_url(identifier)
  end

  # The app's page, on its own port of the NAS (docs/plans/apps.md, O3): HTTPS when its manifest
  # says its page is (`web_tls`, with its own certificate). An app reached only through Tailscale
  # (`access: tailscale`, P4.7) is at the NAS's name on the tailnet over HTTPS, whatever +host+
  # the page was opened by, and has no address while Tailscale can't serve it. Every address of
  # an app is made here (and Amahi-kai's by ApplicationHelper#amahi_url), so HTTPS can change
  # them in one place later. A spec checks.
  def url(host)
    return unless host_port

    entry = AppCatalog.find(identifier)
    return (name = TailscaleService.https_name) && "https://#{name}:#{host_port}/" if entry&.dig(:access) == 'tailscale'

    scheme = entry&.dig(:web_tls) ? 'https' : 'http'
    "#{scheme}://#{host}:#{host_port}/"
  end

  # Whether the app is reached only through Tailscale, over HTTPS (its manifest's access).
  def tailscale_only?
    AppCatalog.find(identifier)&.dig(:access) == 'tailscale'
  end

  # [{ host:, container:, protocol:, label: }]: the ports the app was given at install.
  def ports
    list = JSON.parse(port_mappings.to_s)
    list.is_a?(Array) ? list.grep(Hash).map { |port| port.symbolize_keys.slice(:host, :container, :protocol, :label) } : []
  rescue JSON::ParserError
    []
  end

  def ports=(list)
    self.port_mappings = list.to_json
  end

  # [{ name:, write: }]: the shares the app was given, at /shares/<name> inside it; folder: for one
  # given only a folder of the share, at /shares/<name>/<folder>.
  def shares
    list = JSON.parse(volume_mappings.to_s)
    return [] unless list.is_a?(Array)

    list.grep(Hash).map do |share|
      { name: share['name'].to_s, folder: share['folder'].presence, write: share['write'] == true }.compact
    end
  rescue JSON::ParserError
    []
  end

  def shares=(list)
    self.volume_mappings = list.map { |share| { name: share[:name], folder: share[:folder].presence, write: share[:write] == true }.compact }.to_json
  end

  # "Movies, Vault/media/Pictures (read only) · Downloads (read and write)": for the Apps page.
  def share_summary
    shares.group_by { |share| share[:write] }.sort_by { |write, _| write ? 1 : 0 }.map do |write, group|
      "#{group.map { |share| self.class.share_label(share) }.join(', ')} (#{write ? 'read and write' : 'read only'})"
    end.join(' · ')
  end

  # "Vault/media/Pictures" for a folder of a share, "Vault" for all of it.
  def self.share_label(share)
    [share[:name], share[:folder]].compact.join('/')
  end

  # The folders the app was given that aren't there now (renamed, moved or deleted): until it's
  # given its folders again, it can't start (the root helper only mounts real folders). A folder
  # of a share that's gone is one of missing_shares instead.
  def missing_folders
    given = shares.select { |share| share[:folder] }
    return [] if given.empty?

    paths = Share.where(name: given.map { |share| share[:name] }).to_h { |share| [share.name.downcase, share.path] }
    given.reject do |share|
      root = paths[share[:name].downcase]
      root.nil? || File.directory?(File.join(root, share[:folder]))
    end.map { |share| self.class.share_label(share) }
  end

  # [the shares it was given that the NAS has, those it hasn't any more], as #shares gives them.
  # A share can be gone with an app still listing it (deleted before 1.x kept a share an app has,
  # say): Update, Undo update and Change carry on without it, and its page says so.
  def shares_by_presence
    names = shares.map { |share| share[:name].downcase }.uniq
    have = names.empty? ? [] : Share.where('LOWER(name) IN (?)', names).pluck(:name).map(&:downcase)
    shares.partition { |share| have.include?(share[:name].downcase) }
  end

  # The shares (and folders of shares) it was given that are gone from the NAS: "Test", "Old/media".
  def missing_shares
    shares_by_presence.last.map { |share| self.class.share_label(share) }
  end

  # After a change only to how it's listed (apps.custom_save's update: false), the ports it was
  # given with the labels +listed+ (its catalog entry's ports) gives them now: the same container
  # has the same ports, in the same order. One that doesn't match keeps its label.
  def relabel_ports(listed)
    listed = Array(listed)
    return if listed.size != ports.size

    relabeled = ports.zip(listed).map do |port, now|
      next port unless port[:container] == now[:container] && port[:protocol] == now[:protocol]

      now[:label] ? port.merge(label: now[:label]) : port.except(:label)
    end
    update(ports: relabeled) if relabeled != ports
  end

  # "3300 (web) · 2222 (Git over SSH)", "51413 (peers, TCP and UDP)": for the Apps page.
  def port_summary
    ports.group_by { |port| [port[:host], port[:label]] }.map do |(host, label), group|
      protocols = group.map { |port| port[:protocol] }.uniq.sort
      kind = { %w[tcp udp] => 'TCP and UDP', %w[udp] => 'UDP' }[protocols]
      detail = [label, kind].compact.join(', ')
      detail.empty? ? host.to_s : "#{host} (#{detail})"
    end.join(' · ')
  end

  def start!
    helper('apps.start')
    update!(status: 'running', error_message: nil)
  end

  def stop!
    helper('apps.stop')
    update!(status: 'stopped', error_message: nil)
  end

  def restart!
    helper('apps.restart')
    update!(status: 'running', error_message: nil)
  end

  # Removes the app's container; its data stays unless +delete_data+ (DockerApp.uninstall).
  def uninstall!(delete_data: false)
    self.class.uninstall(identifier, delete_data: delete_data)
  end

  class << self
    # The catalog entry's ports with the host ports the helper gave them (apps.install's
    # reply: each catalog port as preferred, and the one it got); the catalog's own where the
    # reply has none (outside production).
    def assigned_ports(entry, given)
      given = Array(given).grep(Hash)
      entry[:ports].map do |port|
        match = given.find { |p| p['preferred'] == port[:host] && p['protocol'] == port[:protocol] }
        port.merge(host: match ? match['host'] : port[:host])
      end
    end

    # Removes an app, installed or not (deleting the data an earlier install kept).
    def uninstall(identifier, delete_data: false)
      Privileged.call('apps.uninstall', app: identifier, delete_data: delete_data)
      where(identifier: identifier).destroy_all
    rescue Privileged::Error => e
      where(identifier: identifier).update_all(status: 'error', error_message: e.message)
      raise ContainerError, e.message
    end

    # An app given a pooled share reads it through mounts made with its container: the share's
    # folder, and the share's copy folder on each pool drive. After the pool changes (a drive
    # joins or leaves, a share is pooled or turned Off, a pool drive is mounted), the root
    # helper makes again the containers whose mounts no longer match it (apps.follow_pool),
    # keeping each app's shares, version and data, so a drive taken out isn't held by an app.
    # Each restarts for a few seconds; a stopped one stays stopped. One it couldn't make again
    # shows why.
    def follow_pool!
      return unless where.not(volume_mappings: [nil, '', '[]']).exists?

      reply = Privileged.call('apps.follow_pool')
      refresh_statuses!
      # The shares each remade container has now (one gone from Samba is left out of it)
      (reply['shares'] || {}).each do |identifier, shares|
        app = find_by(identifier: identifier) or next
        app.update!(shares: Array(shares).grep(Hash).map { |share| { name: share['name'].to_s, folder: share['folder'], write: share['write'] == true } })
      end
      (reply['apps'] || {}).each do |identifier, outcome|
        next if outcome.to_s.start_with?('remade')

        where(identifier: identifier).update_all(status: 'error', error_message: "Couldn't follow the Greyhole pool's change: #{outcome}")
      end
    rescue Privileged::Error => e
      Rails.logger.error("DockerApp: the apps didn't follow the pool's change: #{e.message}")
    end

    # Each installed app's status from Docker, all at once (apps.status). Nothing changes when
    # Docker can't be asked. A row an install left on Installing (its page cut off: the web app
    # restarted while the job ran on) follows its container like the others once no job runs for
    # it (the reply's jobs) and it's had a minute to settle.
    def refresh_statuses!
      reply = Privileged.call('apps.status')
      return unless reply['docker']

      states = reply['apps'] || {}
      jobs = Array(reply['jobs'])
      busy = where(status: %w[pulling installing]).where(updated_at: 1.minute.ago..).or(where(identifier: jobs))
      where.not(id: busy.select(:id)).find_each do |app|
        state = states.dig(app.identifier, 'state')
        status = case state
                 when 'running', 'restarting' then 'running'
                 when 'exited', 'created', 'paused', 'dead' then 'stopped'
                 end
        if state.nil?
          # An install that failed keeps its own reason; one cut off says so.
          reason = %w[pulling installing].include?(app.status) ? 'Its install was cut off: install it again' : 'Its container is gone: install it again'
          app.update!(status: 'error', error_message: reason) unless app.status == 'error'
        elsif status && status != app.status
          app.update!(status: status, error_message: nil)
        end
      end
    rescue Privileged::Error => e
      Rails.logger.warn("DockerApp: couldn't read the apps' status: #{e.message}")
    end
  end

  private

  def helper(operation, **args)
    Privileged.call(operation, app: identifier, **args)
  rescue Privileged::Error => e
    update!(status: 'error', error_message: e.message)
    raise ContainerError, e.message
  end
end
