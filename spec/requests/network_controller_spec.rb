require 'spec_helper'

describe "Network Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/network"
      expect(response).to redirect_to(new_user_session_url)
    end

    it "lets the moving page's probe in without a sign-in: it only keeps a change already waiting" do
      allow(NetworkAddress).to receive_messages(state: { 'state' => 'pending', 'interface' => 'ens18', 'since' => Time.now.to_i, 'until' => Time.now.to_i + 80 },
                                                arrival_interface: 'ens18', settle!: nil)
      post "/network/address/reached"
      expect(response).to have_http_status(:no_content)
      expect(Privileged.calls).to eq([['network.keep_address', {}]])
      get "/network/address", headers: { 'Accept' => 'application/json' }
      expect(response).to redirect_to(new_user_session_url) # where it stands is the admin's to ask
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/network"
      expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
    end
  end

  describe "admin" do
    before do
      login_as_admin
      allow(DnsService).to receive(:lan_prefix).and_return('192.168.1') # not the test machine's own network
    end

    describe "GET /network (devices)" do
      it "shows the devices seen and the fixed addresses, with the old Hosts page sent here" do
        allow(DnsmasqService).to receive(:rewrite_config!)
        allow(DnsService).to receive(:rewrite!)
        allow(NetworkAddress).to receive_messages(interfaces: [], nameservers: [], state: nil)
        Host.create!(name: "printer", mac: "aa:bb:cc:dd:ee:01", address: "20")
        allow(Leases).to receive(:all).and_return([{ expiration: Time.now.to_i + 3600, mac: "aa:bb:cc:dd:ee:01", ip: "192.168.1.20", name: "printer" },
                                                   { expiration: Time.now.to_i + 600, mac: "aa:bb:cc:dd:ee:02", ip: "192.168.1.150", name: "laptop" }])
        get "/network"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("2 devices seen", "Fixed at <code>192.168.1.20</code>", "laptop", "Fix this address", "Unfix")
        get "/network/hosts"
        expect(response).to redirect_to("/network")
      end
    end

    describe "POST /network/hosts" do
      before do
        allow(DnsmasqService).to receive(:rewrite_config!)
        allow(DnsService).to receive(:rewrite!)
      end

      it "gives a device a fixed address" do
        expect { post "/network/hosts", params: { host: { name: "myhost", mac: "aa:bb:cc:dd:ee:ff", address: "50" } } }.to change(Host, :count).by(1)
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("myhost keeps 192.168.1.50.")
      end

      it "says why it refused one" do
        expect { post "/network/hosts", params: { host: { name: "my_host", mac: "aa:bb", address: "50" } } }.not_to change(Host, :count)
        expect(flash[:alert]).to include("Mac")
      end

      it "takes a fixed address away" do
        host = Host.create!(name: "testhost", mac: "aa:bb:cc:dd:ee:01", address: "51")
        expect { delete "/network/host/#{host.id}" }.to change(Host, :count).by(-1)
        expect(flash[:notice]).to eq("testhost no longer has a fixed address.")
      end

      it "keeps a fixed device off the internet and lets it out again, rewriting the router's rules while the NAS is the router" do
        host = Host.create!(name: "camera", mac: "aa:bb:cc:dd:ee:02", address: "52")
        allow(NetworkAddress).to receive_messages(interfaces: [], nameservers: [], state: nil)
        allow(NetworkPorts).to receive(:all).and_return({})
        post "/network/host/#{host.id}/lan_only"
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("camera can't reach the internet once the NAS is the router; the LAN still works for it.")
        expect(host.reload.lan_only).to be true
        expect(Privileged.calls.map(&:first)).not_to include('network.router_on') # not the router yet: the flag waits
        get "/network"
        expect(response.body).to include("LAN only</span>", ">Internet again</button>")

        allow(DnsService).to receive_messages(router?: true, on?: true, wan_interface: 'ens20', interface: 'ens18', lan_prefix: '192.168.1')
        Privileged.reset!
        post "/network/host/#{host.id}/lan_only"
        expect(flash[:notice]).to eq("camera reaches the internet again.")
        expect(host.reload.lan_only).to be false
        router_on = Privileged.calls.find { |op, _args| op == 'network.router_on' }
        expect(router_on).not_to be_nil
        expect(router_on.last[:lan_only]).to eq([])
        post "/network/host/#{host.id}/lan_only"
        expect(Privileged.calls.last[1][:lan_only]).to eq(['192.168.1.52'])
      end
    end

    describe "This NAS (its own address on each port)" do
      let(:address) { NetworkInterfaces::Address }
      let(:rows) do
        [NetworkAddress::Interface.new(name: 'ens18', addresses: [address.new(ip: IPAddr.new('192.168.1.13'), prefix: 24)], automatic: true, gateway: '192.168.1.1', part: :lan),
         NetworkAddress::Interface.new(name: 'ens20', addresses: [], automatic: false, gateway: '10.77.0.1', part: :internet)]
      end

      let(:ports) do
        { 'ens18' => NetworkPorts::Port.new(name: 'ens18', label: nil, driver: 'igb', model: 'Intel I350 Gigabit Network Connection', virtual: false,
                                            link: true, speed: 1000, mac: 'a0:36:9f:12:34:56'),
          'ens20' => NetworkPorts::Port.new(name: 'ens20', label: 'Modem', driver: 'virtio_net', model: nil, virtual: true, link: true, speed: nil, mac: 'bc:24:11:4c:4a:46') }
      end

      before do
        allow(NetworkAddress).to receive_messages(interfaces: rows, nameservers: ['192.168.1.1'], state: nil, settle!: nil)
        allow(NetworkPorts).to receive(:all).and_return(ports)
        allow(NetworkPorts).to receive(:blinkable?) { |port| !port.virtual }
        allow(NetworkInterfaces).to receive(:lan).and_return('ens18' => [], 'ens20' => [])
        allow(Leases).to receive(:all).and_return([])
      end

      it "shows each port with its address and how it got it, the internet side read-only" do
        get "/network"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("This NAS", "192.168.1.13/24", "from the network (DHCP)", "router 192.168.1.1", "Managed by", "Change")
        expect(response.body).to include('name="interface" value="ens18"')
        expect(response.body).not_to include('name="address" value="ens20"')
      end

      it "shows what each port is, its link and MAC, its given name, and Find port for a real one only" do
        get "/network"
        expect(response.body).to include("Intel I350 Gigabit Network Connection · link up, 1000 Mb/s · a0:36:9f:12:34:56",
                                         "virtual port (virtio) · link up · bc:24:11:4c:4a:46", "<strong>Modem</strong>")
        expect(response.body.scan('>Find port</button>').size).to eq(1) # the real port's; the virtual one has none
        expect(response.body).to include('id="label-ens20"')
      end

      it "names a port, shows the name wherever the port comes up, and drops it again" do
        put "/network/port/label", params: { interface: 'ens18', label: ' Office ' }
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("ens18 is Office.")
        expect(Setting.get('port-label:ens18')).to eq('Office')
        allow(DnsService).to receive_messages(interface: 'ens18', wan_interface: 'ens20', installed?: false, on?: false)
        get "/network/dns"
        expect(response.body).to include("Office (ens18) (")
        put "/network/port/label", params: { interface: 'ens18', label: '' }
        expect(flash[:notice]).to eq("ens18 has no name of its own.")
        put "/network/port/label", params: { interface: 'ens18', label: 'x' * 40 }
        expect(flash[:alert]).to eq("A port's name is up to 32 characters.")
        put "/network/port/label", params: { interface: 'ens99', label: 'x' }
        expect(flash[:alert]).to include("isn't a network interface")
      end

      it "blinks a port's light through the helper" do
        post "/network/port/blink", params: { interface: 'ens18' }
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("ens18's light blinked for five seconds.")
        expect(Privileged.calls).to eq([['network.blink_port', { interface: 'ens18' }]])
      end

      it "changes another port's address at once, and what follows the address follows" do
        put "/network/address", params: { interface: 'ens18', mode: 'fixed', address: '192.168.1.111', prefix: '24', gateway: '192.168.1.1', dns: '192.168.1.1, 9.9.9.9' }
        expect(response).to redirect_to("/network")
        expect(flash[:notice]).to eq("ens18 is at 192.168.1.111.")
        expect(Privileged.calls).to eq([['network.set_address', { interface: 'ens18', mode: 'fixed', guard: false, address: '192.168.1.111/24',
                                                                   gateway: '192.168.1.1', dns: ['192.168.1.1', '9.9.9.9'] }]])
        expect(NetworkAddress).to have_received(:settle!)
      end

      it "shows the moving page for the port this request came in through, and the change waits to be reached" do
        allow(NetworkAddress).to receive(:arrival_interface).and_return('ens18')
        allow(SystemInfo).to receive(:hostname).and_return('nas')
        put "/network/address", params: { interface: 'ens18', mode: 'fixed', address: '192.168.1.111', prefix: '24' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Moving the NAS to 192.168.1.111', 'data-probe="http://192.168.1.111:3000/network/address/reached"',
                                         'data-target="http://192.168.1.111:3000/network"', 'data-status="/network/address"')
        # The probe calls the new address, another origin: this page's policy lets it, and only this page's
        expect(response.headers['Content-Security-Policy']).to include("connect-src 'self' http://192.168.1.111:3000")
        get "/network"
        expect(response.headers['Content-Security-Policy']).to include("connect-src 'self';")
        expect(Privileged.calls.last).to eq(['network.set_address', { interface: 'ens18', mode: 'fixed', guard: true, address: '192.168.1.111/24', gateway: nil, dns: [] }])
        expect(NetworkAddress).not_to have_received(:settle!)
        put "/network/address", params: { interface: 'ens18', mode: 'automatic' }
        expect(response.body).to include('Moving the NAS to nas.local', 'asks the network for an address')
      end

      it "refuses the internet side, a port that isn't there, automatic on the port the NAS hands out addresses on, and what the helper refuses" do
        put "/network/address", params: { interface: 'ens20', mode: 'automatic' }
        expect(flash[:alert]).to include('internet side')
        put "/network/address", params: { interface: 'ens99', mode: 'automatic' }
        expect(flash[:alert]).to include("isn't a network interface")
        allow(DnsService).to receive_messages(dhcp?: true, interface: 'ens18')
        put "/network/address", params: { interface: 'ens18', mode: 'automatic' }
        expect(flash[:alert]).to include('needs a fixed one')
        expect(Privileged.calls).to be_empty
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.set_address', "\"192.168.1.0/24\" is the network's own address", refused: true))
        put "/network/address", params: { interface: 'ens18', mode: 'fixed', address: '192.168.1.0' }
        expect(response).to redirect_to("/network")
        expect(flash[:alert]).to eq("\"192.168.1.0/24\" is the network's own address.")
      end

      it "keeps a change waiting only when reached through the changed port" do
        allow(NetworkAddress).to receive(:state).and_return('state' => 'pending', 'interface' => 'ens18', 'since' => Time.now.to_i, 'until' => Time.now.to_i + 80)
        allow(NetworkAddress).to receive(:arrival_interface).and_return('ens19')
        post "/network/address/reached"
        expect(response).to have_http_status(:no_content)
        expect(Privileged.calls).to be_empty
        allow(NetworkAddress).to receive(:arrival_interface).and_return('ens18')
        post "/network/address/reached"
        expect(response).to have_http_status(:no_content)
        expect(Privileged.calls).to eq([['network.keep_address', {}]])
        expect(NetworkAddress).to have_received(:settle!)
      end

      it "says where the last change stands, on the page and to the moving page" do
        allow(NetworkAddress).to receive(:state).and_return('state' => 'kept', 'interface' => 'ens18', 'mode' => 'fixed', 'address' => '192.168.1.111/24',
                                                            'since' => Time.now.to_i - 30, 'until' => nil, 'files' => ['/etc/netplan/50-cloud-init.yaml'])
        get "/network/address", headers: { 'Accept' => 'application/json' }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('state' => 'kept', 'interface' => 'ens18', 'address' => '192.168.1.111/24')
        expect(JSON.parse(response.body)).not_to have_key('files')
        get "/network"
        expect(response.body).to include("ens18 moved to 192.168.1.111.")
        allow(NetworkAddress).to receive(:state).and_return('state' => 'reverted', 'interface' => 'ens18', 'mode' => 'automatic', 'since' => Time.now.to_i - 30)
        get "/network"
        expect(response.body).to include("ens18 went back: nothing reached the NAS at an address from the network in time.")
      end
    end

    it "sends the old DNS Aliases, Gateway and Settings pages to the new tabs" do
      get "/network/dns_aliases"
      expect(response).to redirect_to("/network/dns#dns-aliases")
      get "/network/gateway"
      expect(response).to redirect_to("/network/dhcp")
      get "/network/settings"
      expect(response).to redirect_to("/network/dns")
    end

    describe "GET /network/remote_access" do
      it "renders the remote access page" do
        allow(CloudflareService).to receive(:status).and_return({ installed: false, running: false })
        allow(SecurityAudit).to receive(:blockers).and_return([])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end

      it "renders with tunnel running" do
        allow(CloudflareService).to receive(:status).and_return({ installed: true, running: true, token_configured: true })
        allow(SecurityAudit).to receive(:blockers).and_return([])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end

      it "renders with security blockers present" do
        allow(CloudflareService).to receive(:status).and_return({ installed: false, running: false })
        allow(SecurityAudit).to receive(:blockers).and_return(["ufw_firewall"])
        get "/network/remote_access"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /network/start_tunnel" do
      it "starts the tunnel" do
        allow(SecurityAudit).to receive(:blockers).and_return([])
        allow(CloudflareService).to receive(:start!).and_return(true)
        post "/network/remote_access/start_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "POST /network/stop_tunnel" do
      it "stops the tunnel" do
        allow(CloudflareService).to receive(:stop!).and_return(true)
        post "/network/remote_access/stop_tunnel", as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    # --- Security ---

    describe "GET /network/security" do
      it "renders the security page" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        get "/network/security"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Security blockers found!")
      end

      it "says so when a blocker fails" do
        blocker = SecurityAudit::Check.new(name: 'ufw_firewall', description: 'UFW firewall enabled',
                                           status: :fail, severity: :blocker)
        allow(SecurityAudit).to receive(:run_all).and_return([blocker])
        get "/network/security"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Security blockers found!")
      end
    end

    describe "GET /network/security/audit_stream" do
      it "returns SSE content type" do
        allow(SecurityAudit).to receive(:run_all).and_return([])
        get "/network/security/audit_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "GET /network/security/fix_stream" do
      it "returns SSE content type" do
        get "/network/security/fix_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end

    describe "POST /network/security/fix" do
      it "fixes a specific security check" do
        allow(SecurityAudit).to receive(:fix!).with("ufw_firewall").and_return(true)
        post "/network/security/fix", params: { check_name: "ufw_firewall" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(body["check"]).to eq("ufw_firewall")
      end

      it "returns error when fix fails" do
        allow(SecurityAudit).to receive(:fix!).with("unknown_check").and_return(false)
        post "/network/security/fix", params: { check_name: "unknown_check" }, as: :json
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("error")
      end
    end
  end
end
