require 'resolv'

class DnsIpSetting < Setting
  validates :value, presence: true, format: { with: Resolv::IPv4::Regex }

  def self.dns_ips
    case self.get("dns")
    when "cloudflare"
      %w(1.1.1.1 1.0.0.1)
    when "google"
      %w(8.8.8.8 8.8.4.4)
    else
      custom_dns_ips
    end
  end

  def self.custom_dns_ips
    [
      self.find_or_create_by(Setting::NETWORK, "dns_ip_1", "1.1.1.1"),
      self.find_or_create_by(Setting::NETWORK, "dns_ip_2", "1.0.0.1"),
    ].map(&:value)
  end
end
