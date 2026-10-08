require 'rails_helper'

RSpec.describe 'Settings → System Dependencies', type: :request do
  let(:update) { ->(package, security) { SystemDependencies::Update.new(package: package, installed: '1.0', available: '1.1', security: security) } }

  before do
    allow(SystemDependencies).to receive(:status).and_return(
      dependencies: [SystemDependencies::Dependency.new(key: 'samba', name: 'Samba', role: 'Network shares (SMB)', source: 'Ubuntu',
                                                        version: '1.0', updates: [update.call('samba', true)]),
                     SystemDependencies::Dependency.new(key: 'greyhole', name: 'Greyhole', role: 'Storage pool', source: 'Greyhole',
                                                        version: '0.15.28-1', updates: []),
                     SystemDependencies::Dependency.new(key: 'tailscale', name: 'Tailscale', role: 'Remote access (VPN)', source: 'Tailscale',
                                                        version: nil, updates: [])],
      other: [update.call('apparmor', false), update.call('libssl3t64', true)], os: 'Ubuntu 24.04.3 LTS', kernel: '6.8.0-142-generic',
      restart: ['linux-image-6.8.0-143-generic'], runtime: { amahi_kai: 'abc1234', ruby: '3.2.3', rails: '8.1.4', gems: 120 },
      checked_at: 2.hours.ago
    )
  end

  it 'is for admins only' do
    login_as(create(:user))
    get '/settings/dependencies'
    expect(response).to redirect_to(new_user_session_url)
  end

  it "lists the software, its versions and the updates waiting, security ones marked, with Check now" do
    login_as_admin
    Setting.set('advanced', '1') # its tab sits with the other advanced ones
    get '/settings/dependencies'
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('#dependencies-summary').text.squish).to include('3 updates waiting', '2 security updates', 'Nothing updates by itself')
    expect(page.at_css('#dependency-samba').text).to include('Samba', '1.0', '1.1', 'Security', 'Ubuntu')
    expect(page.at_css('#dependency-greyhole').text).to include('0.15.28-1', 'Up to date')
    expect(page.at_css('#dependency-tailscale').text).to include('Not installed')
    expect(page.at_css('#operating-system').text).to include('Ubuntu 24.04.3 LTS', '6.8.0-142-generic', 'linux-image-6.8.0-143-generic')
    expect(page.at_css('#other-updates').text).to include('apparmor', 'libssl3t64')
    expect(page.at_css('#runtime').text).to include('abc1234', 'Rails 8.1.4')
    expect(page.at_css('#deps-refresh-install-modal')['data-stream-url']).to eq('/settings/dependencies_refresh_stream')
    expect(page.css('.setup-subtab a').map(&:text).map(&:squish)).to include('System Dependencies')
  end

  it 'refreshes the package lists in a stream' do
    login_as_admin
    get '/settings/dependencies_refresh_stream', headers: same_origin
    expect(response.body).to include('data: Refreshing the package lists...', 'data: ✓ Package lists refreshed', "event: done\ndata: success")
    expect(Privileged.calls).to eq([['packages.refresh', {}]])
  end
end
