require 'rails_helper'

# Tokens for private images (the root helper's registry.rb): kept where only root reads them,
# shown to the app only as their status, sent only to their own registry, and used only for the
# images under their place. The registry here is a fake that answers as ghcr.io and Docker Hub do.
RSpec.describe 'AmahiHelper tokens for private images' do
  let(:helper) { AmahiHelper }
  let(:dir) { Dir.mktmpdir }
  let(:token) { "ghp_#{'a' * 36}" }
  let(:digest) { "sha256:#{'d' * 64}" }
  let(:requests) { [] }
  # What the fake registry says to each request: [code, body, headers]
  let(:routes) do
    good = "Basic #{["CatDogBark:#{token}"].pack('m0')}"
    {
      'GET https://ghcr.io/v2/' => ->(_h) { [401, '', { 'WWW-Authenticate' => 'Bearer realm="https://ghcr.io/token",service="ghcr.io"' }] },
      'GET https://ghcr.io/token' => ->(h) { h['Authorization'] == good ? [200, '{"token":"bearer-1"}'] : [403, '{"errors":[{"code":"DENIED"}]}'] },
      'HEAD https://ghcr.io/v2/catdogbark/bitstream/manifests/0.2.1' =>
        ->(h) { h['Authorization'] == 'Bearer bearer-1' ? [200, '', { 'Docker-Content-Digest' => digest }] : [401, ''] },
      'HEAD https://ghcr.io/v2/catdogbark/bitstream/manifests/9.9' => ->(_h) { [404, ''] },
      'GET https://ghcr.io/v2/catdogbark/bitstream/tags/list' => lambda { |_h|
        [200, '{"tags":["0.2.0","0.2.1"]}', { 'Link' => '</v2/catdogbark/bitstream/tags/list?last=0.2.1&n=1000>; rel="next"' }]
      }
    }
  end

  before(:all) { Privileged.operations } # loads the helper's source once

  before do
    stub_const('AmahiHelper::REGISTRY_TOKENS', "#{dir}/etc/registry-tokens.json")
    stub_const('AmahiHelper::REGISTRY_STATUS', "#{dir}/registry-tokens.json")
    allow(helper).to receive(:group_id).and_call_original
    allow(helper).to receive(:group_id).with('amahi').and_return(Process.gid)
    allow_any_instance_of(File).to receive(:chown) # do_install gives root the file
    allow(helper).to receive(:registry_answer) do |uri, method: :get, headers: {}|
      key = "#{method.to_s.upcase} #{uri.scheme}://#{uri.host}#{uri.path}"
      requests << { key: key, query: uri.query, headers: headers }
      code, body, more = (routes[key] || ->(_h) { [404, ''] }).call(headers)
      reply(code, body, more || {})
    end
  end

  after { FileUtils.rm_rf(dir) }

  def reply(code, body = '', headers = {})
    response = Net::HTTPResponse::CODE_TO_OBJ[code.to_s].new('1.1', code.to_s, '')
    headers.each { |name, value| response[name] = value }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def run(op, args)
    values = helper.validate(op, args)
    helper.plan(op, values).map { |step| helper.send("do_#{step.first}", *step.drop(1)) }.last
  end

  def save(args = {})
    run('registry.save', { 'host' => 'ghcr.io', 'owner' => 'catdogbark', 'username' => 'CatDogBark', 'token' => token,
                           'note' => 'Amahi-kai NAS' }.merge(args))
  end

  def status
    JSON.parse(File.read("#{dir}/registry-tokens.json"))['tokens']
  end

  def kept
    JSON.parse(File.read("#{dir}/etc/registry-tokens.json"))['tokens']
  end

  describe 'registry.save' do
    it 'signs in as docker login does, then keeps the token for root alone and its status for the app' do
      expect(save).to eq('place' => 'ghcr.io/catdogbark', 'saved' => true, 'replaced' => false)
      sign_in = requests.find { |r| r[:key] == 'GET https://ghcr.io/token' }
      expect(sign_in[:query]).to eq('service=ghcr.io') # no image named
      expect(kept).to eq('ghcr.io/catdogbark' => { 'username' => 'CatDogBark', 'token' => token })
      expect(File.stat("#{dir}/etc/registry-tokens.json").mode & 0o777).to eq(0o600)
      expect(status).to contain_exactly(include('place' => 'ghcr.io/catdogbark', 'username' => 'CatDogBark', 'note' => 'Amahi-kai NAS', 'worked' => true))
      expect(File.read("#{dir}/registry-tokens.json")).not_to include(token)
      expect(File.stat("#{dir}/registry-tokens.json").mode & 0o777).to eq(0o640)
    end

    it 'saves nothing when the registry refuses the token' do
      expect { save('token' => "ghp_#{'b' * 36}") }.to raise_error(AmahiHelper::RegistryRefused, 'ghcr.io refused the token')
      expect(File).not_to exist("#{dir}/etc/registry-tokens.json")
    end

    it 'replaces the token a place has, and takes no more than its limit of places' do
      save
      expect(save('note' => nil)).to include('replaced' => true)
      expect(status.size).to eq(1)
      expect(status.first['note']).to be_nil
      stub_const('AmahiHelper::REGISTRY_MAX', 1)
      expect { save('owner' => 'someoneelse') }.to raise_error(AmahiHelper::Failed, /has 1 tokens already/)
    end

    it 'sends the token only to a realm in the registry\'s own domain, over https' do
      routes['GET https://ghcr.io/v2/'] = ->(_h) { [401, '', { 'WWW-Authenticate' => 'Bearer realm="https://ghcr.io.example.net/token",service="x"' }] }
      expect { save }.to raise_error(AmahiHelper::Failed, 'ghcr.io sends sign-ins to ghcr.io.example.net, outside its own domain')
      routes['GET https://ghcr.io/v2/'] = ->(_h) { [401, '', { 'WWW-Authenticate' => 'Bearer realm="http://ghcr.io/token"' }] }
      expect { save }.to raise_error(AmahiHelper::Failed, /which isn't https/)
      expect(requests.map { |r| r[:headers]['Authorization'] }.compact).to be_empty
      expect(helper.registry_same_domain?('registry-1.docker.io', 'auth.docker.io')).to be(true)
      expect(helper.registry_same_domain?('registry.gitlab.com', 'gitlab.com')).to be(true)
      expect(helper.registry_same_domain?('ghcr.io', 'evilghcr.io')).to be(false)
    end

    it 'signs in to a registry that asks for the sign-in itself (Basic)' do
      routes['GET https://registry.example.com/v2/'] = lambda { |h|
        if h['Authorization'] == "Basic #{["me:#{token}"].pack('m0')}" then [200, '{}']
        else [401, '', { 'WWW-Authenticate' => 'Basic realm="registry"' }]
        end
      }
      expect(save('host' => 'registry.example.com', 'owner' => 'team/apps', 'username' => 'me')).to include('place' => 'registry.example.com/team/apps')
    end

    it 'refuses what it mustn\'t keep or send' do
      expect { save('host' => 'GHCR.io') }.to raise_error(AmahiHelper::Refused, /must be a host name/)
      expect { save('host' => 'nas.localhost') }.to raise_error(AmahiHelper::Refused, /is the NAS itself/)
      expect { save('host' => 'ghcr.io:5000') }.to raise_error(AmahiHelper::Refused, /must be a host name/)
      expect { save('owner' => 'CatDogBark') }.to raise_error(AmahiHelper::Refused, /must be lowercase names/)
      expect { save('owner' => 'a/../b') }.to raise_error(AmahiHelper::Refused, /must be lowercase names/)
      expect { save('username' => 'me:you') }.to raise_error(AmahiHelper::Refused, /no colon/)
      expect { save('token' => 'two words here') }.to raise_error(AmahiHelper::Refused, /no spaces/)
      expect { save('note' => "one\ntwo") }.to raise_error(AmahiHelper::Refused, 'the note must be one line')
      expect(requests).to be_empty
    end

    it 'takes Docker Hub by any of its names' do
      expect(helper.registry_host('index.docker.io')).to eq('docker.io')
    end
  end

  describe 'registry.check and registry.remove' do
    before { save }

    it 'says whether the registry still takes the token, and records it' do
      expect(run('registry.check', 'place' => 'ghcr.io/catdogbark')).to eq('place' => 'ghcr.io/catdogbark', 'worked' => true)
      kept_token = kept
      kept_token['ghcr.io/catdogbark']['token'] = "ghp_#{'c' * 36}" # deleted on GitHub since
      File.write("#{dir}/etc/registry-tokens.json", JSON.generate('tokens' => kept_token))
      expect(run('registry.check', 'place' => 'ghcr.io/catdogbark')).to eq('place' => 'ghcr.io/catdogbark', 'worked' => false, 'error' => 'ghcr.io refused the token')
      expect(status.first).to include('worked' => false, 'error' => 'ghcr.io refused the token')
    end

    it 'takes the token off the NAS' do
      expect(run('registry.remove', 'place' => 'ghcr.io/catdogbark')).to include('removed' => true)
      expect(kept).to eq({})
      expect(status).to eq([])
      expect { run('registry.check', 'place' => 'ghcr.io/catdogbark') }.to raise_error(AmahiHelper::Refused, "there's no token for ghcr.io/catdogbark")
    end
  end

  describe 'lookups for the web app' do
    before { save }

    it "finds a tag's digest with a token for that image alone" do
      expect(run('registry.digest', 'repo' => 'ghcr.io/catdogbark/bitstream', 'tag' => '0.2.1')).to eq('digest' => digest)
      scoped = requests.select { |r| r[:key] == 'GET https://ghcr.io/token' }.last
      expect(scoped[:query]).to eq('service=ghcr.io&scope=repository%3Acatdogbark%2Fbitstream%3Apull')
      expect { run('registry.digest', 'repo' => 'ghcr.io/catdogbark/bitstream', 'tag' => '9.9') }.to raise_error(AmahiHelper::Failed, 'ghcr.io has no catdogbark/bitstream:9.9')
      expect(status.first['worked']).to be(true) # an image that isn't there says nothing about the token
    end

    it 'records a token the image refuses' do
      routes['HEAD https://ghcr.io/v2/catdogbark/bitstream/manifests/0.2.1'] = ->(_h) { [403, ''] }
      expect { run('registry.digest', 'repo' => 'ghcr.io/catdogbark/bitstream', 'tag' => '0.2.1') }
        .to raise_error(AmahiHelper::RegistryRefused, "ghcr.io refused the token for catdogbark/bitstream: it can't read that image")
      expect(status.first).to include('worked' => false)
    end

    it 'lists the tags, page by page on the same registry' do
      routes['GET https://ghcr.io/v2/catdogbark/bitstream/tags/list'] = lambda { |_h|
        if requests.last[:query].include?('last=')
          [200, '{"tags":["0.3.0","-bad"]}', { 'Link' => '<https://elsewhere.example/v2/x/tags/list?last=z>; rel="next"' }]
        else
          [200, '{"tags":["0.2.0","0.2.1"]}', { 'Link' => '</v2/catdogbark/bitstream/tags/list?last=0.2.1&n=1000>; rel="next"' }]
        end
      }
      expect(run('registry.tags', 'repo' => 'ghcr.io/catdogbark/bitstream')).to eq('tags' => %w[0.2.0 0.2.1 0.3.0])
      expect(requests.map { |r| r[:key] }).not_to include(a_string_including('elsewhere'))
    end

    it "refuses an image no token is for, so the web app can't spend a token on another place" do
      expect { run('registry.digest', 'repo' => 'ghcr.io/someone/thing', 'tag' => '1') }.to raise_error(AmahiHelper::Refused, "there's no token for ghcr.io/someone/thing")
      expect { run('registry.tags', 'repo' => 'ghcr.io/catdogbark/../x') }.to raise_error(AmahiHelper::Refused, /without its tag/)
    end
  end

  describe 'which token an image takes' do
    before do
      FileUtils.mkdir_p("#{dir}/etc")
      File.write("#{dir}/etc/registry-tokens.json", JSON.generate('tokens' => {
                                                                     'ghcr.io/catdogbark' => { 'username' => 'a', 'token' => token },
                                                                     'ghcr.io/catdogbark/private' => { 'username' => 'b', 'token' => token },
                                                                     'docker.io/jellyfin' => { 'username' => 'c', 'token' => token },
                                                                     'docker.io/library' => { 'username' => 'd', 'token' => token }
                                                                   }))
    end

    it 'is the longest place that holds it, with Docker Hub named as Docker names it' do
      expect(helper.registry_place_for('ghcr.io/catdogbark/bitstream')).to eq('ghcr.io/catdogbark')
      expect(helper.registry_place_for('ghcr.io/catdogbark/private/app')).to eq('ghcr.io/catdogbark/private')
      expect(helper.registry_place_for('ghcr.io/catdogbarkx/app')).to be_nil
      expect(helper.registry_place_for('jellyfin/jellyfin')).to eq('docker.io/jellyfin')
      expect(helper.registry_place_for('nginx')).to eq('docker.io/library')
      expect(helper.registry_place_for('lscr.io/linuxserver/transmission')).to be_nil
    end
  end

  describe 'a pull' do
    let(:image) { "ghcr.io/catdogbark/bitstream:0.2.1@#{digest}" }

    before { save }

    it 'gives Docker the sign-in in a folder of its own for that pull alone, and removes it after' do
      folder = nil
      allow(helper).to receive(:run_command) do |argv|
        folder = argv[argv.index('--config') + 1]
        expect(argv).to eq([AmahiHelper::DOCKER, '--config', folder, 'pull', image, { stream: true }])
        config = JSON.parse(File.read("#{folder}/config.json"))
        expect(config).to eq('auths' => { 'ghcr.io' => { 'auth' => ["CatDogBark:#{token}"].pack('m0') } })
        expect(File.stat(folder).mode & 0o777).to eq(0o700)
        expect(File.stat("#{folder}/config.json").mode & 0o777).to eq(0o600)
        nil
      end
      helper.engine_pull(image)
      expect(File).not_to exist(folder)
      expect(status.first['worked']).to be(true)
    end

    it 'pulls any other image without signing in' do
      allow(helper).to receive(:run_command)
      helper.engine_pull("jellyfin/jellyfin:12.1@#{digest}")
      expect(helper).to have_received(:run_command).with([AmahiHelper::DOCKER, 'pull', "jellyfin/jellyfin:12.1@#{digest}", { stream: true }])
    end

    it 'records a token Docker was refused with' do
      allow(helper).to receive(:run_command).and_raise(AmahiHelper::Failed, 'docker exited 1: unauthorized: authentication required')
      expect { helper.engine_pull(image) }.to raise_error(AmahiHelper::Failed, /unauthorized/)
      expect(status.first).to include('worked' => false, 'error' => 'ghcr.io refused the token when ghcr.io/catdogbark/bitstream was downloaded')
    end

    it 'names Docker Hub as Docker does in its config' do
      FileUtils.mkdir_p("#{dir}/etc")
      File.write("#{dir}/etc/registry-tokens.json", JSON.generate('tokens' => { 'docker.io/me' => { 'username' => 'me', 'token' => token } }))
      helper.registry_signed_in("me/app:1@#{digest}") do |folder|
        expect(JSON.parse(File.read("#{folder}/config.json"))['auths'].keys).to eq(['https://index.docker.io/v1/'])
      end
    end
  end

  it 'never logs a token' do
    expect(helper.filtered_value({ 'host' => 'ghcr.io', 'token' => token })).to eq('host' => 'ghcr.io', 'token' => '[FILTERED]')
  end

  it "won't sign in to the NAS itself" do
    allow(helper).to receive(:registry_answer).and_call_original
    expect { helper.registry_reachable!('localhost') }.to raise_error(AmahiHelper::Failed, /which Amahi-kai doesn't sign in to/)
  end
end
