require 'shell'

class DockerApp < ApplicationRecord
  # A container operation failed. AppsController reports it to the page.
  class ContainerError < StandardError; end

  # Validations
  validates :identifier, presence: true, uniqueness: true
  validates :name, presence: true
  validates :image, presence: true
  validates :status, inclusion: { in: %w[available pulling installing running stopped error] }

  # Scopes
  scope :running, -> { where(status: 'running') }
  scope :dashboard, -> { where(show_in_dashboard: true) }
  scope :by_category, ->(cat) { where(category: cat) }

  # JSON accessors (stored as text for SQLite compatibility)
  def port_mappings
    val = super
    val.is_a?(String) ? JSON.parse(val) : (val || {})
  rescue JSON::ParserError
    {}
  end

  def port_mappings=(value)
    super(value.is_a?(Hash) ? value.to_json : value)
  end

  def volume_mappings
    val = super
    val.is_a?(String) ? JSON.parse(val) : (val || {})
  rescue JSON::ParserError
    {}
  end

  def volume_mappings=(value)
    super(value.is_a?(Hash) ? value.to_json : value)
  end

  def environment
    val = super
    val.is_a?(String) ? JSON.parse(val) : (val || {})
  rescue JSON::ParserError
    {}
  end

  def environment=(value)
    super(value.is_a?(Hash) ? value.to_json : value)
  end

  # URL for accessing this app through the reverse proxy
  def url
    "/app/#{identifier}"
  end

  # Container name defaults to identifier
  def effective_container_name
    container_name.presence || "amahi-#{identifier}"
  end

  # Uninstall the app
  def uninstall!
    if container_name.present?
      cname = Shellwords.escape(effective_container_name)
      # Force stop (30s timeout) then force remove — don't fail if container is already gone
      Shell.run("docker stop -t 30 #{cname} 2>/dev/null")
      Shell.run("docker rm -f -v #{cname} 2>/dev/null")
    end
    # Prune unused images to reclaim disk space
    Shell.run("docker image prune -f 2>/dev/null")
    # Clean up host app directory (configs, databases, etc.)
    app_dir = "/opt/amahi/apps/#{identifier}"
    Shell.run("rm -rf #{Shellwords.escape(app_dir)}") if identifier.present? && File.directory?(app_dir)
    update!(status: 'available', container_name: nil, host_port: nil, error_message: nil)
  rescue ContainerError, Shell::CommandError => e
    update!(status: 'error', error_message: e.message)
    raise
  end

  # Start the container
  def start!
    cname = Shellwords.escape(effective_container_name)
    result = Shell.run("docker start #{cname} 2>/dev/null")
    if result
      update!(status: 'running')
    else
      update!(status: 'error', error_message: 'Container not found — reinstall the app')
      raise ContainerError, "Failed to start container #{effective_container_name}"
    end
  end

  # Stop the container
  def stop!
    cname = Shellwords.escape(effective_container_name)
    output, stderr, status = Shell.capture("docker stop -t 30 #{cname}")
    # Use the status Shell.capture returns: it runs through Open3, which leaves $?
    # holding whatever command ran before, so stop used to succeed or fail at random.
    if status.success?
      update!(status: 'stopped')
    else
      # If container doesn't exist, force cleanup the DB record (docker says so on stderr)
      message = "#{output}\n#{stderr}"
      if message.include?('No such container') || message.include?('not found')
        update!(status: 'stopped')
      else
        update!(status: 'error', error_message: "Stop failed: #{message.strip}")
        raise ContainerError, "Failed to stop container #{effective_container_name}: #{message.strip}"
      end
    end
  end

  # Restart the container
  def restart!
    cname = Shellwords.escape(effective_container_name)
    unless Shell.run("docker restart #{cname} 2>/dev/null")
      update!(status: 'error', error_message: 'Restart failed')
      raise ContainerError, "Failed to restart container #{effective_container_name}"
    end
    update!(status: 'running')
  end

  # Refresh status from Docker
  def refresh_status!
    return unless container_name.present?
    cname = Shellwords.escape(effective_container_name)
    output, _stderr, _status = Shell.capture("docker inspect --format '{{.State.Status}}' #{cname}")
    output = output.strip
    case output
    when 'running' then update!(status: 'running')
    when 'exited', 'stopped' then update!(status: 'stopped')
    when 'restarting' then update!(status: 'running')
    else update!(status: 'error', error_message: 'Container not found')
    end
  end
end
