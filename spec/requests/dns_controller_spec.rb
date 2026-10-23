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

    it "shows Unbound's totals while it's on: lookups, how many the NAS answered, DNSSEC" do
      allow(DnsService).to receive_messages(installed?: true, running?: true, check: { local: 1, outside: 24 },
                                            totals: { 'since' => Time.now.to_i - (3 * 3600), 'queries' => 12_345, 'answered_here' => 7_900,
                                                      'secure' => 4_321, 'bogus' => 3 })
      Setting.set('dns_mode', 'dns')
      get '/network/dns'
      expect(response.body).to include('12,345 in about 3 hours', '64% answered on the NAS', 'without asking Quad9',
                                        '4,321 came signed by their domain, and the signature checked out', '3 failed the check, so the NAS refused them')
    end

    describe 'saving' do
      before { allow(DnsService).to receive(:installed?).and_return(true) }

      it 'turns DNS on with the provider and interface picked' do
        put '/network/dns', params: { mode: 'dns', provider: 'cloudflare', interface: 'ens18' }
        expect(response).to redirect_to('/network/dns')
        expect(flash[:notice]).to include('Unbound is answering')
        expect([Setting.get('dns_mode'), Setting.get('dns_provider'), Setting.get('dns_interface')]).to eq(%w[dns cloudflare ens18])
        expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable dns.blocking_off])
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
        [[{ mode: 'everything', provider: 'quad9', interface: 'ens18' }, 'Choose Off, DNS for my network, DNS + DHCP, or Router'],
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
          expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable dns.blocking_off network.write_dnsmasq_config services.enable])
          expect(Privileged.calls[3].last[:content]).to include('interface=ens18', 'dhcp-range=192.168.1.100,192.168.1.200,14400s')
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
          expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable dns.blocking_off network.write_dnsmasq_config services.disable])
          expect(Privileged.calls[3].last[:content]).not_to include('dhcp-range')
        end
      end

      it "says so when the settings couldn't be applied" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('dns.write_config', 'unbound-checkconf rejected the config'))
        put '/network/dns', params: { mode: 'dns', provider: 'quad9', interface: 'ens18' }
        expect(flash[:alert]).to include("couldn't be applied", 'unbound-checkconf rejected')
      end
    end

    describe 'blocking' do
      before { allow(DnsService).to receive(:installed?).and_return(true) }

      it 'shows how many domains it blocks, and offers a pause' do
        Setting.set('dns_mode', 'dns')
        Setting.set('dns_blocking', '1')
        allow(DnsService).to receive_messages(blocklists_refreshing?: false, blocking_status: {
          'blocked' => 327_002, 'refreshed_at' => Time.now.to_i - 3600,
          'lists' => { 'hagezi-normal' => { 'domains' => 171_250 }, 'hagezi-tif-mini' => { 'domains' => 211_791, 'error' => 'curl exited 22', 'downloaded_at' => 1 } }
        })
        get '/network/dns'
        expect(response.body).to include('Blocking <strong>327,002</strong> domains', 'Pause for 5 minutes', '171,250 domains',
                                          "HaGeZi Threat Intelligence (mini) couldn't be downloaded (curl exited 22), so its last copy is used")
      end

      it "says why the lists couldn't be updated, and looks again while they're updating" do
        Setting.set('dns_mode', 'dns')
        Setting.set('dns_blocking', '1')
        allow(DnsService).to receive_messages(blocklists_refreshing?: false,
                                              blocking_status: { 'blocked' => 10, 'error' => 'at most 1000000 fit', 'lists' => {} })
        get '/network/dns'
        expect(response.body).to include('Not updated', "The blocklist couldn't be updated: at most 1000000 fit.", 'The one before is still in use.')
        allow(DnsService).to receive(:blocklists_refreshing?).and_return(true)
        get '/network/dns'
        expect(response.body).to include('<meta http-equiv="refresh" content="5">', 'Downloading the lists')
      end

      it 'turns on with the lists and allowlist chosen, while DNS is on' do
        Setting.set('dns_mode', 'dns')
        put '/network/dns/blocking', params: { blocking: '1', lists: %w[hagezi-light oisd-small], allowlist: "Example.com\ncdn.example.net" }
        expect(flash[:notice]).to include('The lists are downloading')
        expect(Privileged.calls).to eq([['dns.set_blocklists', { lists: %w[hagezi-light oisd-small], allow: %w[example.com cdn.example.net] }]])
      end

      it 'saves for later while DNS is off' do
        put '/network/dns/blocking', params: { blocking: '1', lists: %w[hagezi-normal] }
        expect(flash[:notice]).to eq('Saved. Blocking starts when DNS is on.')
        expect(Setting.get('dns_blocking')).to eq('1')
        expect(Privileged.calls).to be_empty
      end

      it 'refuses an allowlist with something not a domain, or no list to block with' do
        put '/network/dns/blocking', params: { blocking: '1', lists: %w[hagezi-normal], allowlist: 'example.com 10.0.0.1' }
        expect(flash[:alert]).to include("10.0.0.1 isn't a domain")
        put '/network/dns/blocking', params: { blocking: '1', lists: %w[made-up] }
        expect(flash[:alert]).to include('Choose at least one list')
        expect(Setting.get('dns_blocking')).not_to eq('1')
      end

      it 'turns off, ending any pause' do
        Setting.set('dns_mode', 'dns')
        Setting.set('dns_blocking_paused_until', (Time.now.to_i + 100).to_s)
        put '/network/dns/blocking', params: { lists: %w[hagezi-normal] }
        expect(flash[:notice]).to eq('Blocking is off.')
        expect(Privileged.calls).to eq([['dns.blocking_off', {}]])
        expect(DnsService.paused_until).to be_nil
      end

      it 'pauses for five minutes, and resumes' do
        allow(Privileged).to receive(:call).with('dns.pause_blocking').and_return('ok' => true, 'until' => Time.now.to_i + 300)
        post '/network/dns/pause_blocking'
        expect(flash[:notice]).to eq('Blocking is paused for 5 minutes.')
        expect(DnsService.paused_until).to be_within(5).of(Time.now + 300)
        allow(Privileged).to receive(:call).with('dns.resume_blocking').and_return('ok' => true)
        post '/network/dns/resume_blocking'
        expect(flash[:notice]).to eq('Blocking is back on.')
        expect(DnsService.paused_until).to be_nil
      end
    end

    describe 'router mode' do
      let(:router) { { mode: 'router', provider: 'quad9', interface: 'ens18', wan_interface: 'ens19', dhcp_first: '100', dhcp_last: '200', dhcp_router: '1', lease_time: '14400' } }

      before do
        allow(DnsService).to receive_messages(installed?: true, firewall_on?: true, router_state: nil)
        allow(DnsmasqService).to receive(:installed?).and_return(true)
        allow(DnsmasqService).to receive(:other_servers).and_return([])
        allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [lan], 'ens19' => [NetworkInterfaces::Address.new(ip: IPAddr.new('10.77.0.5'), prefix: 24)])
      end

      it 'needs an internet interface, a different one, and the firewall on' do
        put '/network/dns', params: router.merge(wan_interface: '')
        expect(flash[:alert]).to include('Choose the interface the internet is on')
        put '/network/dns', params: router.merge(wan_interface: 'ens18')
        expect(flash[:alert]).to include('must differ')
        allow(DnsService).to receive(:firewall_on?).and_return(false)
        put '/network/dns', params: router
        expect(flash[:alert]).to include('Turn the firewall on first')
        expect(Privileged.calls).to be_empty
      end

      it "refuses to make the interface you're connected through the internet side" do
        put '/network/dns', params: router.merge(interface: 'ens19', wan_interface: 'ens18'), headers: { 'REMOTE_ADDR' => '192.168.1.74' }
        expect(flash[:alert]).to include("You're connected through ens18")
      end

      it 'saves, and puts the router in place after DNS and DHCP' do
        put '/network/dns', params: router
        expect(flash[:notice]).to include('The NAS is the router')
        expect([Setting.get('dns_mode'), Setting.get('dns_wan_interface')]).to eq(%w[router ens19])
        expect(Privileged.calls.map(&:first)).to eq(%w[dns.write_config services.enable dns.blocking_off network.write_dnsmasq_config services.enable network.router_on])
        expect(Privileged.calls.last.last).to eq(lan: 'ens18', wan: 'ens19', forwards: [])
        expect(Privileged.calls[3].last[:content]).to include('dhcp-option=option:router,192.168.1.10')
      end

      it 'shows the internet side, and takes the router down when the mode changes' do
        Setting.set('dns_mode', 'router')
        Setting.set('dns_wan_interface', 'ens19')
        allow(DnsService).to receive_messages(router_state: { 'lan' => 'ens18', 'wan' => 'ens19', 'forwards' => [] }, running?: true, check: nil)
        allow(NetworkInterfaces).to receive(:addresses).with('ens19').and_return([NetworkInterfaces::Address.new(ip: IPAddr.new('10.77.0.134'), prefix: 24)])
        allow(NetworkInterfaces).to receive(:default_route).and_return(%w[ens19 10.77.0.1])
        get '/network/dns'
        expect(response.body).to include('Through ens19 at 10.77.0.134', 'router 10.77.0.1', '0 ports let in', 'Ports let in from the internet')
        allow(NetworkInterfaces).to receive(:default_route).and_return(%w[ens18 192.168.1.1])
        get '/network/dns'
        expect(response.body).to include('still goes through', 'ens18 (via 192.168.1.1)', 'metric above 50')
        put '/network/dns', params: router.merge(mode: 'dns_dhcp')
        expect(Privileged.calls.map(&:first)).to include('network.router_off')
      end

      it 'adds and removes port forwards, rewriting the rules each time' do
        Setting.set('dns_mode', 'router')
        Setting.set('dns_wan_interface', 'ens19')
        post '/network/dns/forwards', params: { port_forward: { port: '8080', protocol: 'tcp', address: '60', to_port: '80', name: 'camera' } }
        expect(flash[:notice]).to eq('Forwarding tcp 8080 → 80 to 192.168.1.60.')
        expect(Privileged.calls.last).to eq(['network.router_on', { lan: 'ens18', wan: 'ens19', forwards: [{ protocol: 'tcp', port: 8080, address: '192.168.1.60', to_port: 80 }] }])
        post '/network/dns/forwards', params: { port_forward: { port: '8080', protocol: 'tcp', address: '61' } }
        expect(flash[:alert]).to include('forwarded already')
        delete "/network/dns/forwards/#{PortForward.last.id}"
        expect(flash[:notice]).to eq('No longer forwarding tcp 8080 → 80.')
        expect(Privileged.calls.last.last[:forwards]).to eq([])
      end
    end

    describe 'IPv6' do
      before do
        allow(DnsService).to receive(:installed?).and_return(true)
        Setting.set('dns_mode', 'dns')
      end

      it 'announces the NAS once radvd is installed' do
        allow(DnsService).to receive(:radvd_installed?).and_return(false)
        put '/network/dns', params: { mode: 'dns', provider: 'quad9', interface: 'ens18', ipv6_advertise: '1' }
        expect(flash[:alert]).to include('Install radvd first')
        allow(DnsService).to receive_messages(radvd_installed?: true, radvd_running?: false)
        put '/network/dns', params: { mode: 'dns', provider: 'quad9', interface: 'ens18', ipv6_advertise: '1' }
        expect(Setting.get('dns_ipv6_advertise')).to eq('1')
        expect(Privileged.calls.map(&:first)).to include('dns.set_own_address', 'dns.write_radvd_config')
      end

      it 'asks the routers, and warns when one tells devices about another DNS server' do
        allow(Privileged).to receive(:call).with('dns.check_routers', interface: 'ens18').and_return(
          'ok' => true, 'advertisers' => [{ 'router' => 'fe80::1', 'lifetime' => 1800, 'prefixes' => ['2600:1700:abcd::/64'],
                                            'dns' => ['2600:1700:abcd::1'], 'domains' => [] }]
        )
        post '/network/dns/check_routers'
        expect(response).to redirect_to('/network/dns#dns-ipv6')
        allow(DnsService).to receive(:check).and_return(nil)
        get '/network/dns'
        expect(response.body).to include('<code>fe80::1</code>', '(a router)', 'DNS 2600:1700:abcd::1',
                                          'tells devices to use <code>2600:1700:abcd::1</code> for DNS')
      end

      it "says so when no router answers" do
        allow(Privileged).to receive(:call).with('dns.check_routers', interface: 'ens18').and_return('ok' => true, 'advertisers' => [])
        post '/network/dns/check_routers'
        get '/network/dns'
        expect(response.body).to include('No router answered')
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
