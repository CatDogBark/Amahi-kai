# Rate limiting and request throttling
# https://github.com/rack/rack-attack

# Disable in test environment
Rack::Attack.enabled = !Rails.env.test?

class Rack::Attack
  # The client's address. Rack's req.ip believes X-Forwarded-For from any private address,
  # so a LAN client could claim a new address on every attempt. A direct connection is
  # throttled by the socket's address. The Cloudflare Tunnel connects from the NAS itself
  # (cloudflared on localhost) and sends the visitor's address as CF-Connecting-IP.
  def self.client_ip(req)
    remote = req.get_header('REMOTE_ADDR').to_s
    return remote unless %w[127.0.0.1 ::1].include?(remote)

    req.get_header('HTTP_CF_CONNECTING_IP').presence || remote
  end

  # Sign-in attempts are limited in UserSessionsController (rate_limit, and a ban on repeated
  # failures), at the action whatever path reached it: here they were matched by the exact
  # path, which /user_sessions.json went around, and the ban counted successful sign-ins too.

  # Throttle API/AJAX requests
  # 60 requests per minute per IP
  throttle("api/ip", limit: 60, period: 60.seconds) do |req|
    client_ip(req) if req.xhr?
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |req|
    [429, { "Content-Type" => "text/plain" }, ["Rate limit exceeded. Try again later.\n"]]
  end
end
