# Rate limiting and request throttling
# https://github.com/rack/rack-attack

# Disable in test environment
Rack::Attack.enabled = !Rails.env.test?

class Rack::Attack
  # Throttle login attempts by IP address
  # 5 attempts per 20 seconds
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/user_sessions" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by username
  # 10 attempts per minute per username
  throttle("logins/username", limit: 10, period: 60.seconds) do |req|
    if req.path == "/user_sessions" && req.post?
      # Normalize username to prevent case-based bypass
      req.params.dig("username")&.downcase&.strip
    end
  end

  # Throttle API/AJAX requests
  # 60 requests per minute per IP
  throttle("api/ip", limit: 60, period: 60.seconds) do |req|
    req.ip if req.xhr?
  end

  # Block suspicious requests
  blocklist("fail2ban/logins") do |req|
    # Block IPs that fail login 20 times in 1 hour
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 20, findtime: 1.hour, bantime: 1.hour) do
      req.path == "/user_sessions" && req.post?
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |req|
    [429, { "Content-Type" => "text/plain" }, ["Rate limit exceeded. Try again later.\n"]]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |req|
    [403, { "Content-Type" => "text/plain" }, ["Blocked.\n"]]
  end
end
