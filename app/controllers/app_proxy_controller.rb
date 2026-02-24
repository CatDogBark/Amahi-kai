require 'net/http'
require 'uri'

class AppProxyController < ApplicationController
  before_action :admin_required
  before_action :find_app

  # Skip hooks that interfere with proxying (theme, DNS alias redirect, etc.)
  skip_before_action :before_action_hook
  # Skip CSRF for proxied POST/PUT requests from the app
  skip_before_action :verify_authenticity_token, only: [:proxy]

  # Proxy all requests to the Docker app's local port
  def proxy
    unless @docker_app.status == 'running' && @docker_app.host_port.present?
      render plain: "App is not running", status: :service_unavailable
      return
    end

    target_port = @docker_app.host_port
    prefix = "/app/#{@docker_app.identifier}"

    # Strip the /app/{identifier} prefix — upstream sees root-relative paths
    # (baseURL is NOT set on the server; we rewrite the JS config instead)
    sub_path = params[:path].to_s
    sub_path = "/#{sub_path}" unless sub_path.start_with?('/')
    # Preserve trailing slash — Rails *path glob AND request.path both strip it
    raw_path = request.env['REQUEST_URI'] || request.original_fullpath || request.path
    sub_path += '/' if raw_path.end_with?('/') && !sub_path.end_with?('/')
    query = request.query_string.present? ? "?#{request.query_string}" : ""

    # Detect HTTPS upstream — some apps (Nextcloud, Portainer) use SSL internally
    upstream_ssl = ssl_port?(@docker_app)
    scheme = upstream_ssl ? 'https' : 'http'
    target_uri = URI("#{scheme}://127.0.0.1:#{target_port}#{sub_path}#{query}")

    begin
      http = Net::HTTP.new(target_uri.host, target_uri.port)
      if upstream_ssl
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE # local container, self-signed cert
      end
      http.open_timeout = 5
      http.read_timeout = 30

      # Map request method
      klass = case request.method
      when 'GET'     then Net::HTTP::Get
      when 'POST'    then Net::HTTP::Post
      when 'PUT'     then Net::HTTP::Put
      when 'PATCH'   then Net::HTTP::Patch
      when 'DELETE'  then Net::HTTP::Delete
      when 'HEAD'    then Net::HTTP::Head
      when 'OPTIONS' then Net::HTTP::Options
      else
        render plain: "Method not supported", status: :method_not_allowed
        return
      end

      outgoing = klass.new(target_uri)

      # Forward request headers — skip accept-encoding so upstream sends uncompressed
      # (we need to read/rewrite HTML responses)
      skip_headers = %w[host connection transfer-encoding keep-alive upgrade proxy-authorization te trailer accept-encoding]
      request.headers.each do |key, value|
        next unless key.start_with?('HTTP_')
        header_name = key.sub('HTTP_', '').tr('_', '-').downcase
        next if skip_headers.include?(header_name)
        outgoing[header_name] = value
      end

      # Forward Content-Type header
      if request.content_type.present?
        outgoing['Content-Type'] = request.content_type
      end

      # Forward body for POST/PUT/PATCH
      if %w[POST PUT PATCH].include?(request.method)
        outgoing.body = request.body.read
      end

      # Forwarded headers for the upstream app
      outgoing['X-Forwarded-For'] = request.remote_ip
      outgoing['X-Forwarded-Proto'] = request.scheme
      outgoing['X-Forwarded-Host'] = request.host
      outgoing['X-Real-IP'] = request.remote_ip

      Rails.logger.info("PROXY >>> #{request.method} #{target_uri} (from #{request.path})")

      # Execute
      upstream = http.request(outgoing)

      status_code = upstream.code.to_i

      # Build response headers
      skip_response = %w[transfer-encoding connection keep-alive content-length content-type]
      upstream.each_header do |name, value|
        next if skip_response.include?(name.downcase)

        if name.downcase == 'location'
          value = rewrite_location(value, @docker_app)
        end

        if name.downcase == 'set-cookie'
          value = rewrite_cookie_path(value, @docker_app)
        end

        response.headers[name] = value
      end

      content_type = upstream['content-type'].to_s
      body = upstream.body || ''

      Rails.logger.info("PROXY <<< #{status_code} #{content_type} (#{body.bytesize} bytes) for #{target_uri}")

      # Rewrite HTML responses for proxied apps
      if content_type.include?('text/html')
        body = rewrite_html(body, @docker_app)
      end

      # Fix MIME type — some apps return application/octet-stream for CSS/JS
      effective_type = content_type.presence || 'application/octet-stream'
      if effective_type.include?('application/octet-stream')
        effective_type = mime_from_path(sub_path) || effective_type
      end

      render body: body, content_type: effective_type, status: status_code

    rescue Errno::ECONNREFUSED
      render plain: "Cannot connect to #{@docker_app.name} — is it running?", status: :bad_gateway
    rescue Net::OpenTimeout, Net::ReadTimeout
      render plain: "#{@docker_app.name} is not responding", status: :gateway_timeout
    rescue => e
      Rails.logger.error("App proxy error: #{e.message}")
      render plain: "Proxy error: #{e.message}", status: :bad_gateway
    end
  end

  private

  def find_app
    @docker_app = DockerApp.find_by(identifier: params[:app_id])
    unless @docker_app
      render plain: "App not found", status: :not_found
    end
  end

  def rewrite_html(body, app)
    prefix = "/app/#{app.identifier}"

    # 1. Inject <base> tag using the current request path (not just the prefix)
    #    e.g., Jellyfin serves from /web/, so base must be /app/jellyfin/web/
    base_path = request.path
    base_path += '/' unless base_path.end_with?('/')
    base_tag = "<base href=\"#{base_path}\">"
    body = if body =~ /<head([^>]*)>/i
      body.sub(/<head([^>]*)>/i, "<head\\1>#{base_tag}")
    else
      base_tag + body
    end

    # 2. Rewrite root-absolute paths in HTML attributes
    #    /static/foo → /app/filebrowser/static/foo
    body = body.gsub(%r{((?:src|href|action)\s*=\s*["'])/(?!app/|https?:|data:|//)([^"']*["'])}, "\\1#{prefix}/\\2")

    # 3. Rewrite the app's JS config to use the proxy prefix for API calls
    #    "BaseURL":"" → "BaseURL":"/app/filebrowser"
    body = body.gsub('"BaseURL":""', "\"BaseURL\":\"#{prefix}\"")
    body = body.gsub('"baseURL":""', "\"baseURL\":\"#{prefix}\"")

    body
  end

  # Infer MIME type from file extension when upstream doesn't provide one
  def mime_from_path(path)
    ext = File.extname(path.to_s.split('?').first).downcase
    {
      '.css'  => 'text/css; charset=utf-8',
      '.js'   => 'application/javascript; charset=utf-8',
      '.json' => 'application/json; charset=utf-8',
      '.svg'  => 'image/svg+xml',
      '.png'  => 'image/png',
      '.jpg'  => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.gif'  => 'image/gif',
      '.webp' => 'image/webp',
      '.woff' => 'font/woff',
      '.woff2'=> 'font/woff2',
      '.ttf'  => 'font/ttf',
      '.ico'  => 'image/x-icon',
      '.map'  => 'application/json',
    }[ext]
  end

  # Apps that use HTTPS internally (container port is 443 or 9443)
  def ssl_port?(app)
    return false unless app.port_mappings.present?
    ports = app.port_mappings
    ports = JSON.parse(ports) if ports.is_a?(String)
    ssl_ports = %w[443 9443 8443]
    ports.keys.any? { |k| ssl_ports.include?(k.to_s) }
  rescue
    false
  end

  def rewrite_location(location, app)
    prefix = "/app/#{app.identifier}"
    port = app.host_port

    if location =~ %r{^https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::#{port})?(.*)}
      "#{prefix}#{$1}"
    elsif location.start_with?('/') && !location.start_with?(prefix)
      "#{prefix}#{location}"
    elsif !location.start_with?('/') && !location.start_with?('http')
      # Relative redirect (e.g., "web/") — make it absolute under the proxy prefix
      "#{prefix}/#{location}"
    else
      location
    end
  end

  def rewrite_cookie_path(cookie, app)
    prefix = "/app/#{app.identifier}"
    cookie.gsub(%r{[Pp]ath=/(?=\s|;|$)}, "Path=#{prefix}/")
  end
end
