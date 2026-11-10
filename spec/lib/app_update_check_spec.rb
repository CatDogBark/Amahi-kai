require 'rails_helper'

# The update check (docs/plans/apps.md, P4.9): each installed app's image asked for a newer
# version, its answer kept on the app's record. A registry stands in, with no network.
RSpec.describe AppUpdateCheck do
  let(:registry) do
    Class.new do
      attr_accessor :tags_by_repo, :digests, :failure

      def tags(repo)
        raise failure if failure

        tags_by_repo.fetch(repo)
      end

      def digest(repo, tag) = digests.fetch("#{repo}:#{tag}")
    end.new
  end
  let(:versions) { AppVersions.new(registry: registry) }
  let(:jellyfin_image) { AppCatalog.find('jellyfin')[:image] }
  let(:jellyfin_digest) { jellyfin_image[/sha256:\h{64}/] }
  let!(:jellyfin) { DockerApp.create!(identifier: 'jellyfin', name: 'Jellyfin', image: jellyfin_image, status: 'running') }

  before do
    registry.tags_by_repo = { 'jellyfin/jellyfin' => %w[12.1 12.4 12.4.1 latest 13.0-rc1] }
    registry.digests = { 'jellyfin/jellyfin:12.4' => "sha256:#{'4' * 64}", 'jellyfin/jellyfin:12.1' => jellyfin_digest }
  end

  it "keeps a newer release of the app's tag, with its notes, and that it isn't a new major version" do
    found = described_class.check(jellyfin, versions: versions)
    expect(found).to have_attributes(kind: :newer, latest: '12.4')
    expect(jellyfin.reload).to have_attributes(newer_tag: '12.4', newer_image: "jellyfin/jellyfin:12.4@sha256:#{'4' * 64}", newer_kind: 'newer',
                                               newer_major: false, versions_error: nil)
    expect(jellyfin.newer_notes).to eq('https://github.com/jellyfin/jellyfin/releases/tag/v12.4')
    expect(jellyfin.versions_checked_at).to be_within(5.seconds).of(Time.current)
    expect(jellyfin.newer_found).to include(tag: '12.4', kind: 'newer', major: false)
    expect(jellyfin).to be_update_available
  end

  it 'says a new major version is one, and a newer build of the same tag is one too' do
    registry.tags_by_repo = { 'jellyfin/jellyfin' => %w[12.1 13.0] }
    registry.digests['jellyfin/jellyfin:13.0'] = "sha256:#{'3' * 64}"
    described_class.check(jellyfin, versions: versions)
    expect(jellyfin.reload.newer_found).to include(tag: '13.0', major: true)

    registry.tags_by_repo = { 'jellyfin/jellyfin' => %w[12.1] }
    registry.digests['jellyfin/jellyfin:12.1'] = "sha256:#{'5' * 64}"
    described_class.check(jellyfin, versions: versions)
    expect(jellyfin.reload.newer_found).to include(tag: '12.1', kind: 'rebuilt', image: "jellyfin/jellyfin:12.1@sha256:#{'5' * 64}")
  end

  it "forgets what it found once the app runs it, or when there's nothing newer" do
    described_class.check(jellyfin, versions: versions)
    jellyfin.update!(image: jellyfin.reload.newer_image)
    expect(jellyfin.newer_found).to be_nil
    expect(jellyfin).not_to be_update_available

    registry.tags_by_repo = { 'jellyfin/jellyfin' => %w[12.4] }
    described_class.check(jellyfin, versions: versions)
    expect(jellyfin.reload).to have_attributes(newer_tag: nil, newer_image: nil, newer_kind: nil)
  end

  it "keeps what it found before, with why, when the registry can't be asked" do
    described_class.check(jellyfin, versions: versions)
    registry.failure = RuntimeError.new('registry-1.docker.io answered 503')
    expect(described_class.check(jellyfin, versions: versions)).to be_nil
    expect(jellyfin.reload).to have_attributes(newer_tag: '12.4', versions_error: 'registry-1.docker.io answered 503')

    registry.failure = AppVersions::Private.new('ghcr.io/someone', "ghcr.io says someone/app is private, or isn't there")
    described_class.check(jellyfin, versions: versions)
    expect(jellyfin.reload.versions_error).to eq("ghcr.io says someone/app is private, or isn't there. " \
                                                 "If it's private, add a token for ghcr.io/someone on Private images (under Apps).")
  end

  it 'checks every installed app at once, and Check now waits only a while for them' do
    gitea = DockerApp.create!(identifier: 'gitea', name: 'Gitea', image: AppCatalog.find('gitea')[:image], status: 'stopped')
    DockerApp.create!(identifier: 'other', name: 'Other', image: 'x/y:1@sha256:' + ('0' * 64), status: 'installing')
    expect(described_class.installed.map(&:identifier)).to contain_exactly('jellyfin', 'gitea')

    checked = Queue.new
    allow(described_class).to receive(:check) { |app| checked << app.identifier }
    expect(described_class.run([jellyfin, gitea])).to eq(0)
    expect([checked.pop, checked.pop]).to contain_exactly('jellyfin', 'gitea')

    allow(described_class).to receive(:check) { sleep 0.5 }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(described_class.run([jellyfin], wait: 0.05)).to eq(1) # still asking, kept when it answers
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.4
  end
end
