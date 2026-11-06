require 'rails_helper'

# The container engine (libexec/amahi-helper.d/engine.rb): every command Docker is given, and
# everything read back from it, is in that one part, so another engine is a change to one file
# (docs/container-engine.md). The apps part decides what a container gets; the engine part spells
# it. Nothing here runs Docker.
RSpec.describe 'AmahiHelper container engine' do
  let(:helper) { AmahiHelper }
  let(:parts) { Rails.root.join('libexec/amahi-helper.d') }

  before(:all) { Privileged.operations } # loads the helper's source

  # Docker's program, its output reader, its names on the NAS, and the flags only it reads
  # (DOCKER_MODS, an environment name the apps part refuses, isn't one).
  ENGINE_WORDS = [/\bDOCKER\b(?!_)/, /docker_output/, %r{/usr/bin/docker\b}, /'docker0'/, /'DOCKER-USER'/, /'docker\.service'/,
                  /'--(?:mount|publish|dns|dns-search|cap-drop|cap-add|group-add|security-opt|pids-limit|log-opt|env-file|restart)'/].freeze

  it 'is the one part that names Docker, its flags, or its names on the NAS' do
    found = (Dir[parts.join('*.rb')] + [Rails.root.join('libexec/amahi-helper').to_s]).flat_map do |path|
      next [] if File.basename(path) == 'engine.rb'

      File.readlines(path).each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?('#')

        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line.strip}" if ENGINE_WORDS.any? { |word| line.match?(word) }
      end
    end
    expect(found).to eq([])
  end

  describe 'engine_create' do
    let(:ran) { [] }

    before { allow(helper).to receive(:run_command) { |argv| ran << argv && nil } }

    def spec(**changes)
      { image: "example/app:1.0@sha256:#{'a' * 64}", restart: 'unless-stopped', no_new_privileges: true,
        cap_drop: %w[NET_RAW MKNOD], pids_limit: 2048, log: { size: '10m', files: 3 }, memory: '1g', label: 'transmission',
        dns: { servers: ['172.17.0.1'], search: ['home.arpa'] }, env_file: '/run/amahi-kai/env.1', user: nil, group_add: [100],
        publish: [{ address: '0.0.0.0', host: 9091, container: 9091, protocol: 'tcp' }, { address: '0.0.0.0', host: 51_413, container: 51_413, protocol: 'udp' }],
        mounts: [{ source: '/srv/apps/transmission/config', target: '/config' },
                 { source: '/run/amahi-kai-app-shares/transmission/1/0', target: '/shares/Downloads', readonly: false },
                 { source: '/run/amahi-kai-app-shares/transmission/1/1', target: '/shares/Movies', readonly: true }] }.merge(changes)
    end

    it "spells what the apps part decided in Docker's flags, in one command" do
      helper.engine_create('amahi-transmission-next', spec)
      expect(ran.sole).to eq(['/usr/bin/docker', 'create', '--name', 'amahi-transmission-next', '--restart', 'unless-stopped',
                              '--security-opt', 'no-new-privileges', '--cap-drop', 'NET_RAW', '--cap-drop', 'MKNOD',
                              '--pids-limit', '2048', '--log-opt', 'max-size=10m', '--log-opt', 'max-file=3',
                              '--memory', '1g', '--label', 'amahi.app=transmission',
                              '--dns', '172.17.0.1', '--dns-search', 'home.arpa', '--env-file', '/run/amahi-kai/env.1',
                              '--group-add', '100',
                              '--publish', '0.0.0.0:9091:9091/tcp', '--publish', '0.0.0.0:51413:51413/udp',
                              '--mount', 'type=bind,source=/srv/apps/transmission/config,target=/config',
                              '--mount', 'type=bind,source=/run/amahi-kai-app-shares/transmission/1/0,target=/shares/Downloads',
                              '--mount', 'type=bind,source=/run/amahi-kai-app-shares/transmission/1/1,target=/shares/Movies,readonly',
                              "example/app:1.0@sha256:#{'a' * 64}"])
    end

    it "leaves out the user, the extra groups and the DNS when there are none, so the image's and the engine's own apply" do
      helper.engine_create('amahi-transmission-next', spec(user: nil, group_add: [], dns: {}))
      expect(ran.sole).not_to include('--user', '--group-add', '--dns', '--dns-search')
      helper.engine_create('amahi-gitea-next', spec(user: '987:987'))
      expect(ran.last.each_cons(2).to_a).to include(['--user', '987:987'])
    end
  end

  it "reads a container's DNS back as engine_create takes it, so the two compare" do
    expect(helper.engine_container_dns('HostConfig' => { 'Dns' => ['172.17.0.1'], 'DnsSearch' => ['home.arpa'] }))
      .to eq(servers: ['172.17.0.1'], search: ['home.arpa'])
    expect(helper.engine_container_dns('HostConfig' => { 'Dns' => [], 'DnsSearch' => nil })).to eq({})
  end

  it "gives start, stop and restart as commands for an operation's plan, and runs them with a failure allowed when asked" do
    ran = []
    allow(helper).to receive(:run_command) { |argv| ran << argv && nil }
    expect(helper.plan('apps.stop', { id: 'gitea' })).to eq([%w[/usr/bin/docker stop --time 30 amahi-gitea]])
    expect(helper.plan('apps.restart', { id: 'gitea' })).to eq([%w[/usr/bin/docker restart --time 30 amahi-gitea]])
    expect(helper.plan('apps.start', { id: 'gitea' })).to eq([%w[/usr/bin/docker start amahi-gitea]])
    helper.engine_start('amahi-gitea', allow_failure: true)
    helper.engine_stop('amahi-gitea')
    expect(ran).to eq([['/usr/bin/docker', 'start', 'amahi-gitea', { allow_failure: true }], %w[/usr/bin/docker stop --time 30 amahi-gitea]])
  end
end
