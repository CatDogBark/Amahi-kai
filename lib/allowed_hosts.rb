require 'ipaddr'
require 'json'
require 'open3'
require 'socket'

# Host names the production server answers to (config.hosts). A request for any
# other name is refused. That stops DNS rebinding: a web page can't point a
# hostname it controls at the NAS and then talk to the NAS from the visitor's
# browser. A new install needs no setup: see the three rules below.
module AllowedHosts
  # IP addresses are always allowed: a rebinding attack needs a hostname, and this
  # keeps http://<nas-ip>:3000 working even if a name is missing.
  ANY_IP = [IPAddr.new("0.0.0.0/0"), IPAddr.new("::/0")].freeze

  ENV_FILE = "/etc/amahi-kai/amahi.env".freeze

  # localhost, this machine's hostname and hostname.local, the NAS's Tailscale name
  # when Tailscale runs on it, plus the comma-separated names in RAILS_ALLOWED_HOSTS
  # (and the older single RAILS_ALLOWED_HOST) from the env file.
  def self.list(env: ENV, hostname: Socket.gethostname, tailscale_name: tailscale_dns_name)
    name = hostname.to_s.strip.downcase
    names = ["localhost"]
    names += [name, "#{name}.local"] unless name.empty?
    names << tailscale_name.downcase if tailscale_name.present?
    extra = [env["RAILS_ALLOWED_HOSTS"], env["RAILS_ALLOWED_HOST"]].compact.join(",")
    names += extra.split(",").map { |h| h.strip.downcase }.reject(&:empty?)
    ANY_IP + names.uniq
  end

  # Requests from the NAS itself skip the check. That covers the Cloudflare Tunnel:
  # cloudflared runs on the NAS and connects to the app from 127.0.0.1, so every
  # tunnel hostname works without setup. Rebinding always arrives from a browser
  # elsewhere on the network, never from the NAS's own loopback address.
  def self.local_request?(request)
    ip = IPAddr.new(request.remote_addr.to_s)
    ip = ip.native if ip.ipv6? && ip.ipv4_mapped?
    ip.loopback?
  rescue IPAddr::InvalidAddressError
    false
  end

  # The NAS's MagicDNS name (such as nas.tail1234.ts.net) when Tailscale runs on it.
  # Read once at boot, so a Tailscale install shows up after the next restart.
  def self.tailscale_dns_name
    return nil unless File.executable?("/usr/bin/tailscale")
    out, status = Open3.capture2("timeout", "3", "/usr/bin/tailscale", "status", "--json")
    return nil unless status.success?
    JSON.parse(out).dig("Self", "DNSName").to_s.chomp(".").presence
  rescue JSON::ParserError, SystemCallError
    nil
  end

  # What a refused request sees instead of a blank page. Plain text: the Host
  # header is the requester's, so nothing in it is rendered as HTML.
  def self.blocked_response(env)
    host = env["HTTP_HOST"].to_s.sub(/:\d+\z/, "")
    body = "This Amahi-kai server doesn't answer to the name \"#{host}\".\n\n" \
           "Open it by its IP address instead, or add the name to RAILS_ALLOWED_HOSTS " \
           "in #{ENV_FILE} (comma-separated) and restart Amahi-kai " \
           "(sudo systemctl restart amahi-kai).\n"
    [403, { "content-type" => "text/plain; charset=utf-8" }, [body]]
  end
end
