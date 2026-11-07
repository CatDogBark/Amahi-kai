require 'rails_helper'

# Tokens for private images as the pages see them (RegistryTokens): the root helper's status file,
# never a token, and which token an image downloads with.
RSpec.describe RegistryTokens do
  let(:status_file) { Rails.root.join("tmp/registry-status-#{Process.pid}.json").to_s }

  before { allow(described_class).to receive(:status_file).and_return(status_file) }
  after { FileUtils.rm_f(status_file) }

  def keep(*places)
    File.write(status_file, JSON.generate('tokens' => places.map { |place| { 'place' => place, 'username' => 'me', 'worked' => true } }))
  end

  it "names an image as Docker does in full, and the place a token for it would have" do
    expect(described_class.full_name('ghcr.io/catdogbark/bitstream:0.2.1@sha256:' + ('a' * 64))).to eq('ghcr.io/catdogbark/bitstream')
    expect(described_class.full_name('jellyfin/jellyfin:12.1')).to eq('docker.io/jellyfin/jellyfin')
    expect(described_class.full_name('nginx:1')).to eq('docker.io/library/nginx')
    expect(described_class.full_name('index.docker.io/me/app:1')).to eq('docker.io/me/app')
    expect(described_class.place_for('ghcr.io/catdogbark/bitshare:0.3.0')).to eq('ghcr.io/catdogbark')
    expect(described_class.place_for('me/app:1')).to eq('docker.io/me')
  end

  it 'finds the token an image downloads with: the longest place that holds it' do
    keep('ghcr.io/catdogbark', 'ghcr.io/catdogbark/private', 'docker.io/me')
    expect(described_class.for_image('ghcr.io/catdogbark/bitstream:0.2.1').place).to eq('ghcr.io/catdogbark')
    expect(described_class.for_image('ghcr.io/catdogbark/private/app:1').place).to eq('ghcr.io/catdogbark/private')
    expect(described_class.for_image('ghcr.io/catdogbarkx/app:1')).to be_nil
    expect(described_class.for_image('me/app:1').place).to eq('docker.io/me')
    expect(described_class.for_repo('ghcr.io/catdogbark/bitstream')).to be_present
  end

  it 'reads nothing when there is no status, or it is broken' do
    expect(described_class.all).to eq([])
    File.write(status_file, '{"tokens": [{"no": "place"}, 7]')
    expect(described_class.all).to eq([])
    File.write(status_file, '{"tokens": [{"no": "place"}, 7, {"place": "ghcr.io/x", "worked": false, "error": "refused", "checked_at": "nope"}]}')
    expect(described_class.all).to contain_exactly(have_attributes(place: 'ghcr.io/x', refused?: true, checked_at: nil, registry_name: "GitHub's registry",
                                                                   owner: 'x'))
  end

  it 'lists the apps whose images are a token\'s' do
    keep('ghcr.io/catdogbark')
    apps = [DockerApp.new(identifier: 'bitstream', image: 'ghcr.io/catdogbark/bitstream:0.2.1'), DockerApp.new(identifier: 'jellyfin', image: 'jellyfin/jellyfin:12.1'),
            DockerApp.new(identifier: 'none', image: nil)]
    expect(described_class.apps_using(described_class.all.first, apps).map(&:identifier)).to eq(['bitstream'])
  end

  it 'asks the root helper to look up an image under a token, so the web app never holds it' do
    allow(Privileged).to receive(:call).with('registry.digest', repo: 'ghcr.io/catdogbark/x', tag: '1').and_return('digest' => 'sha256:abc')
    allow(Privileged).to receive(:call).with('registry.tags', repo: 'ghcr.io/catdogbark/x').and_return('tags' => %w[1 2])
    expect(described_class.digest('ghcr.io/catdogbark/x', '1')).to eq('sha256:abc')
    expect(described_class.tags('ghcr.io/catdogbark/x')).to eq(%w[1 2])
  end
end
