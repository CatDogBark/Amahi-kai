require 'rails_helper'
require 'allowed_hosts'

RSpec.describe AllowedHosts do
  # Ask Rails' own host check whether a Host header would get through.
  def allowed?(host, env: { "RAILS_ALLOWED_HOSTS" => "nas.example.lan" }, tailscale_name: nil)
    list = AllowedHosts.list(env: env, hostname: "amahi-kai", tailscale_name: tailscale_name)
    ActionDispatch::HostAuthorization::Permissions.new(list).allows?(host)
  end

  describe ".list" do
    it "allows any IP address, so the LAN IP always works" do
      expect(allowed?("192.168.1.111")).to be true
      expect(allowed?("100.64.96.4")).to be true
      expect(allowed?("127.0.0.1")).to be true
    end

    it "allows localhost and the machine's own names" do
      expect(allowed?("localhost")).to be true
      expect(allowed?("amahi-kai")).to be true
      expect(allowed?("amahi-kai.local")).to be true
    end

    it "allows the NAS's Tailscale name" do
      expect(allowed?("amahi-kai.tail1234.ts.net", tailscale_name: "amahi-kai.tail1234.ts.net")).to be true
    end

    it "allows the names in RAILS_ALLOWED_HOSTS, whatever their case" do
      expect(allowed?("nas.example.lan")).to be true
      expect(allowed?("NAS.Example.LAN")).to be true
    end

    it "blocks any other hostname" do
      expect(allowed?("rebind.attacker.example")).to be false
      expect(allowed?("amahi-kai.attacker.example")).to be false
    end

    it "reads a comma-separated list with spaces and blanks" do
      env = { "RAILS_ALLOWED_HOSTS" => " a.example , ,b.example" }
      expect(allowed?("a.example", env: env)).to be true
      expect(allowed?("b.example", env: env)).to be true
    end

    it "still reads the older single RAILS_ALLOWED_HOST" do
      expect(allowed?("old.example", env: { "RAILS_ALLOWED_HOST" => "old.example" })).to be true
    end
  end

  describe ".local_request?" do
    it "is true for requests from the NAS itself" do
      %w[127.0.0.1 ::1 ::ffff:127.0.0.1].each do |addr|
        expect(AllowedHosts.local_request?(double(remote_addr: addr))).to be(true), addr
      end
    end

    it "is false for anything else" do
      ["192.168.1.74", "100.64.96.4", "", nil].each do |addr|
        expect(AllowedHosts.local_request?(double(remote_addr: addr))).to be(false), addr.inspect
      end
    end
  end

  describe ".tailscale_dns_name" do
    before { allow(File).to receive(:executable?).and_call_original }

    it "reads the MagicDNS name without its trailing dot" do
      allow(File).to receive(:executable?).with("/usr/bin/tailscale").and_return(true)
      json = { "Self" => { "DNSName" => "amahi-kai.tail1234.ts.net." } }.to_json
      allow(Open3).to receive(:capture2).and_return([json, double(success?: true)])
      expect(AllowedHosts.tailscale_dns_name).to eq("amahi-kai.tail1234.ts.net")
    end

    it "is nil when Tailscale isn't installed" do
      allow(File).to receive(:executable?).with("/usr/bin/tailscale").and_return(false)
      expect(AllowedHosts.tailscale_dns_name).to be_nil
    end

    it "is nil when Tailscale isn't running" do
      allow(File).to receive(:executable?).with("/usr/bin/tailscale").and_return(true)
      allow(Open3).to receive(:capture2).and_return(["", double(success?: false)])
      expect(AllowedHosts.tailscale_dns_name).to be_nil
    end
  end

  # The middleware with exactly the production settings (config/environments/production.rb).
  describe "as the production host check" do
    let(:app) { ->(_env) { [200, {}, ["ok"]] } }
    let(:middleware) do
      ActionDispatch::HostAuthorization.new(
        app,
        AllowedHosts.list(env: {}, hostname: "amahi-kai", tailscale_name: nil),
        exclude: ->(request) { AllowedHosts.local_request?(request) },
        response_app: ->(env) { AllowedHosts.blocked_response(env) }
      )
    end

    def request(host, from:)
      env = Rack::MockRequest.env_for("http://#{host}/login", "HTTP_HOST" => host, "REMOTE_ADDR" => from)
      middleware.call(env)
    end

    it "lets the LAN IP through" do
      status, = request("192.168.1.111:3000", from: "192.168.1.74")
      expect(status).to eq(200)
    end

    it "lets a Cloudflare Tunnel hostname through with no setup" do
      status, = request("nas.amahi-kai.com", from: "127.0.0.1")
      expect(status).to eq(200)
    end

    it "refuses an unknown name from the network, explaining what to do" do
      status, headers, body = request("rebind.attacker.example:3000", from: "192.168.1.74")
      expect(status).to eq(403)
      expect(headers["content-type"]).to start_with("text/plain")
      text = body.join
      expect(text).to include('"rebind.attacker.example"', "RAILS_ALLOWED_HOSTS", "/etc/amahi-kai/amahi.env")
    end
  end
end
