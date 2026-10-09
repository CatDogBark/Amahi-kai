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

  # The catalog has another version of it (P4.5): System Update brought a newer manifest.
  def update_available?
    entry = AppCatalog.find(identifier)
    entry.present? && image.present? && entry[:image] != image
  end

  def catalog_version
    AppCatalog.tag(AppCatalog.find(identifier)&.dig(:image))
  end

  # The catalog's logo, which may have changed (or arrived) since the install, else the one
  # saved then.
  def logo_url
    AppCatalog.find(identifier)&.dig(:logo_url).presence || super
  end

  # The app's page, on its own port of the NAS (docs/plans/apps.md, O3): HTTPS when its manifest
  # says its page is (`web_tls`, with its own certificate). Every address of an app is made here
  # (and Amahi-kai's by ApplicationHelper#amahi_url), so HTTPS can change them in one place
  # later. A spec checks.
  def url(host)
    return unless host_port

    scheme = AppCatalog.find(identifier)&.dig(:web_tls) ? 'https' : 'http'
    "#{scheme}://#{host}:#{host_port}/"
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

  # [{ name:, write: }]: the shares the app was given, at /shares/<name> inside it.
  def shares
    list = JSON.parse(volume_mappings.to_s)
    list.is_a?(Array) ? list.grep(Hash).map { |share| { name: share['name'].to_s, write: share['write'] == true } } : []
  rescue JSON::ParserError
    []
  end

  def shares=(list)
    self.volume_mappings = list.map { |share| { name: share[:name], write: share[:write] == true } }.to_json
  end

  # "Movies, TV (read only) · Downloads (read and write)": for the Apps page.
  def share_summary
    shares.group_by { |share| share[:write] }.sort_by { |write, _| write ? 1 : 0 }.map do |write, group|
      "#{group.map { |share| share[:name] }.join(', ')} (#{write ? 'read and write' : 'read only'})"
    end.join(' · ')
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
      (reply['apps'] || {}).each do |identifier, outcome|
        next if outcome.to_s.start_with?('remade')

        where(identifier: identifier).update_all(status: 'error', error_message: "Couldn't follow the Greyhole pool's change: #{outcome}")
      end
    rescue Privileged::Error => e
      Rails.logger.error("DockerApp: the apps didn't follow the pool's change: #{e.message}")
    end

    # Each installed app's status from Docker, all at once (apps.status). Nothing changes when
    # Docker can't be asked.
    def refresh_statuses!
      reply = Privileged.call('apps.status')
      return unless reply['docker']

      states = reply['apps'] || {}
      where.not(status: %w[pulling installing]).find_each do |app|
        state = states.dig(app.identifier, 'state')
        status = case state
                 when 'running', 'restarting' then 'running'
                 when 'exited', 'created', 'paused', 'dead' then 'stopped'
                 end
        if state.nil?
          # An install that failed keeps its own reason.
          app.update!(status: 'error', error_message: 'Its container is gone: install it again') unless app.status == 'error'
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
