require 'spec_helper'

describe 'Network → DNS', type: :request do
  let(:lan) { NetworkInterfaces::Address.new(ip: IPAddr.new('192.168.1.10'), prefix: 24) }

  before do
    allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [lan], 'ens19' => [])
    allow(NetworkInterfaces).to receive(:default_name).and_return('ens18')
    allow(NetworkInterfaces).to receive(:addresses).and_return([])
    allow(NetworkInterfaces).to receive(:addresses).with('ens18').and_return([lan])
    allow(DnsService).to receive(:running?).and_return(false)
    allow(DnsmasqService).to receive(:rewrite_config!)
  end

  it 'is for admins only' do
    get '/network/dns'
    expect(response).to redirect_to(new_user_session_url)
    login_as(create(:user))
    get '/network/dns'
    expect(response).to redirect_to(root_url)
  end

  describe 'as an admin' do
    before { login_as_admin }

    it 'offers to install Unbound when it is not installed' do
      allow(DnsService).to receive(:installed?).and_return(false)
      get '/network/dns'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Install Unbound', 'Not installed', 'Quad9 (default)', 'ens18 (192.168.1.10)')
    end

    it 'shows how it is answering while it is on' do
      allow(DnsService).to receive_messages(installed?: true, running?: true, check: { local: 1, outside: 24 })
      Setting.set('dns_mode', 'dns')
      get '/network/dns'
      expect(response.body).to include('Answering', '192.168.1.10', 'Answered in 24 ms, encrypted, through Quad9')
    end

    describe 'saving' do
      before { allow(DnsService).to receive(:installed?).and_return(true) }

      it 'turns DNS on with the provider and interface picked' do
        put '/network/dns', params: { mode: 'dns', provider: 'cloudflare', interface: 'ens18' }
        expect(response).to redirect_to('/network/dns')
        expect(flash[:notice]).to include('Unbound is answering')
        expect([Setting.get('dns_mode'), Setting.get('dns_provider'), Setting.get('dns_interface')]).to eq(%w[dns cloudflare ens18])
        expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable])
        expect(Privileged.calls.first.last[:content]).to include('forward-addr: 1.1.1.1@853#one.one.one.one')
      end

      it 'saves a custom server, tidied' do
        put '/network/dns', params: { mode: 'dns', provider: 'custom', interface: 'ens18',
                                      custom_addresses: ' 192.168.1.53,  fd00::53 ', custom_tls_name: ' DNS.Example.org ' }
        expect(Setting.get('dns_custom_addresses')).to eq('192.168.1.53 fd00::53')
        expect(Setting.get('dns_custom_tls_name')).to eq('dns.example.org')
      end

      it 'turns DNS off' do
        Setting.set('dns_mode', 'dns')
        put '/network/dns', params: { mode: 'off', provider: 'quad9', interface: 'ens18' }
        expect(flash[:notice]).to eq('DNS is off.')
        expect(Privileged.calls.map(&:first)).to eq(%w[services.disable dns.remove_config])
      end

      it 'refuses what it cannot use, and changes nothing' do
        mode = Setting.get('dns_mode')
        [[{ mode: 'everything', provider: 'quad9', interface: 'ens18' }, 'Choose whether DNS is on'],
         [{ mode: 'dns', provider: 'google', interface: 'ens18' }, 'Choose a provider'],
         [{ mode: 'dns', provider: 'custom', interface: 'ens18', custom_addresses: '', custom_tls_name: 'x.y' }, 'one to four addresses'],
         [{ mode: 'dns', provider: 'quad9', interface: 'eth9' }, 'Choose the network interface'],
         [{ mode: 'dns', provider: 'quad9', interface: 'ens19' }, 'ens19 has no IPv4 address']].each do |params, reason|
          put '/network/dns', params: params
          expect(flash[:alert]).to include(reason), reason
        end
        expect(Setting.get('dns_mode')).to eq(mode)
        expect(Privileged.calls).to be_empty
      end

      it 'refuses to turn DNS on before Unbound is installed' do
        allow(DnsService).to receive(:installed?).and_return(false)
        put '/network/dns', params: { mode: 'dns', provider: 'quad9', interface: 'ens18' }
        expect(flash[:alert]).to include('Install Unbound first')
      end

      it "says so when the settings couldn't be applied" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('dns.write_config', 'unbound-checkconf rejected the config'))
        put '/network/dns', params: { mode: 'dns', provider: 'quad9', interface: 'ens18' }
        expect(flash[:alert]).to include("couldn't be applied", 'unbound-checkconf rejected')
      end
    end

    describe 'installing Unbound, in production' do
      before { allow(Rails.env).to receive(:production?).and_return(true) }

      it 'installs it with the DNSSEC root key and leaves it stopped while DNS is off' do
        get '/network/dns/install_stream', headers: same_origin
        expect(response.body).to include('Unbound installed')
        expect(Privileged.calls).to eq([['packages.install', { packages: %w[unbound dns-root-data] }],
                                        ['services.disable', { service: 'unbound' }]])
      end

      it "streams the helper's reason when the install fails" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.install', 'apt-get exited 100: E: oops'))
        get '/network/dns/install_stream', headers: same_origin
        expect(response.body).to include('apt-get exited 100', 'Installation failed')
      end
    end
  end
end
