# Amahi Home Server — Remote Access (Cloudflare Tunnel + Tailscale)
# Split from NetworkController for maintainability.

require 'shell'
require 'tailscale_service'

class RemoteAccessController < ApplicationController
  include SseStreaming

  before_action :admin_required

  def index
    @page_title = t('network')
    @tunnel_status = CloudflareService.status
    @tailscale_status = TailscaleService.status
    @security_blockers = SecurityAudit.blockers
  end

  # --- Cloudflare Tunnel ---

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
    rescue Shell::CommandError, Errno::ENOENT, Errno::EACCES, IOError => e
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
      sse.emit("Starting cloudflared installation...")

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
          sse.emit(line)
        end
        sse.emit("", event: "done")
        next
      end

      begin
        CloudflareService.install!
        sse.emit("✓ cloudflared installed successfully!")
      rescue CloudflareService::CloudflareError, Shell::CommandError => e
        sse.emit("✗ Installation failed: #{e.message}")
      end
      sse.emit("", event: "done")
    end
  end

  # POST: the page sends the token here first, then opens setup_tunnel_stream.
  def stage_tunnel_token
    token = params[:token].to_s.strip
    if token.blank?
      render json: { status: :not_acceptable, error: 'Token is required' }, status: :unprocessable_entity
      return
    end
    CloudflareService.stage_token(token)
    render json: { status: :ok }
  end

  def setup_tunnel_stream
    token = CloudflareService.take_staged_token.to_s

    stream_sse do |sse|
      if token.blank?
        sse.emit("✗ No tunnel token provided")
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
          sse.emit(line)
        end
        sse.done
        next
      end

      begin
        unless CloudflareService.installed?
          sse.emit("Installing cloudflared...")
          CloudflareService.install!
          sse.emit("✓ cloudflared installed")
        else
          sse.emit("✓ cloudflared already installed")
        end

        sse.emit("Configuring tunnel service...")
        CloudflareService.configure!(token)
        sse.emit("✓ Tunnel service configured")

        sse.emit("Starting tunnel...")
        CloudflareService.start!
        sleep 2
        if CloudflareService.running?
          sse.emit("✓ Cloudflare Tunnel is connected!")
        else
          sse.emit("⚠ Service started but may take a moment to connect")
        end

        sse.done
      rescue CloudflareService::CloudflareError, Shell::CommandError, Errno::ENOENT => e
        sse.emit("✗ Error: #{e.message}")
        sse.done("error")
      end
    end
  end

  # --- Tailscale VPN ---

  def install_tailscale_stream
    stream_sse do |sse|
      sse.emit("Installing Tailscale...")

      unless Rails.env.production?
        lines = [
          "Downloading Tailscale install script...",
          "  Adding Tailscale apt repository...",
          "  Downloading signing key...",
          "Updating package lists...",
          "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
          "  Get:2 https://pkgs.tailscale.com/stable/ubuntu noble InRelease",
          "Installing tailscale...",
          "  Reading package lists...",
          "  Setting up tailscale (1.78.1) ...",
          "  Starting tailscaled...",
          "✓ Tailscale installed successfully!",
          "",
          "Starting Tailscale...",
          "  To authenticate, visit:",
          "  https://login.tailscale.com/a/abc123example",
          "",
          "✓ Open the link above to connect this device to your Tailnet."
        ]
        lines.each do |line|
          sleep 0.3
          sse.emit(line)
        end
        sse.emit("https://login.tailscale.com/a/abc123example", event: "auth_url")
        sse.done
        next
      end

      begin
        # Install
        sse.emit("Downloading Tailscale install script...")
        script_path = '/tmp/tailscale-install.sh'
        system("curl -fsSL https://tailscale.com/install.sh -o #{script_path} 2>&1")
        unless $?.success? && File.exist?(script_path)
          sse.emit("✗ Failed to download install script")
          sse.done("error")
          next
        end

        sse.emit("Installing Tailscale...")
        IO.popen("sudo bash #{script_path} 2>&1") do |io|
          io.each_line { |line| sse.emit("  #{line.chomp}") }
        end
        FileUtils.rm_f(script_path)
        unless $?.success?
          sse.emit("✗ Installation failed")
          sse.done("error")
          next
        end
        sse.emit("✓ Tailscale installed")

        # Start and get auth URL
        sse.emit("")
        sse.emit("Starting Tailscale...")
        Shell.run("systemctl enable tailscaled 2>/dev/null")
        Shell.run("systemctl start tailscaled 2>/dev/null")

        # `tailscale up` blocks waiting for auth — run with timeout and capture URL
        auth_url = nil
        IO.popen("sudo timeout 10 tailscale up 2>&1") do |io|
          io.each_line do |line|
            sse.emit("  #{line.chomp}")
            url = line[/https:\/\/login\.tailscale\.com\/[^\s]+/]
            auth_url = url if url
          end
        end

        if auth_url
          sse.emit("")
          sse.emit("✓ Open the link above to connect this device to your Tailnet.")
          sse.emit(auth_url, event: "auth_url")
        elsif TailscaleService.running?
          sse.emit("✓ Tailscale is already authenticated and running!")
        else
          sse.emit("⚠ Tailscale started but may need authentication. Check `tailscale status`.")
        end

        sse.done
      rescue Shell::CommandError, Errno::ENOENT, IOError => e
        sse.emit("✗ Error: #{e.message}")
        sse.done("error")
      end
    end
  end

  def start_tailscale
    result = TailscaleService.start!
    render json: { status: result[:success] ? :ok : :error, auth_url: result[:auth_url] }
  end

  def stop_tailscale
    TailscaleService.stop!
    render json: { status: :ok }
  end

  def logout_tailscale
    TailscaleService.logout!
    render json: { status: :ok }
  end
end
