require 'spec_helper'

RSpec.describe Ping do
  describe ".pingecho" do
    it "returns false for unreachable host" do
      # Use a non-routable IP to trigger timeout
      result = Ping.pingecho("192.0.2.1", 1)
      expect(result).to be false
    end

    it "returns true when connection is refused" do
      # Stub TCPSocket to raise ECONNREFUSED (host is up but port closed)
      allow(TCPSocket).to receive(:new).and_raise(Errno::ECONNREFUSED)
      result = Ping.pingecho("localhost", 1)
      expect(result).to be true
    end

    it "returns true on successful connection" do
      socket = double("socket", close: nil)
      allow(TCPSocket).to receive(:new).and_return(socket)
      result = Ping.pingecho("localhost", 1)
      expect(result).to be true
    end
  end
end
