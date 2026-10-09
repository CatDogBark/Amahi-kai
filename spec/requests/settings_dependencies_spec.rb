require 'rails_helper'

RSpec.describe 'Settings → System Dependencies', type: :request do
  let(:update) { ->(package, security) { SystemDependencies::Update.new(package: package, installed: '1.0', available: '1.1', security: security) } }

  let(:automatic) { false }

  before do
    allow(SystemDependencies).to receive(:status).and_return(
      dependencies: [SystemDependencies::Dependency.new(key: 'samba', name: 'Samba', role: 'Network shares (SMB)', source: 'Ubuntu',
                                                        version: '1.0', updates: [update.call('samba', true)], packages: ['samba'], held: []),
                     SystemDependencies::Dependency.new(key: 'greyhole', name: 'Greyhole', role: 'Storage pool', source: 'Greyhole',
                                                        version: '0.15.28-1', updates: [], packages: ['greyhole'], held: ['greyhole']),
                     SystemDependencies::Dependency.new(key: 'tailscale', name: 'Tailscale', role: 'Remote access (VPN)', source: 'Tailscale',
                                                        version: nil, updates: [], packages: [], held: [])],
      other: [update.call('apparmor', false), update.call('libssl3t64', true)], held: ['greyhole'], automatic: automatic,
      os: 'Ubuntu 24.04.3 LTS', kernel: '6.8.0-142-generic',
      restart: ['linux-image-6.8.0-143-generic'], runtime: { amahi_kai: 'abc1234', ruby: '3.2.3', rails: '8.1.4', gems: 120 },
      checked_at: 2.hours.ago
    )
  end

  it 'is for admins only' do
    login_as(create(:user))
    get '/settings/dependencies'
    expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
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

  describe 'updating' do
    before { login_as_admin }

    def page
      get '/settings/dependencies'
      Nokogiri::HTML(response.body)
    end

    it 'offers Update for software with an update, Hold or Release for what is installed, and Update all' do
      samba = page.at_css('#dependency-samba')
      update = samba.at_xpath(".//button[text()='Update']")
      expect(update['data-call']).to eq('openInstallTerminal')
      expect(JSON.parse(update['data-args'])).to eq(['deps-upgrade', '/settings/dependencies_upgrade_stream?packages%5B%5D=samba'])
      expect(update['data-confirm']).to start_with('Update Samba')
      expect(samba.at_xpath(".//form//button[text()='Hold']")).to be_present
      greyhole = page.at_css('#dependency-greyhole')
      expect(greyhole.text).to include('Held')
      expect(greyhole.at_xpath(".//form//button[text()='Release']")).to be_present
      expect(page.at_css('#dependency-tailscale form')).to be_nil
      expect(JSON.parse(page.at_css('#update-all')['data-args'])).to eq(['deps-upgrade', '/settings/dependencies_upgrade_stream?all=1'])
      expect(page.at_css('#other-updates').css('button').map(&:text)).to eq(%w[Update Update])
      expect(page.at_css('#deps-upgrade-install-modal')).to be_present
    end

    it 'says automatic updates are off, with Turn on' do
      expect(page.at_css('#automatic-updates').text.squish).to include('Automatic updates are off', '2 days')
      expect(page.at_css('#automatic-updates-switch').text).to eq('Turn on')
    end

    context 'with automatic updates on' do
      let(:automatic) { true }

      it 'says so, with Turn off' do
        expect(page.at_css('#dependencies-summary').text.squish).to include('Automatic updates are on')
        expect(page.at_css('#automatic-updates-switch').text).to eq('Turn off')
      end
    end

    it 'holds, releases and switches automatic updates through the helper' do
      post '/settings/dependencies_hold', params: { packages: ['samba'], held: '1' }
      expect(response).to redirect_to('/settings/dependencies')
      expect(flash[:notice]).to eq('Held at their versions: samba.')
      post '/settings/dependencies_hold', params: { packages: ['greyhole'], held: '0' }
      post '/settings/dependencies_automatic', params: { enabled: '0' }
      expect(flash[:notice]).to start_with('Automatic updates are off')
      expect(Privileged.calls).to eq([['packages.hold', { packages: ['samba'], held: true }],
                                      ['packages.hold', { packages: ['greyhole'], held: false }],
                                      ['updates.set_automatic', { enabled: false }]])
    end

    it 'shows what the helper refused' do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('updates.set_automatic', 'unattended-upgrades is not installed'))
      post '/settings/dependencies_automatic', params: { enabled: '1' }
      expect(flash[:error]).to include('unattended-upgrades is not installed')
    end

    it 'updates software, or everything, in a stream' do
      get '/settings/dependencies_upgrade_stream', params: { packages: ['samba'] }, headers: same_origin
      expect(response.body).to include('data: Updating samba...', 'data: ✓ Updated.', "event: done\ndata: success")
      get '/settings/dependencies_upgrade_stream', params: { all: '1' }, headers: same_origin
      expect(response.body).to include('data: Installing every update waiting')
      expect(Privileged.calls).to eq([['packages.upgrade', { packages: ['samba'] }], ['packages.upgrade_all', {}]])
    end

    it 'is for admins only' do
      login_as(create(:user))
      post '/settings/dependencies_automatic', params: { enabled: '1' }
      get '/settings/dependencies_upgrade_stream', params: { all: '1' }, headers: same_origin
      expect(Privileged.calls).to eq([])
    end
  end
end
