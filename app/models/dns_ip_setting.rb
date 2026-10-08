require 'resolv'

class DnsIpSetting < Setting
  validates :value, presence: true, format: { with: Resolv::IPv4::Regex }

  def self.custom_dns_ips
    [
      self.find_or_create_by(Setting::NETWORK, "dns_ip_1", "1.1.1.1"),
      self.find_or_create_by(Setting::NETWORK, "dns_ip_2", "1.0.0.1"),
    ].map(&:value)
  end
end
