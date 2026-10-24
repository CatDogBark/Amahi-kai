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
    before { login_as_admin }

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
    end

    describe "This NAS (its own address on each port)" do
      let(:address) { NetworkInterfaces::Address }
      let(:rows) do
        [NetworkAddress::Interface.new(name: 'ens18', addresses: [address.new(ip: IPAddr.new('192.168.1.13'), prefix: 24)], automatic: true, gateway: '192.168.1.1', part: :lan),
         NetworkAddress::Interface.new(name: 'ens20', addresses: [], automatic: false, gateway: '10.77.0.1', part: :internet)]
      end

      before do
        allow(NetworkAddress).to receive_messages(interfaces: rows, nameservers: ['192.168.1.1'], state: nil, settle!: nil)
        allow(Leases).to receive(:all).and_return([])
      end

      it "shows each port with its address and how it got it, the internet side read-only" do
        get "/network"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("This NAS", "192.168.1.13/24", "from the network (DHCP)", "router 192.168.1.1", "Managed by", "Change")
        expect(response.body).to include('name="interface" value="ens18"')
        expect(response.body).not_to include('name="interface" value="ens20"')
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
