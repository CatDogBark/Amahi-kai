require 'spec_helper'

describe Platform do
  describe ".platform" do
    it "returns a supported platform" do
      expect(Platform::PLATFORMS).to include(Platform.platform)
    end
  end

  describe ".file_name" do
    it "returns syslog path" do
      expect(Platform.file_name(:syslog)).to eq("/var/log/syslog")
    end

    it "raises for unknown filenames" do
      expect { Platform.file_name(:nonexistent) }.to raise_error(RuntimeError, /unknown filename/)
    end
  end

  describe ".platform_versions" do
    it "returns a hash with :platform and :core keys" do
      versions = Platform.platform_versions
      expect(versions).to have_key(:platform)
      expect(versions).to have_key(:core)
    end
  end

  describe "platform detection" do
    it "detects ubuntu or debian" do
      expect(%w[ubuntu debian]).to include(Platform.platform)
    end
  end

  describe ".set_hostname!" do
    it "turns a server name into a hostname and sets it through the root helper" do
      { "My NAS" => "my-nas", "  Bob's NAS! " => "bob-s-nas", "amahi-kai" => "amahi-kai" }.each do |name, hostname|
        Privileged.reset!
        expect(Platform.set_hostname!(name)).to be true
        expect(Privileged.calls).to eq([['network.set_hostname', { hostname: hostname }]])
      end
    end

    it "returns false when the helper refuses" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.set_hostname', 'refused'))
      expect(Platform.set_hostname!("!!!")).to be false
    end
  end
end
