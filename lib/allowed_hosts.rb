require 'ipaddr'
require 'socket'

# Host names the production server answers to (config.hosts). A request for any
# other name gets Rails' "Blocked host" response. That stops DNS rebinding: a web
# page can't point a hostname it controls at the NAS and then talk to the NAS
# from the visitor's browser.
module AllowedHosts
  # IP addresses are always allowed: a rebinding attack needs a hostname, and this
  # keeps http://<nas-ip>:3000 working even if a name below is missing.
  ANY_IP = [IPAddr.new("0.0.0.0/0"), IPAddr.new("::/0")].freeze

  # localhost, this machine's hostname and hostname.local, plus the comma-separated
  # names in RAILS_ALLOWED_HOSTS (and the older single RAILS_ALLOWED_HOST), such as
  # the Cloudflare Tunnel hostname. Both are set in /etc/amahi-kai/amahi.env.
  def self.list(env: ENV, hostname: Socket.gethostname)
    name = hostname.to_s.strip.downcase
    names = ["localhost"]
    names += [name, "#{name}.local"] unless name.empty?
    extra = [env["RAILS_ALLOWED_HOSTS"], env["RAILS_ALLOWED_HOST"]].compact.join(",")
    names += extra.split(",").map { |h| h.strip.downcase }.reject(&:empty?)
    ANY_IP + names.uniq
  end
end
