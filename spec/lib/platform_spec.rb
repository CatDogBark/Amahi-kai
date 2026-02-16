require 'spec_helper'

describe Platform do
  describe ".platform" do
    it "returns a supported platform" do
      expect(Platform::PLATFORMS).to include(Platform.platform)
    end
  end

  describe ".dnsmasq?" do
    it "returns a boolean" do
      expect(Platform.dnsmasq?).to be(true).or be(false)
    end
  end

  describe ".service_name" do
    it "maps :apache to apache2" do
      expect(Platform.service_name(:apache)).to eq("apache2")
    end

    it "maps :mysql to mariadb" do
      expect(Platform.service_name(:mysql)).to eq("mariadb")
    end

    it "maps :smb to smbd" do
      expect(Platform.service_name(:smb)).to eq("smbd")
    end

    it "returns the name itself for unknown services" do
      expect(Platform.service_name(:unknown_service)).to eq(:unknown_service)
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

  describe ".service_start_command" do
    it "returns systemctl start command" do
      expect(Platform.service_start_command(:apache)).to eq("/usr/bin/systemctl start apache2.service")
    end
  end

  describe ".service_stop_command" do
    it "returns systemctl stop command" do
      expect(Platform.service_stop_command(:smb)).to eq("/usr/bin/systemctl stop smbd.service")
    end
  end

  describe ".service_enable_command" do
    it "returns systemctl enable command" do
      expect(Platform.service_enable_command(:mysql)).to eq("/usr/bin/systemctl enable mariadb.service")
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
      expect(Platform.ubuntu? || Platform.debian?).to be true
    end
  end

  describe "DEFAULT_GROUP" do
    it "is 'users'" do
      expect(Platform::DEFAULT_GROUP).to eq("users")
    end
  end
end
