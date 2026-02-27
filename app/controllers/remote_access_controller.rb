# Amahi Home Server — Remote Access (Cloudflare Tunnel)
# Split from NetworkController for maintainability.

require 'shell'

class RemoteAccessController < ApplicationController
  include SseStreaming

  before_action :admin_required

  def index
    @page_title = t('network')
    @tunnel_status = CloudflareService.status
    @security_blockers = SecurityAudit.blockers
  end

  def configure_tunnel
    token = params[:tunnel_token].to_s.strip
    if token.blank?
      render json: { status: :not_acceptable, error: 'Token is required' }
      return
    end
    begin
      CloudflareService.configure!(token)
      CloudflareService.start!
      render json: { status: :ok }
    rescue StandardError => e
      render json: { status: :error, error: e.message }
    end
  end

  def start_tunnel
    CloudflareService.start!
    render json: { status: :ok }
  end

  def stop_tunnel
    CloudflareService.stop!
    render json: { status: :ok }
  end

  def install_cloudflared_stream
    stream_sse do |sse|
      sse.send("Starting cloudflared installation...")

      unless Rails.env.production?
        lines = [
          "Adding Cloudflare apt repository...",
          "  Downloading signing key...",
          "  Adding source list...",
          "Updating package lists...",
          "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
          "  Get:2 https://pkg.cloudflare.com/cloudflared any InRelease",
          "  Fetched 8.2 kB in 1s (6,100 B/s)",
          "Installing cloudflared...",
          "  Reading package lists...",
          "  Building dependency tree...",
          "  The following NEW packages will be installed:",
          "    cloudflared",
          "  Setting up cloudflared (2024.12.1) ...",
          "✓ cloudflared installed successfully!"
        ]
        lines.each do |line|
          sleep 0.3
          sse.send(line)
        end
        sse.send("", event: "done")
        next
      end

      begin
        CloudflareService.install!
        sse.send("✓ cloudflared installed successfully!")
      rescue StandardError => e
        sse.send("✗ Installation failed: #{e.message}")
      end
      sse.send("", event: "done")
    end
  end

  def setup_tunnel_stream
    token = params[:token].to_s.strip

    stream_sse do |sse|
      if token.blank?
        sse.send("✗ No tunnel token provided")
        sse.done("error")
        next
      end

      unless Rails.env.production?
        lines = [
          "Installing cloudflared...",
          "  Adding Cloudflare apt repository...",
          "  Downloading signing key...",
          "  Updating package lists...",
          "  Setting up cloudflared (2024.12.1) ...",
          "✓ cloudflared installed",
          "",
          "Configuring tunnel service...",
          "  Saving tunnel token...",
          "  Removing old service (if any)...",
          "  Registering cloudflared service...",
          "✓ Tunnel service configured",
          "",
          "Starting tunnel...",
          "✓ Cloudflare Tunnel is connected!"
        ]
        lines.each do |line|
          sleep 0.3
          sse.send(line)
        end
        sse.done
        next
      end

      begin
        unless CloudflareService.installed?
          sse.send("Installing cloudflared...")
          CloudflareService.install!
          sse.send("✓ cloudflared installed")
        else
          sse.send("✓ cloudflared already installed")
        end

        sse.send("Configuring tunnel service...")
        CloudflareService.configure!(token)
        sse.send("✓ Tunnel service configured")

        sse.send("Starting tunnel...")
        CloudflareService.start!
        sleep 2
        if CloudflareService.running?
          sse.send("✓ Cloudflare Tunnel is connected!")
        else
          sse.send("⚠ Service started but may take a moment to connect")
        end

        sse.done
      rescue StandardError => e
        sse.send("✗ Error: #{e.message}")
        sse.done("error")
      end
    end
  end
end
