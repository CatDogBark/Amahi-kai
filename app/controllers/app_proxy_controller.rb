require 'net/http'
require 'uri'

class AppProxyController < ApplicationController
  before_action :admin_required
  before_action :find_app

  # Proxy all requests to the Docker app's local port
  def proxy
    unless @docker_app.status == 'running' && @docker_app.host_port.present?
      render plain: "App is not running", status: :service_unavailable
      return
    end

    target_port = @docker_app.host_port
    # Build the proxied path (strip our prefix)
    proxy_path = params[:path].to_s
    proxy_path = "/#{proxy_path}" unless proxy_path.start_with?('/')
    query = request.query_string.present? ? "?#{request.query_string}" : ""

    target_uri = URI("http://127.0.0.1:#{target_port}#{proxy_path}#{query}")

    begin
      # Build the outgoing request
      http = Net::HTTP.new(target_uri.host, target_uri.port)
      http.open_timeout = 5
      http.read_timeout = 30

      # Map the incoming request method
      outgoing = case request.method
      when 'GET'    then Net::HTTP::Get.new(target_uri)
      when 'POST'   then Net::HTTP::Post.new(target_uri)
      when 'PUT'    then Net::HTTP::Put.new(target_uri)
      when 'PATCH'  then Net::HTTP::Patch.new(target_uri)
      when 'DELETE' then Net::HTTP::Delete.new(target_uri)
      when 'HEAD'   then Net::HTTP::Head.new(target_uri)
      when 'OPTIONS' then Net::HTTP::Options.new(target_uri)
      else
        render plain: "Method not supported", status: :method_not_allowed
        return
      end

      # Forward headers (skip hop-by-hop headers)
      skip_headers = %w[host connection transfer-encoding keep-alive upgrade proxy-authorization te trailer]
      request.headers.each do |key, value|
        next unless key.start_with?('HTTP_')
        header_name = key.sub('HTTP_', '').tr('_', '-').downcase
        next if skip_headers.include?(header_name)
        outgoing[header_name] = value
      end

      # Forward content type and body for POST/PUT/PATCH
      if %w[POST PUT PATCH].include?(request.method)
        outgoing.body = request.body.read
        outgoing.content_type = request.content_type if request.content_type
      end

      # Set forwarded headers
      outgoing['X-Forwarded-For'] = request.remote_ip
      outgoing['X-Forwarded-Proto'] = request.scheme
      outgoing['X-Forwarded-Host'] = request.host

      # Execute the request
      upstream = http.request(outgoing)

      # Map response status
      response.status = upstream.code.to_i

      # Forward response headers (skip hop-by-hop)
      skip_response = %w[transfer-encoding connection keep-alive]
      upstream.each_header do |name, value|
        next if skip_response.include?(name.downcase)

        # Rewrite Location headers to go through our proxy
        if name.downcase == 'location'
          value = rewrite_location(value, @docker_app)
        end

        # Rewrite Set-Cookie paths
        if name.downcase == 'set-cookie'
          value = rewrite_cookie_path(value, @docker_app)
        end

        response.headers[name] = value
      end

      # Send body
      content_type = upstream['content-type'].to_s

      # Rewrite HTML content to fix absolute URLs
      if content_type.include?('text/html')
        body = rewrite_html(upstream.body.to_s, @docker_app)
        render html: body.html_safe, status: response.status, layout: false
      else
        send_data upstream.body, type: content_type, disposition: 'inline', status: response.status
      end

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

  # Rewrite absolute URLs in HTML to go through our proxy
  def rewrite_html(body, app)
    prefix = "/app/#{app.identifier}"
    port = app.host_port

    # Rewrite absolute URLs pointing to the app's port
    body = body.gsub(%r{(["'])(https?://)(localhost|127\.0\.0\.1|0\.0\.0\.0):#{port}(/[^"']*)?}, "\\1#{prefix}\\4")

    # Rewrite root-relative URLs (src="/...", href="/...")
    # Be careful not to rewrite data URIs, protocol-relative URLs, or already-proxied paths
    body = body.gsub(%r{((?:src|href|action)\s*=\s*["'])/(?!(?:app/|https?:|data:|//))}, "\\1#{prefix}/")

    body
  end

  # Rewrite Location redirect headers
  def rewrite_location(location, app)
    prefix = "/app/#{app.identifier}"
    port = app.host_port

    if location =~ %r{^https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0):#{port}(.*)}
      "#{prefix}#{$1}"
    elsif location.start_with?('/')
      "#{prefix}#{location}"
    else
      location
    end
  end

  # Rewrite cookie paths
  def rewrite_cookie_path(cookie, app)
    prefix = "/app/#{app.identifier}"
    cookie.gsub(/[Pp]ath=\//, "Path=#{prefix}/")
  end
end
