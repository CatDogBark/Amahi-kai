require 'spec_helper'
require 'app_versions'

# script/app-versions' logic, with tags as Docker Hub lists them (2026-10-05) and no network.
RSpec.describe AppVersions do
  let(:dir) { Dir.mktmpdir }
  let(:digest) { "sha256:#{'a' * 64}" }
  let(:registry) do
    Class.new do
      attr_accessor :tags_by_repo, :digests

      def tags(repo) = tags_by_repo.fetch(repo)
      def digest(repo, tag) = digests.fetch("#{repo}:#{tag}")
    end.new
  end

  after { FileUtils.rm_rf(dir) }

  def manifest(id, image, releases: nil)
    File.write("#{dir}/#{id}.yml", "name: #{id}\n#{"releases: #{releases}\n" if releases}image: #{image}\nrun_as: app\n")
  end

  describe 'which tags count as releases' do
    it "keeps the pinned tag's shape, so nightlies, release candidates and other variants don't" do
      gitea = %w[28-nightly-rootless main-nightly-rootless latest-rootless 28.0-rootless 28-rootless 28.0.0-rootless
                 28.0.0 1.27-nightly-rootless 1.27.3-rootless 1.27.0-rc0-rootless 1.26.4-rootless]
      expect(described_class.newest('1.27.3-rootless', gitea)).to eq('28.0.0-rootless')
      kuma = %w[nightly-rootless 2.5.5 2.5.5-slim-rootless 2.5.6-slim-rootless 2.5.5-rootless 2-rootless 2.5.4-rootless]
      expect(described_class.newest('2.5.5-rootless', kuma)).to be_nil
      transmission = %w[4.1.3 version-4.1.3-r0 4.1.3-r0-ls363 4.1.3-r0-ls364 amd64-4.1.3-r0-ls364 4.1.2-r0-ls370]
      expect(described_class.newest('4.1.3-r0-ls363', transmission)).to eq('4.1.3-r0-ls364')
      jellyfin = %w[unstable 2026100512 latest 12 12.1 12.1.20260915-010956 12.0 12.0-rc7 12.2-rc1]
      expect(described_class.newest('12.1', jellyfin)).to be_nil
      expect(described_class.newest('12.0', jellyfin)).to eq('12.1')
    end

    # A new install stays on the catalog's major version (P4.9): a new one is offered as an update
    it 'keeps to the same major version when asked' do
      gitea = %w[1.27.3-rootless 1.27.5-rootless 28.0.0-rootless 28.3.0-rootless 1.26.9-rootless]
      expect(described_class.newest('1.27.3-rootless', gitea)).to eq('28.3.0-rootless')
      expect(described_class.newest('1.27.3-rootless', gitea, same_major: true)).to eq('1.27.5-rootless')
      expect(described_class.newest('1.27.5-rootless', gitea, same_major: true)).to be_nil
    end

    it "builds the release notes link from the tag's leading number" do
      expect(described_class.release_notes('https://github.com/go-gitea/gitea/releases/tag/v{version}', '28.0.0-rootless'))
        .to eq('https://github.com/go-gitea/gitea/releases/tag/v28.0.0')
      expect(described_class.release_notes(nil, '1.0')).to be_nil
    end
  end

  describe '#check' do
    let(:versions) { described_class.new(registry: registry, dir: dir) }

    before do
      registry.tags_by_repo = { 'gitea/gitea' => %w[1.27.3-rootless 28.0.0-rootless], 'jellyfin/jellyfin' => %w[12.1 12.0] }
      registry.digests = { 'gitea/gitea:28.0.0-rootless' => "sha256:#{'c' * 64}", 'jellyfin/jellyfin:12.1' => "sha256:#{'d' * 64}" }
    end

    it 'finds a newer release, says when the major version changes, and links its notes' do
      manifest('gitea', "gitea/gitea:1.27.3-rootless@#{digest}", releases: 'https://example.com/v{version}')
      expect(versions.check('gitea')).to have_attributes(kind: :newer, latest: '28.0.0-rootless', major: true,
                                                         image: "gitea/gitea:28.0.0-rootless@sha256:#{'c' * 64}",
                                                         notes: 'https://example.com/v28.0.0')
    end

    it 'finds a newer build of the same tag, or none' do
      manifest('jellyfin', "jellyfin/jellyfin:12.1@#{digest}")
      expect(versions.check('jellyfin')).to have_attributes(kind: :rebuilt, latest: '12.1', image: "jellyfin/jellyfin:12.1@sha256:#{'d' * 64}")
      manifest('jellyfin', "jellyfin/jellyfin:12.1@sha256:#{'d' * 64}")
      expect(versions.check('jellyfin').kind).to eq(:current)
    end

    it "reports what it couldn't check" do
      manifest('odd', 'odd/app:latest')
      expect(versions.check('odd').error).to include('name:tag@sha256:digest')
      manifest('gone', "gone/app:1.0@#{digest}")
      expect(versions.check('gone').error).to include('gone/app')
    end

    it 'writes only the image line when asked' do
      manifest('gitea', "gitea/gitea:1.27.3-rootless@#{digest}", releases: 'https://example.com/v{version}')
      described_class.write("#{dir}/gitea.yml", "gitea/gitea:28.0.0-rootless@sha256:#{'c' * 64}")
      expect(File.read("#{dir}/gitea.yml")).to eq("name: gitea\nreleases: https://example.com/v{version}\n" \
                                                   "image: gitea/gitea:28.0.0-rootless@sha256:#{'c' * 64}\nrun_as: app\n")
    end
  end

  it "asks each image's own registry: Docker Hub, GitHub's for ghcr.io, or any other by the registry API" do
    versions = described_class.new
    expect(versions.registry_for("ghcr.io/catdogbark/bittube")).to be_a(AppVersions::Ghcr)
    expect(versions.registry_for("gitea/gitea")).to be_a(AppVersions::DockerHub)
    expect(versions.registry_for("nginx")).to be_a(AppVersions::DockerHub)
    expect(versions.registry_for("docker.io/library/nginx")).to be_a(AppVersions::DockerHub)
    expect(versions.registry_for("lscr.io/linuxserver/transmission")).to be_a(AppVersions::Registry)
    expect(described_class.newest("0.1.0", %w[0.1.0 0.2.0 latest main sha-abc1234])).to eq("0.2.0")
  end

  # The owner's token for it goes through the root helper (RegistryTokens), never the web app
  it 'asks through the token an image is under, when there is one' do
    tokens = Module.new do
      def self.for_repo(repo) = repo.start_with?('ghcr.io/catdogbark/')
      def self.digest(_repo, tag) = "sha256:#{tag == '0.3.0' ? 'b' * 64 : 'a' * 64}"
      def self.tags(_repo) = %w[0.2.1 0.3.0]
    end
    versions = described_class.new(tokens: tokens)
    expect(versions.registry_for('ghcr.io/catdogbark/bitstream')).to be(tokens)
    expect(versions.registry_for('ghcr.io/someone/else')).to be_a(AppVersions::Ghcr)
    expect(versions.pin('ghcr.io/catdogbark/bitstream:0.2.1')).to eq("ghcr.io/catdogbark/bitstream:0.2.1@sha256:#{'a' * 64}")
    expect(versions.check_image("ghcr.io/catdogbark/bitstream:0.2.1@sha256:#{'a' * 64}")).to have_attributes(kind: :newer, latest: '0.3.0')
  end

  it "says where a token would go for a private image on GitHub's registry or Docker Hub" do
    ghcr = AppVersions::Ghcr.new
    allow(ghcr).to receive(:answer).and_return(Net::HTTPForbidden.new('1.1', '403', ''))
    expect { ghcr.digest('ghcr.io/catdogbark/bitshare', '1') }.to raise_error(AppVersions::Private, "ghcr.io says catdogbark/bitshare is private, or isn't there") { |e|
      expect(e.place).to eq('ghcr.io/catdogbark')
    }
    hub = AppVersions::DockerHub.new
    ok = Net::HTTPOK.new('1.1', '200', '')
    ok.instance_variable_set(:@body, '{"token":"t"}')
    ok.instance_variable_set(:@read, true)
    allow(hub).to receive(:answer) { |url, **| URI(url).host == 'auth.docker.io' ? ok : Net::HTTPUnauthorized.new('1.1', '401', '') }
    expect { hub.digest('me/app', '1') }.to raise_error(AppVersions::Private) { |e| expect(e.place).to eq('docker.io/me') }
  end

  it "knows the real catalog's apps and their release notes" do
    versions = described_class.new
    expect(versions.ids).to eq(%w[gitea jellyfin pigallery2 transmission uptimekuma vaultwarden])
    versions.ids.each do |id|
      notes = YAML.safe_load(File.read(versions.path(id)))['releases']
      expect(notes).to match(%r{\Ahttps://github\.com/.+\{version\}\z}), "#{id} has no releases link"
    end
  end

  # An app of your own's image (CustomAppsController): pinned to the build its tag names now, and
  # checked for a newer one only when asked.
  describe 'pinning' do
    let(:versions) { described_class.new(registry: registry) }

    before { registry.digests = { 'mealie-recipes/mealie:v2.4.1' => digest } }

    it "pins name:tag to the build it names now, and keeps one pinned already" do
      expect(versions.pin('mealie-recipes/mealie:v2.4.1')).to eq("mealie-recipes/mealie:v2.4.1@#{digest}")
      expect(versions.pin("mealie-recipes/mealie:v2.4.0@sha256:#{'e' * 64}")).to eq("mealie-recipes/mealie:v2.4.0@sha256:#{'e' * 64}")
      expect { versions.pin('mealie-recipes/mealie') }.to raise_error(ArgumentError, /isn't name:tag/)
      expect { versions.pin('Mealie:1') }.to raise_error(ArgumentError)
      expect { versions.pin('registry.local:5000/x:1') }.to raise_error(ArgumentError)
    end

    it 'finds a newer release of an image, or a newer build of its tag' do
      registry.tags_by_repo = { 'mealie-recipes/mealie' => %w[v2.4.1 v2.5.0 nightly] }
      registry.digests['mealie-recipes/mealie:v2.5.0'] = "sha256:#{'c' * 64}"
      expect(versions.check_image("mealie-recipes/mealie:v2.4.1@#{digest}")).to have_attributes(kind: :newer, latest: 'v2.5.0', major: false)
      registry.tags_by_repo = { 'mealie-recipes/mealie' => %w[v2.4.1 nightly] }
      expect(versions.check_image("mealie-recipes/mealie:v2.4.1@#{digest}").kind).to eq(:current)
      expect(versions.check_image("mealie-recipes/mealie:v2.4.1@sha256:#{'e' * 64}")).to have_attributes(kind: :rebuilt, image: "mealie-recipes/mealie:v2.4.1@#{digest}")
    end
  end

  # Any other registry: the registry API with the anonymous token it asks for, never pointed at
  # the NAS itself or a link-local address.
  describe AppVersions::Registry do
    let(:registry) { described_class.new('quay.io') }
    let(:asked) { [] }

    def answer(kind, body: '', headers: {})
      response = kind.new('1.1', { Net::HTTPUnauthorized => '401', Net::HTTPForbidden => '403', Net::HTTPNotFound => '404' }.fetch(kind, '200'), '')
      headers.each { |key, value| response[key] = value }
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
      response
    end

    before do
      allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp('203.0.113.7', 443)])
    end

    def answers(map)
      allow(registry).to receive(:answer) do |url, method: :get, headers: {}|
        asked << [url, method, headers['Authorization']]
        map.call(url, headers)
      end
    end

    let(:challenge) { 'Bearer realm="https://quay.io/v2/auth",service="quay.io",scope="repository:prometheus/node-exporter:pull"' }

    it "asks once without a token, then with the one the registry's challenge names" do
      answers(lambda do |url, headers|
        if url.start_with?('https://quay.io/v2/auth') then answer(Net::HTTPOK, body: '{"token":"t0k"}')
        elsif headers['Authorization'] == 'Bearer t0k' then answer(Net::HTTPOK, headers: { 'Docker-Content-Digest' => digest })
        else answer(Net::HTTPUnauthorized, headers: { 'WWW-Authenticate' => challenge })
        end
      end)
      expect(registry.digest('quay.io/prometheus/node-exporter', 'v1.8.2')).to eq(digest)
      expect(asked.map(&:first)).to eq(['https://quay.io/v2/prometheus/node-exporter/manifests/v1.8.2',
                                        'https://quay.io/v2/auth?service=quay.io&scope=repository%3Aprometheus%2Fnode-exporter%3Apull',
                                        'https://quay.io/v2/prometheus/node-exporter/manifests/v1.8.2'])
    end

    it "reads every page of tags, on this registry only" do
      answers(lambda do |url, _headers|
        if url.include?('last=b')
          answer(Net::HTTPOK, body: '{"tags":["c"]}', headers: { 'Link' => '<https://elsewhere.example/v2/x/tags/list?last=c>; rel="next"' })
        else
          answer(Net::HTTPOK, body: '{"tags":["a","b"]}', headers: { 'Link' => '</v2/x/tags/list?n=1000&last=b>; rel="next"' })
        end
      end)
      expect(registry.tags('quay.io/x')).to eq(%w[a b c])
      expect(asked.size).to eq(2)
    end

    it "says when the image is private, or isn't there" do
      answers(lambda do |url, _headers|
        url.start_with?('https://quay.io/v2/auth') ? answer(Net::HTTPOK, body: '{"token":"t0k"}') : answer(Net::HTTPUnauthorized, headers: { 'WWW-Authenticate' => challenge })
      end)
      expect { registry.digest('quay.io/nosuch/thing', '1') }.to raise_error(AppVersions::Private, "quay.io says nosuch/thing is private, or isn't there") { |e|
        expect(e.place).to eq('quay.io/nosuch')
      }
      answers(->(_url, _headers) { answer(Net::HTTPNotFound) })
      expect { registry.digest('quay.io/prometheus/node-exporter', 'v0') }.to raise_error('quay.io has no prometheus/node-exporter, or not that tag')
    end

    it "won't send for a token anywhere but https, nor ask the NAS itself or a link-local address" do
      answers(->(_url, _headers) { answer(Net::HTTPUnauthorized, headers: { 'WWW-Authenticate' => 'Bearer realm="http://quay.io/auth"' }) })
      expect { registry.digest('quay.io/x', '1') }.to raise_error("quay.io asks for a sign-in Amahi-kai can't give")
      [['127.0.0.1', 'is 127.0.0.1'], ['169.254.169.254', 'is 169.254.169.254'], ['::1', 'is ::1']].each do |address, words|
        allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp(address, 443)])
        expect { described_class.new('evil.example').digest('evil.example/x', '1') }.to raise_error(RuntimeError, /#{Regexp.escape(words)}/)
      end
    end
  end
end
