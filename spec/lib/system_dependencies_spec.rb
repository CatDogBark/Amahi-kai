require 'rails_helper'

# Settings → System Dependencies: what Amahi-kai depends on, its versions and the updates waiting.
RSpec.describe SystemDependencies do
  def status(success = true)
    instance_double(Process::Status, success?: success)
  end

  let(:upgradable) do
    <<~APT
      Listing...
      samba/noble-updates,noble-security 2:4.19.5+dfsg-4ubuntu9.3 amd64 [upgradable from: 2:4.19.5+dfsg-4ubuntu9.2]
      cloudflared/unknown 2026.10.0 amd64 [upgradable from: 2026.2.0]
      apparmor/noble-updates 4.0.1really4.0.1-0ubuntu0.24.04.8 amd64 [upgradable from: 4.0.1really4.0.1-0ubuntu0.24.04.5]
      libssl3t64/noble-security 3.0.13-0ubuntu3.7 amd64 [upgradable from: 3.0.13-0ubuntu3.6]
    APT
  end

  it "reads apt's updates, marking the ones from a security pocket" do
    updates = described_class.parse_upgradable(upgradable)
    expect(updates.map { |u| [u.package, u.installed, u.available, u.security] }).to eq(
      [['samba', '2:4.19.5+dfsg-4ubuntu9.2', '2:4.19.5+dfsg-4ubuntu9.3', true], ['cloudflared', '2026.2.0', '2026.10.0', false],
       ['apparmor', '4.0.1really4.0.1-0ubuntu0.24.04.5', '4.0.1really4.0.1-0ubuntu0.24.04.8', false],
       ['libssl3t64', '3.0.13-0ubuntu3.6', '3.0.13-0ubuntu3.7', true]]
    )
  end

  it "puts each update with the software it belongs to, and the rest under other updates" do
    allow(Open3).to receive(:capture3).and_call_original
    allow(Open3).to receive(:capture3).with({ 'LANG' => 'C' }, 'apt', 'list', '--upgradable').and_return([upgradable, '', status])
    allow(Open3).to receive(:capture3).with('dpkg-query', '-W', any_args)
                                      .and_return(["samba\t2:4.19.5+dfsg-4ubuntu9.2\tii \ncloudflared\t2026.2.0\tii \n" \
                                                   "greyhole\t0.15.28-1\tii \ntailscale\t\tun \n", '', status(false)])
    result = described_class.status
    deps = result[:dependencies].index_by(&:key)
    expect(deps['samba']).to have_attributes(version: '2:4.19.5+dfsg-4ubuntu9.2', security?: true)
    expect(deps['cloudflared'].updates.map(&:available)).to eq(['2026.10.0'])
    expect(deps['greyhole']).to have_attributes(installed?: true, updates: [])
    expect(deps['tailscale']).not_to be_installed
    expect(result[:other].map(&:package)).to eq(%w[apparmor libssl3t64])
    expect(result[:runtime]).to include(ruby: RUBY_VERSION, rails: Rails.version)
  end

  it 'lists nothing when apt fails, and refreshes the lists through the helper' do
    allow(Open3).to receive(:capture3).with({ 'LANG' => 'C' }, 'apt', 'list', '--upgradable').and_return(['', 'boom', status(false)])
    expect(described_class.upgradable).to eq([])
    described_class.refresh!
    expect(Privileged.calls).to eq([['packages.refresh', {}]])
  end
end
