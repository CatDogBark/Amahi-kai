# An app installed from the catalog (AppCatalog, config/apps). The root helper does the work
# (apps.* operations, docs/plans/apps.md); the record keeps what the pages show: the app's
# status, its web port and whether it's on the dashboard. (Its old port, volume and
# environment columns are no longer used.)
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

  # The app's page, on its own port of the NAS (docs/plans/apps.md, O3).
  def url(host)
    "http://#{host}:#{host_port}/" if host_port
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
    # Removes an app, installed or not (deleting the data an earlier install kept).
    def uninstall(identifier, delete_data: false)
      Privileged.call('apps.uninstall', app: identifier, delete_data: delete_data)
      where(identifier: identifier).destroy_all
    rescue Privileged::Error => e
      where(identifier: identifier).update_all(status: 'error', error_message: e.message)
      raise ContainerError, e.message
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
