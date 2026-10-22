require 'spec_helper'

describe 'Network → DNS & DHCP', type: :request do
  let(:lan) { NetworkInterfaces::Address.new(ip: IPAddr.new('192.168.1.10'), prefix: 24) }

  before do
    allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [lan], 'ens19' => [])
    allow(NetworkInterfaces).to receive(:default_name).and_return('ens18')
    allow(NetworkInterfaces).to receive(:addresses).and_return([])
    allow(NetworkInterfaces).to receive(:addresses).with('ens18').and_return([lan])
    allow(DnsService).to receive(:running?).and_return(false)
    allow(DnsmasqService).to receive_messages(installed?: false, running?: false)
  end

  it 'is for admins only' do
    get '/network/dns'
    expect(response).to redirect_to(new_user_session_url)
    login_as(create(:user))
    get '/network/dns'
    expect(response).to redirect_to(root_url)
  end

  describe 'as an admin' do
    before do
      login_as_admin
      Setting.set('advanced', '1')
    end

    it 'is in advanced mode only, like the rest of Network' do
      Setting.set('advanced', '0')
      get '/network/dns'
      expect(response).to redirect_to('/network')
    end

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
        expect(flash[:notice]).to eq('DNS and DHCP are off.')
        expect(Privileged.calls.map(&:first)).to eq(%w[services.disable dns.remove_config])
      end

      it 'refuses what it cannot use, and changes nothing' do
        mode = Setting.get('dns_mode')
        [[{ mode: 'everything', provider: 'quad9', interface: 'ens18' }, 'Choose Off, DNS for my network, or DNS + DHCP'],
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

      describe 'with DHCP' do
        let(:dhcp) { { mode: 'dns_dhcp', provider: 'quad9', interface: 'ens18', dhcp_first: '100', dhcp_last: '200', dhcp_router: '1', lease_time: '14400' } }

        before do
          allow(DnsmasqService).to receive(:installed?).and_return(true)
          allow(DnsmasqService).to receive(:other_servers).with('ens18').and_return([])
        end

        it 'checks for another DHCP server, saves the range, and starts dnsmasq' do
          put '/network/dns', params: dhcp
          expect(flash[:notice]).to include('handing out addresses')
          expect(DnsmasqService.settings).to eq(first: 100, last: 200, router: 1, lease_time: 14_400)
          expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable network.write_dnsmasq_config services.enable])
          expect(Privileged.calls[2].last[:content]).to include('interface=ens18', 'dhcp-range=192.168.1.100,192.168.1.200,14400s')
        end

        it 'refuses while another DHCP server answers, and says where' do
          allow(DnsmasqService).to receive(:other_servers).with('ens18').and_return(['192.168.1.1'])
          put '/network/dns', params: dhcp
          expect(flash[:alert]).to include('Another DHCP server answers on ens18 (192.168.1.1)', 'Turn it off first')
          expect(Privileged.calls).to be_empty
        end

        it "refuses when it can't check" do
          allow(DnsmasqService).to receive(:other_servers).and_raise(Privileged::Error.new('dhcp.check_servers', 'Address already in use'))
          put '/network/dns', params: dhcp
          expect(flash[:alert]).to include("Couldn't check for another DHCP server", 'Address already in use')
        end

        it "refuses settings that don't fit, before asking the network" do
          put '/network/dns', params: dhcp.merge(dhcp_first: '5', dhcp_last: '20')
          expect(flash[:alert]).to include("takes in the NAS's own address (.10)")
          expect(DnsmasqService).not_to have_received(:other_servers)
        end

        it 'needs dnsmasq, and a /24 network' do
          allow(DnsmasqService).to receive(:installed?).and_return(false)
          put '/network/dns', params: dhcp
          expect(flash[:alert]).to include('Install dnsmasq first')
          allow(DnsmasqService).to receive(:installed?).and_return(true)
          allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [NetworkInterfaces::Address.new(ip: IPAddr.new('10.1.2.3'), prefix: 16)])
          put '/network/dns', params: dhcp
          expect(flash[:alert]).to include("DHCP needs ens18's network to be a /24")
        end

        it 'stops dnsmasq when DNS + DHCP is left' do
          Setting.set('dns_mode', 'dns_dhcp')
          put '/network/dns', params: dhcp.merge(mode: 'dns')
          expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable network.write_dnsmasq_config services.disable])
          expect(Privileged.calls[2].last[:content]).not_to include('dhcp-range')
        end
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

      it "installs dnsmasq after writing its config, answering no DNS, and leaves it stopped outside DNS + DHCP" do
        get '/network/dns/install_dnsmasq_stream', headers: same_origin
        expect(response.body).to include('dnsmasq installed')
        expect(Privileged.calls.map(&:first)).to eq(%w[network.write_dnsmasq_config packages.install services.disable])
        expect(Privileged.calls.first.last[:content]).to include('port=0')
        expect(Privileged.calls[1]).to eq(['packages.install', { packages: ['dnsmasq'] }])
      end

      it "streams the helper's reason when the install fails" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.install', 'apt-get exited 100: E: oops'))
        get '/network/dns/install_stream', headers: same_origin
        expect(response.body).to include('apt-get exited 100', 'Installation failed')
      end
    end
  end
end
