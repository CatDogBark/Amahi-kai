require 'spec_helper'

RSpec.describe Leases do
  describe ".all" do
    it "returns an empty array when lease file doesn't exist" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Leases::LEASEFILE).and_return(false)
      expect(Leases.all).to eq([])
    end
  end

  describe ".read_lease (private)" do
    let(:tmpfile) { Tempfile.new('leases') }

    after { tmpfile.close! }

    it "parses dnsmasq lease lines" do
      tmpfile.write("1708099200 aa:bb:cc:dd:ee:ff 192.168.1.100 myhost *\n")
      tmpfile.write("1708099300 11:22:33:44:55:66 192.168.1.101 otherhost *\n")
      tmpfile.flush

      result = Leases.send(:read_lease, tmpfile.path)
      expect(result.size).to eq(2)
      expect(result.first[:mac]).to eq("aa:bb:cc:dd:ee:ff")
      expect(result.first[:ip]).to eq("192.168.1.100")
      expect(result.first[:name]).to eq("myhost")
      expect(result.first[:expiration]).to eq(1708099200)
    end

    it "sorts by expiration" do
      tmpfile.write("1708099300 aa:bb:cc:dd:ee:ff 192.168.1.100 later *\n")
      tmpfile.write("1708099200 11:22:33:44:55:66 192.168.1.101 earlier *\n")
      tmpfile.flush

      result = Leases.send(:read_lease, tmpfile.path)
      expect(result.first[:name]).to eq("earlier")
      expect(result.last[:name]).to eq("later")
    end

    it "skips comment lines" do
      tmpfile.write("# this is a comment\n")
      tmpfile.write("1708099200 aa:bb:cc:dd:ee:ff 192.168.1.100 myhost *\n")
      tmpfile.flush

      result = Leases.send(:read_lease, tmpfile.path)
      expect(result.size).to eq(1)
    end

    it "returns empty for empty file" do
      tmpfile.flush
      result = Leases.send(:read_lease, tmpfile.path)
      expect(result).to eq([])
    end

    it "returns empty for nonexistent file" do
      result = Leases.send(:read_lease, "/nonexistent/path/leases")
      expect(result).to eq([])
    end
  end
end
