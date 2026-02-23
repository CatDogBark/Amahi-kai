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

    # Create host directories for volumes and set permissions so containers can write
    prepare_host_directories!

    # Write init_files from catalog (e.g., config files the app needs at first boot)
    write_init_files!

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
    if container_name.present?
      cname = Shellwords.escape(effective_container_name)
      # Force stop (30s timeout) then force remove — don't fail if container is already gone
      system("sudo docker stop -t 30 #{cname} 2>/dev/null")
      system("sudo docker rm -f -v #{cname} 2>/dev/null")
    end
    # Prune unused images to reclaim disk space
    system("sudo docker image prune -f 2>/dev/null")
    # Clean up host app directory (configs, databases, etc.)
    app_dir = "/opt/amahi/apps/#{identifier}"
    system("sudo rm -rf #{Shellwords.escape(app_dir)}") if identifier.present? && File.directory?(app_dir)
    update!(status: 'available', container_name: nil, host_port: nil, error_message: nil)
  rescue => e
    update!(status: 'error', error_message: e.message)
    raise
  end

  # Start the container
  def start!
    cname = Shellwords.escape(effective_container_name)
    result = system("sudo docker start #{cname} 2>/dev/null")
    if result
      update!(status: 'running')
    else
      update!(status: 'error', error_message: 'Container not found — reinstall the app')
      raise "Failed to start container #{effective_container_name}"
    end
  end

  # Stop the container
  def stop!
    cname = Shellwords.escape(effective_container_name)
    output = `sudo docker stop -t 30 #{cname} 2>&1`
    if $?.success?
      update!(status: 'stopped')
    else
      # If container doesn't exist, force cleanup the DB record
      if output.include?('No such container') || output.include?('not found')
        update!(status: 'stopped')
      else
        update!(status: 'error', error_message: "Stop failed: #{output.strip}")
        raise "Failed to stop container #{effective_container_name}: #{output.strip}"
      end
    end
  end

  # Restart the container
  def restart!
    cname = Shellwords.escape(effective_container_name)
    system("sudo docker restart #{cname} 2>/dev/null")
    update!(status: 'running')
  end

  # Refresh status from Docker
  def refresh_status!
    return unless container_name.present?
    cname = Shellwords.escape(effective_container_name)
    output = `sudo docker inspect --format '{{.State.Status}}' #{cname} 2>/dev/null`.strip
    case output
    when 'running' then update!(status: 'running')
    when 'exited', 'stopped' then update!(status: 'stopped')
    when 'restarting' then update!(status: 'running')
    else update!(status: 'error', error_message: 'Container not found')
    end
  end

  private

  # Create host directories for all volume mounts and set open permissions
  # so non-root containers can write to them
  def prepare_host_directories!
    return unless volume_mappings.present?
    volume_mappings.each do |_container_path, host_path|
      next if host_path.blank?
      # Skip shared/system paths like /var/run/docker.sock
      next if host_path.start_with?('/var/run/')
      system("sudo mkdir -p #{Shellwords.escape(host_path)}")
      system("sudo chmod 777 #{Shellwords.escape(host_path)}")
    end
  end

  # Write init_files from the catalog (config files needed before first boot)
  def write_init_files!
    catalog_entry = AppCatalog.find(identifier) rescue nil
    return unless catalog_entry && catalog_entry[:init_files].present?

    catalog_entry[:init_files].each do |file_spec|
      host_path = file_spec[:host] || file_spec['host']
      content = file_spec[:content] || file_spec['content']
      next unless host_path && content

      dir = File.dirname(host_path)
      system("sudo mkdir -p #{Shellwords.escape(dir)}")
      # Write via temp file + sudo mv to handle root-owned directories
      require 'tempfile'
      tmp = Tempfile.new('init_file')
      tmp.write(content)
      tmp.close
      system("sudo cp #{Shellwords.escape(tmp.path)} #{Shellwords.escape(host_path)}")
      system("sudo chmod 644 #{Shellwords.escape(host_path)}")
      tmp.unlink
    end
  end
end
