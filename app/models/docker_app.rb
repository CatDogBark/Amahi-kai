class DockerApp < ApplicationRecord
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

  # Container name defaults to identifier
  def effective_container_name
    container_name.presence || "amahi-#{identifier}"
  end

  # Install the app (synchronous)
  def install!
    update!(status: 'pulling')
    ContainerService.pull_image(image)
    update!(status: 'installing')
    result = ContainerService.create(
      image: image,
      name: effective_container_name,
      identifier: identifier,
      ports: port_mappings,
      volumes: volume_mappings,
      environment: environment
    )
    # Determine host port from result or port_mappings
    first_port = port_mappings.values.first
    update!(status: 'running', container_name: effective_container_name, host_port: first_port)
  rescue => e
    update!(status: 'error', error_message: e.message)
    raise
  end

  # Install in background (forked process)
  def install_async!
    if Rails.env.production?
      pid = Process.fork do
        install!
      end
      Process.detach(pid)
    else
      # In dev/test, just install synchronously (Docker calls are stubbed)
      install!
    end
  end

  # Uninstall the app
  def uninstall!
    ContainerService.remove(effective_container_name, remove_volumes: true) if container_name.present?
    # Clean up host app directory
    app_dir = "/opt/amahi/apps/#{identifier}"
    FileUtils.rm_rf(app_dir) if identifier.present? && File.directory?(app_dir)
    update!(status: 'available', container_name: nil, host_port: nil, error_message: nil)
  rescue => e
    update!(status: 'error', error_message: e.message)
    raise
  end

  # Start the container
  def start!
    ContainerService.start(effective_container_name)
    update!(status: 'running')
  rescue ContainerService::ContainerError => e
    if e.message.include?('not found')
      update!(status: 'error', error_message: 'Container not found — reinstall the app')
    end
    raise
  end

  # Stop the container
  def stop!
    ContainerService.stop(effective_container_name)
    update!(status: 'stopped')
  rescue ContainerService::ContainerError => e
    if e.message.include?('not found')
      update!(status: 'error', error_message: 'Container not found — reinstall the app')
    end
    raise
  end

  # Restart the container
  def restart!
    ContainerService.restart(effective_container_name)
    update!(status: 'running')
  end

  # Refresh status from Docker
  def refresh_status!
    return unless container_name.present?
    docker_status = ContainerService.status(effective_container_name)
    update!(status: docker_status == 'not_found' ? 'error' : docker_status)
  end
end
