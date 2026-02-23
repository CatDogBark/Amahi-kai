require 'net/http'
require 'uri'

class AppProxyController < ApplicationController
  before_action :admin_required
  before_action :find_app

  # Skip CSRF for proxied POST/PUT requests from the app
  skip_before_action :verify_authenticity_token, only: [:proxy]

  # Proxy all requests to the Docker app's local port
  def proxy
    unless @docker_app.status == 'running' && @docker_app.host_port.present?
      render plain: "App is not running", status: :service_unavailable
      return
    end

    target_port = @docker_app.host_port
    proxy_path = params[:path].to_s
    proxy_path = "/#{proxy_path}" unless proxy_path.start_with?('/')
    query = request.query_string.present? ? "?#{request.query_string}" : ""

    target_uri = URI("http://127.0.0.1:#{target_port}#{proxy_path}#{query}")

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

      # Forward body for POST/PUT/PATCH
      if %w[POST PUT PATCH].include?(request.method)
        outgoing.body = request.body.read
        outgoing.content_type = request.content_type if request.content_type
      end

      # Forwarded headers
      outgoing['X-Forwarded-For'] = request.remote_ip
      outgoing['X-Forwarded-Proto'] = request.scheme
      outgoing['X-Forwarded-Host'] = request.host

      # Execute
      upstream = http.request(outgoing)

      # Send response with correct status
      status_code = upstream.code.to_i

      # Build response headers
      skip_response = %w[transfer-encoding connection keep-alive]
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

      # Rewrite HTML to fix root-relative paths
      if content_type.include?('text/html')
        body = rewrite_html(body, @docker_app)
      end

      # Send raw response — let the upstream Content-Type pass through exactly
      self.response_body = body
      self.status = status_code
      response.headers['Content-Type'] = content_type if content_type.present?

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

    # Rewrite root-relative src/href/action attributes
    # /static/... → /app/filebrowser/static/...
    # But don't rewrite if already prefixed or external
    body.gsub(%r{((?:src|href|action)\s*=\s*["'])/(?!app/|https?:|data:|//)}, "\\1#{prefix}/")
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
    cookie.gsub(/[Pp]ath=\/(?!\S)/, "Path=#{prefix}/")
  end
end
