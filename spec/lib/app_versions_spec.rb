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

  it "asks each image's own registry: Docker Hub, or GitHub's for ghcr.io" do
    versions = described_class.new
    expect(versions.registry_for("ghcr.io/catdogbark/bittube")).to be_a(AppVersions::Ghcr)
    expect(versions.registry_for("gitea/gitea")).to be_a(AppVersions::DockerHub)
    expect(described_class.newest("0.1.0", %w[0.1.0 0.2.0 latest main sha-abc1234])).to eq("0.2.0")
  end

  it "knows the real catalog's apps and their release notes" do
    versions = described_class.new
    expect(versions.ids).to eq(%w[bittube gitea jellyfin transmission uptimekuma vaultwarden])
    versions.ids.each do |id|
      notes = YAML.safe_load(File.read(versions.path(id)))['releases']
      expect(notes).to match(%r{\Ahttps://github\.com/.+\{version\}\z}), "#{id} has no releases link"
    end
  end
end
