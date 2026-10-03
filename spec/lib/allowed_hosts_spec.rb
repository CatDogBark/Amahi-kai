require 'rails_helper'
require 'allowed_hosts'

RSpec.describe AllowedHosts do
  # Ask Rails' own host check whether a Host header would get through.
  def allowed?(host, env: { "RAILS_ALLOWED_HOSTS" => "nas.amahi-kai.com" })
    list = AllowedHosts.list(env: env, hostname: "amahi-kai")
    ActionDispatch::HostAuthorization::Permissions.new(list).allows?(host)
  end

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

  it "allows the names in RAILS_ALLOWED_HOSTS, whatever their case" do
    expect(allowed?("nas.amahi-kai.com")).to be true
    expect(allowed?("NAS.Amahi-Kai.com")).to be true
  end

  it "blocks any other hostname" do
    expect(allowed?("rebind.attacker.example")).to be false
    expect(allowed?("amahi-kai.com.attacker.example")).to be false
  end

  it "reads a comma-separated list with spaces and blanks" do
    env = { "RAILS_ALLOWED_HOSTS" => " a.example , ,b.example" }
    expect(allowed?("a.example", env: env)).to be true
    expect(allowed?("b.example", env: env)).to be true
  end

  it "still reads the older single RAILS_ALLOWED_HOST" do
    expect(allowed?("old.example", env: { "RAILS_ALLOWED_HOST" => "old.example" })).to be true
  end

  it "blocks the tunnel name when it isn't configured" do
    expect(allowed?("nas.amahi-kai.com", env: {})).to be false
  end
end
