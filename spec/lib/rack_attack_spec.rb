require 'rails_helper'

# Rack::Attack is off in the test environment, so these check the address it throttles by.
RSpec.describe Rack::Attack do
  def request(env)
    Rack::Attack::Request.new(Rack::MockRequest.env_for('/user_sessions', { method: 'POST' }.merge(env)))
  end

  it 'throttles a LAN client by its own address, whatever forwarding headers it sends' do
    req = request('REMOTE_ADDR' => '192.168.1.50', 'HTTP_X_FORWARDED_FOR' => '10.9.9.9',
                  'HTTP_CF_CONNECTING_IP' => '1.2.3.4')
    expect(described_class.client_ip(req)).to eq('192.168.1.50')
    expect(described_class.throttles['logins/ip'].block.call(req)).to eq('192.168.1.50')
  end

  it "throttles a visitor through the Cloudflare Tunnel by Cloudflare's address for them" do
    expect(described_class.client_ip(request('REMOTE_ADDR' => '127.0.0.1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.7')))
      .to eq('203.0.113.7')
    expect(described_class.client_ip(request('REMOTE_ADDR' => '::1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.8')))
      .to eq('203.0.113.8')
  end

  it 'falls back to localhost for local requests without the header' do
    expect(described_class.client_ip(request('REMOTE_ADDR' => '127.0.0.1'))).to eq('127.0.0.1')
  end
end
