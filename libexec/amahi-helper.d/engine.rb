# frozen_string_literal: true

# The container engine, Docker: every command the helper gives it, everything it reads back from
# it, and the names it uses on the NAS (its bridge, the firewall chain it leaves for us, its
# service), in this one part. The apps part decides what a container gets (apps.rb: its user,
# memory, ports, folders, shares, DNS); this part only says it in Docker's words. Another engine
# would replace this part, keeping its methods and what they return; the other places that know
# about Docker are listed in docs/container-engine.md.
#
# What the rest of the helper reads from a container (engine_inspect) is Docker's inspect, and
# only these keys of it: Id, State (Running, Status, ExitCode, Error, Health.Status), Config.Image,
# HostConfig (Dns, DnsSearch, NanoCpus, NetworkMode), Mounts (Type, Source, Destination, RW) and
# RestartCount.
module AmahiHelper
  DOCKER = '/usr/bin/docker'

  # The engine's own service: services.* starts and stops it by this unit.
  ENGINE_UNIT = 'docker.service'

  # The bridge the apps' containers are on: their gateway, where Unbound answers them (dns.rb).
  ENGINE_BRIDGE = 'docker0'

  # The chain Docker sends forwarded traffic through before its own rules, and leaves to us:
  # APP_CHAIN hangs off it (apps.rb, do_app_firewall).
  ENGINE_FIREWALL_HOOK = 'DOCKER-USER'

  # How long a container is given to stop before it's killed.
  ENGINE_STOP_SECONDS = 30

  class << self
    # --- Whether it's there ---

    def engine_installed?
      File.executable?(DOCKER)
    end

    def engine_installed!
      installed!(DOCKER)
    end

    def engine_running?
      !docker_output('info', '--format', '{{.ServerVersion}}').nil?
    end

    # The engine answers: an uninstall while it's stopped left the container, which came back when
    # it started, unlisted.
    def engine_running!
      raise Refused, "Docker isn't running: start it (Apps), then try again" unless engine_running?

      true
    end

    # The IPv4 address of the apps' bridge (their gateway), or nil while the engine isn't up.
    def engine_bridge_address
      Socket.getifaddrs.find { |ifaddr| ifaddr.name == ENGINE_BRIDGE && ifaddr.addr&.ipv4? }&.addr&.ip_address
    end

    # --- Containers: what's there ---

    def engine_container?(name)
      !docker_output('inspect', '--format', '{{.Id}}', name).nil?
    end

    # The container's inspect (see the keys above), or nil when there's none.
    def engine_inspect(name)
      JSON.parse(docker_output('inspect', name) || '[]').first
    rescue JSON::ParserError
      nil
    end

    def engine_container_running?(name)
      docker_output('inspect', '--format', '{{.State.Running}}', name).to_s.strip == 'true'
    end

    # The image the container was made from, as it was given (name:tag@sha256:...); '' without one.
    def engine_container_image(name)
      docker_output('inspect', '--format', '{{.Config.Image}}', name).to_s.strip
    end

    # The container's State (see the keys above), or nil.
    def engine_container_state(name)
      out = docker_output('inspect', '--format', '{{json .State}}', name)
      out ? JSON.parse(out) : nil
    rescue JSON::ParserError
      nil
    end

    def engine_restart_count(name)
      docker_output('inspect', '--format', '{{.RestartCount}}', name).to_i
    end

    # The processors a container may use (+info+, engine_inspect's), as engine_create takes them;
    # nil for no limit.
    def engine_container_cpus(info)
      nano = info.dig('HostConfig', 'NanoCpus').to_i
      return nil unless nano.positive?

      (nano % 1_000_000_000).zero? ? nano / 1_000_000_000 : nano / 1_000_000_000.0
    end

    # The network a container is on (+info+, engine_inspect's): its name.
    def engine_container_network(info)
      info.dig('HostConfig', 'NetworkMode').to_s
    end

    # The DNS a container was made with (+info+, engine_inspect's), as engine_create takes it.
    def engine_container_dns(info)
      { servers: Array(info.dig('HostConfig', 'Dns')), search: Array(info.dig('HostConfig', 'DnsSearch')) }
        .reject { |_key, list| list.empty? }
    end

    # The amahi.app label of every container that has one, running or not: nil when the engine
    # isn't installed or running. Labels aren't checked here: a caller keeps those that are app ids.
    def engine_app_labels
      docker_output('ps', '--all', '--filter', 'label=amahi.app', '--format', '{{.Label "amahi.app"}}')&.lines(chomp: true)&.map(&:strip)
    end

    # [label, { 'state', 'status', 'image' }] for every container with an amahi.app label; nil when
    # the engine isn't installed or running.
    def engine_app_rows
      # The label by itself: joined with the image's own labels, a value there could read like it.
      out = docker_output('ps', '--all', '--filter', 'label=amahi.app', '--format', "{{.Label \"amahi.app\"}}\t{{json .}}")
      return nil unless out

      out.lines.filter_map do |line|
        label, json = line.chomp.split("\t", 2)
        next unless json

        row = JSON.parse(json)
        [label.to_s, { 'state' => row['State'], 'status' => row['Status'], 'image' => row['Image'] }]
      rescue JSON::ParserError
        nil
      end
    end

    # "<name>\t<ports>" for every running container, as the engine writes ports
    # ("0.0.0.0:8096->8096/tcp"); [] when it isn't installed or running.
    def engine_port_rows
      docker_output('ps', '--format', "{{.Names}}\t{{.Ports}}").to_s.lines(chomp: true).reject(&:empty?)
    end

    # { full id => name } for the running containers; {} without the engine.
    def container_names
      return {} unless engine_installed?

      capture([DOCKER, 'ps', '--no-trunc', '--format', '{{.ID}} {{.Names}}']).lines.to_h { |line| line.split(' ', 2).map(&:strip) }
    rescue Failed
      {}
    end

    # The container's last +lines+ of output, stdout and stderr together, each with its time.
    def engine_logs(name, lines)
      out, status = Open3.capture2e(ENV_MIN, [DOCKER, DOCKER], 'logs', '--tail', lines.to_s, '--timestamps', name,
                                    unsetenv_others: true, chdir: '/')
      raise Failed, "docker logs exited #{status.exitstatus}: #{last_lines(out, 3)}" unless status.success?

      out
    end

    # --- Images ---

    # The image is here already, by its digest (a tag can move; the digest can't).
    def engine_image_present?(image)
      !docker_output('image', 'inspect', '--format', '{{.Id}}', image.sub(%r{:[^:@/]+@}, '@')).nil?
    end

    def engine_pull(image)
      run_command([DOCKER, 'pull', image, { stream: true }])
    end

    def engine_remove_image(image)
      run_command([DOCKER, 'image', 'rm', image, { allow_failure: true }])
    end

    # --- Networks ---

    # The subnet of the network +name+ (its first), or nil when there's none of that name.
    def engine_network_subnet(name)
      out = docker_output('network', 'inspect', '--format', '{{range .IPAM.Config}}{{.Subnet}} {{end}}', name)
      out && out.split.first.to_s
    end

    # An app's own network, made unless it's there with this +subnet+: a bridge of its own, its
    # interface named +bridge+, +gateway+ the NAS's address on it, labelled with the app. One of
    # the name on another subnet is made again (never while a container is on it: Docker refuses).
    def engine_network_ensure(name, subnet:, gateway:, bridge:, label:)
      have = engine_network_subnet(name)
      return if have == subnet

      engine_network_remove(name) if have
      run_command([DOCKER, 'network', 'create', '--driver', 'bridge', '--subnet', subnet, '--gateway', gateway,
                   '--opt', "com.docker.network.bridge.name=#{bridge}", '--label', "amahi.app=#{label}", name])
    end

    # Gone, if it was there and nothing's on it.
    def engine_network_remove(name)
      run_command([DOCKER, 'network', 'rm', name, { allow_failure: true }])
    end

    # --- Containers: changing them ---

    # The commands by themselves, for an operation's plan (apps.start, apps.stop, apps.restart).
    def engine_start_command(name)
      [DOCKER, 'start', name]
    end

    def engine_stop_command(name)
      [DOCKER, 'stop', '--time', ENGINE_STOP_SECONDS.to_s, name]
    end

    def engine_restart_command(name)
      [DOCKER, 'restart', '--time', ENGINE_STOP_SECONDS.to_s, name]
    end

    def engine_start(name, allow_failure: false)
      run_command(engine_step(engine_start_command(name), allow_failure))
    end

    def engine_stop(name, allow_failure: false)
      run_command(engine_step(engine_stop_command(name), allow_failure))
    end

    # Gone, running or not; nothing when there was none.
    def engine_remove(name)
      run_command([DOCKER, 'rm', '--force', name, { allow_failure: true }])
    end

    def engine_rename(name, new_name)
      run_command([DOCKER, 'rename', name, new_name])
    end

    # The processors a container may use, changed in place, running or not (no restart): nil, or
    # why not.
    def engine_set_cpus(name, cpus)
      run_command([DOCKER, 'update', '--cpus', cpus.to_s, name, { allow_failure: true }])
    end

    # A container made from +image+ and never started, to copy a file out of it (engine_copy_out).
    def engine_create_scratch(name, image)
      run_command([DOCKER, 'create', '--name', name, image])
    end

    # The file at +path+ in the container, a link there followed, copied to +to+ on the NAS.
    def engine_copy_out(name, path, to)
      run_command([DOCKER, 'cp', '--follow-link', "#{name}:#{path}", to])
    end

    # Makes an app's container, not started. +spec+ is what the apps part decided:
    #   image:             name:tag@sha256:... (APP_IMAGE)
    #   restart:           when the engine starts it again ('unless-stopped')
    #   no_new_privileges: true: nothing in it gains privileges, setuid files included
    #   cap_drop:          capabilities it doesn't get
    #   pids_limit:        the most processes it may have
    #   log:               { size:, files: } kept of its output
    #   memory:            '512m', '2g'
    #   cpus:              the most processors it may use, or nil for no limit
    #   label:             its app id, as the amahi.app label
    #   network:           the network it's on, or nil for the engine's own bridge
    #   dns:               { servers: [address], search: [domain] }, either left out for the engine's own
    #   env_file:          the file its environment is read from (secrets stay off the command line)
    #   user:              'uid:gid' it runs as, or nil for the image's own
    #   group_add:         [gid] it's also in
    #   publish:           [{ address:, host:, container:, protocol: }]
    #   mounts:            [{ source:, target:, readonly: }] bound into it, in order
    def engine_create(name, spec)
      dns = spec.fetch(:dns, {})
      log = spec.fetch(:log)
      run_command([DOCKER, 'create', '--name', name, '--restart', spec.fetch(:restart),
                   *(spec[:no_new_privileges] ? ['--security-opt', 'no-new-privileges'] : []),
                   *spec.fetch(:cap_drop).flat_map { |cap| ['--cap-drop', cap] },
                   '--pids-limit', spec.fetch(:pids_limit).to_s,
                   '--log-opt', "max-size=#{log.fetch(:size)}", '--log-opt', "max-file=#{log.fetch(:files)}",
                   '--memory', spec.fetch(:memory), *(spec[:cpus] ? ['--cpus', spec[:cpus].to_s] : []),
                   '--label', "amahi.app=#{spec.fetch(:label)}", *(spec[:network] ? ['--network', spec[:network]] : []),
                   *Array(dns[:servers]).flat_map { |server| ['--dns', server] },
                   *Array(dns[:search]).flat_map { |domain| ['--dns-search', domain] },
                   '--env-file', spec.fetch(:env_file),
                   *(spec[:user] ? ['--user', spec[:user]] : []),
                   *Array(spec[:group_add]).flat_map { |gid| ['--group-add', gid.to_s] },
                   *spec.fetch(:publish).flat_map { |p| ['--publish', "#{p[:address]}:#{p[:host]}:#{p[:container]}/#{p[:protocol]}"] },
                   *spec.fetch(:mounts).flat_map { |m| ['--mount', "type=bind,source=#{m[:source]},target=#{m[:target]}#{',readonly' if m[:readonly]}"] },
                   spec.fetch(:image)])
    end

    # docker's output, or nil when it isn't installed, isn't running, or the command failed.
    def docker_output(*args)
      return nil unless engine_installed?

      out, _err, status = Open3.capture3(ENV_MIN, [DOCKER, DOCKER], *args, unsetenv_others: true, chdir: '/')
      status.success? ? out : nil
    rescue SystemCallError
      nil
    end

    private

    def engine_step(argv, allow_failure)
      allow_failure ? [*argv, { allow_failure: true }] : argv
    end
  end
end
