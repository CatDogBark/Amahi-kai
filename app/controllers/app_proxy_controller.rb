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

    # Strip the /app/{identifier} prefix — upstream app sees root-relative paths
    sub_path = params[:path].to_s
    sub_path = "/#{sub_path}" unless sub_path.start_with?('/')
    query = request.query_string.present? ? "?#{request.query_string}" : ""

    target_uri = URI("http://127.0.0.1:#{target_port}#{sub_path}#{query}")

    begin
      http = Net::HTTP.new(target_uri.host, target_uri.port)
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

      # Forward request headers
      skip_headers = %w[host connection transfer-encoding keep-alive upgrade proxy-authorization te trailer]
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

      # Execute
      upstream = http.request(outgoing)

      # Send response with correct status
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

      # Rewrite HTML responses to fix asset paths
      if content_type.include?('text/html')
        body = rewrite_html(body, @docker_app)
      end

      # Use send_data for full control over Content-Type (prevents Rails MIME override)
      send_data body, type: content_type.presence || 'application/octet-stream',
                       disposition: 'inline', status: status_code

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

    # Inject <base> tag so relative URLs resolve under the proxy prefix
    # This handles SPA assets that use relative paths (e.g., "index-Ce8cFD10.css")
    base_tag = "<base href=\"#{prefix}/\">"
    body = if body =~ /<head([^>]*)>/i
      body.sub(/<head([^>]*)>/i, "<head\\1>#{base_tag}")
    else
      base_tag + body
    end

    # Rewrite root-absolute paths in src/href/action attributes
    # /static/foo → /app/filebrowser/static/foo
    # Skip already-prefixed, external, data URIs, and protocol-relative
    body.gsub(%r{((?:src|href|action)\s*=\s*["'])/(?!app/|https?:|data:|//)([^"']*["'])}, "\\1#{prefix}/\\2")
  end

  def rewrite_location(location, app)
    prefix = "/app/#{app.identifier}"
    port = app.host_port

    if location =~ %r{^https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0):#{port}(.*)}
      "#{prefix}#{$1}"
    elsif location.start_with?('/') && !location.start_with?(prefix)
      "#{prefix}#{location}"
    else
      location
    end
  end

  def rewrite_cookie_path(cookie, app)
    prefix = "/app/#{app.identifier}"
    cookie.gsub(%r{[Pp]ath=/(?=\s|;|$)}, "Path=#{prefix}/")
  end
end
