# A port let in from the internet to a device on the LAN, while the NAS is the router (Network →
# DNS & DHCP). The address is the last part of the device's address on DHCP's network, as a fixed
# host's is; a change rewrites the router's rules.
class PortForward < ApplicationRecord
  PROTOCOLS = %w[tcp udp].freeze

  before_validation { self.to_port = port if to_port.blank? }
  after_commit :rewrite_router

  validates :name, length: { maximum: 40 }
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :port, :to_port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }
  validates :port, uniqueness: { scope: :protocol, message: 'is forwarded already (for that protocol)' }
  validates :address, presence: true, numericality: { only_integer: true, greater_than: 1, less_than: 255 }

  # What the root helper takes: each forward with the device's whole address on +prefix+'s
  # network ("10.99.0").
  def self.for_helper(prefix)
    order(:protocol, :port).map do |f|
      { protocol: f.protocol, port: f.port, address: "#{prefix}.#{f.address}", to_port: f.to_port }
    end
  end

  def label
    "#{protocol} #{port}#{" → #{to_port}" if to_port != port}"
  end

  private

  def rewrite_router
    DnsService.rewrite_router!
  rescue Privileged::Error => e
    Rails.logger.error("PortForward #{label}: the router's rules weren't rewritten: #{e.message}")
  end
end
