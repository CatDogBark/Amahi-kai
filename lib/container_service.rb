require 'docker'

class ContainerService
  class ContainerError < StandardError; end

  MANAGED_LABEL = 'amahi.managed'
  APP_LABEL = 'amahi.app'

  def self.available?
    return true unless production?
    begin
      Docker.ping == 'OK'
    rescue => e
      false
    end
  end

  def self.list
    return [] unless production?
    Docker::Container.all(
      all: true,
      filters: { label: ["#{MANAGED_LABEL}=true"] }.to_json
    ).map { |c| container_info(c) }
  end

  def self.find(name)
    return dummy_container(name) unless production?
    container = Docker::Container.get(name)
    container_info(container)
  rescue Docker::Error::NotFoundError
    nil
  end

  def self.pull_image(image_name, &progress_block)
    return true unless production?
    Docker::Image.create('fromImage' => image_name) do |chunk|
      progress_block&.call(chunk)
    end
    true
  rescue => e
    raise ContainerError, "Failed to pull image #{image_name}: #{e.message}"
  end

  def self.create(options)
    return dummy_container(options[:name]) unless production?

    image = options[:image] || raise(ContainerError, "Image is required")
    name = options[:name] || raise(ContainerError, "Name is required")
    ports = options[:ports] || {}
    volumes = options[:volumes] || {}
    environment = options[:environment] || {}
    labels = options[:labels] || {}

    port_bindings = {}
    exposed_ports = {}
    ports.each do |container_port, host_port|
      key = container_port.to_s.include?('/') ? container_port.to_s : "#{container_port}/tcp"
      port_bindings[key] = [{ 'HostPort' => host_port.to_s }]
      exposed_ports[key] = {}
    end

    binds = volumes.map { |container_path, host_path| "#{host_path}:#{container_path}" }
    env = environment.map { |k, v| "#{k}=#{v}" }

    all_labels = labels.merge(MANAGED_LABEL => 'true')
    all_labels[APP_LABEL] = options[:identifier] if options[:identifier]

    container = Docker::Container.create(
      'name' => name,
      'Image' => image,
      'ExposedPorts' => exposed_ports,
      'Env' => env,
      'Labels' => all_labels,
      'HostConfig' => {
        'Binds' => binds,
        'PortBindings' => port_bindings,
        'RestartPolicy' => { 'Name' => 'unless-stopped' }
      }
    )
    container.start
    container_info(container)
  rescue Docker::Error::DockerError => e
    raise ContainerError, "Failed to create container: #{e.message}"
  end

  def self.start(name)
    return true unless production?
    container = Docker::Container.get(name)
    container.start
    true
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  def self.stop(name)
    return true unless production?
    container = Docker::Container.get(name)
    container.stop
    true
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  def self.restart(name)
    return true unless production?
    container = Docker::Container.get(name)
    container.restart
    true
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  def self.remove(name, remove_volumes: false)
    return true unless production?
    container = Docker::Container.get(name)
    container.stop rescue nil
    container.remove(v: remove_volumes)
    true
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  def self.status(name)
    return 'stopped' unless production?
    container = Docker::Container.get(name)
    state = container.json['State']
    if state['Running']
      'running'
    elsif state['Paused']
      'paused'
    else
      'stopped'
    end
  rescue Docker::Error::NotFoundError
    'not_found'
  end

  def self.logs(name, lines: 100)
    return "Dummy logs for #{name}" unless production?
    container = Docker::Container.get(name)
    container.logs(stdout: true, stderr: true, tail: lines)
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  def self.stats(name)
    return { cpu: 0.0, memory: 0 } unless production?
    container = Docker::Container.get(name)
    stats = container.stats(stream: false)
    {
      cpu: calculate_cpu_percent(stats),
      memory: stats.dig('memory_stats', 'usage') || 0,
      memory_limit: stats.dig('memory_stats', 'limit') || 0
    }
  rescue Docker::Error::NotFoundError
    raise ContainerError, "Container #{name} not found"
  end

  private

  def self.production?
    defined?(Rails) && Rails.env.production?
  end

  def self.dummy_container(name)
    {
      name: name || 'dummy',
      status: 'stopped',
      image: 'dummy:latest',
      id: 'dummy_id'
    }
  end

  def self.container_info(container)
    json = container.json
    {
      id: json['Id'],
      name: json['Name']&.sub(/^\//, ''),
      image: json.dig('Config', 'Image'),
      status: json.dig('State', 'Status'),
      labels: json.dig('Config', 'Labels') || {},
      ports: json.dig('HostConfig', 'PortBindings') || {},
      created: json['Created']
    }
  end

  def self.calculate_cpu_percent(stats)
    cpu_delta = (stats.dig('cpu_stats', 'cpu_usage', 'total_usage') || 0) -
                (stats.dig('precpu_stats', 'cpu_usage', 'total_usage') || 0)
    system_delta = (stats.dig('cpu_stats', 'system_cpu_usage') || 0) -
                   (stats.dig('precpu_stats', 'system_cpu_usage') || 0)
    return 0.0 if system_delta <= 0 || cpu_delta <= 0
    num_cpus = stats.dig('cpu_stats', 'online_cpus') || 1
    (cpu_delta.to_f / system_delta * num_cpus * 100).round(2)
  end
end
