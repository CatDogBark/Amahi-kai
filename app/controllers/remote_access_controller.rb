# Amahi Home Server — Remote Access (Cloudflare Tunnel + Tailscale)
# Split from NetworkController for maintainability.
#
# The tunnel exposes the NAS to the Internet, so it can't be set up or started while the
# security audit has blockers (stopping it is always allowed).

require 'tailscale_service'

class RemoteAccessController < ApplicationController
  include SseStreaming

  before_action :admin_required
  before_action :require_no_security_blockers, only: %i[start_tunnel restart_tunnel stage_tunnel_token]

  def index
    @page_title = t('network')
    @tunnel_status = CloudflareService.status
    @tailscale_status = TailscaleService.status
    @security_blockers = SecurityAudit.blockers
  end

  # --- Cloudflare Tunnel ---

  def start_tunnel
    tunnel_action(CloudflareService.start!, 'start', 'Tunnel started')
  end

  def restart_tunnel
    tunnel_action(CloudflareService.restart!, 'restart', 'Tunnel restarted')
  end

  def stop_tunnel
    tunnel_action(CloudflareService.stop!, 'stop', 'Tunnel stopped')
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
    blockers = SecurityAudit.blockers

    stream_sse do |sse|
      if blockers.any?
        sse.emit("✗ #{blocker_message(blockers)}")
        sse.done("error")
        next
      end

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
        if CloudflareService.installed?
          sse.emit("✓ cloudflared already installed")
        else
          sse.emit("Installing cloudflared...")
          CloudflareService.install! { |line| sse.emit("  #{line}") }
          sse.emit("✓ cloudflared installed")
        end

        sse.emit("Configuring and starting the tunnel...")
        CloudflareService.configure!(token)
        sse.emit("✓ Tunnel service configured")

        sleep 2
        if CloudflareService.running?
          sse.emit("✓ Cloudflare Tunnel is connected!")
        else
          sse.emit("⚠ Service started but may take a moment to connect")
        end

        sse.done
      rescue CloudflareService::CloudflareError => e
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
        sse.emit("Adding Tailscale's apt repository and installing...")
        TailscaleService.install! { |line| sse.emit("  #{line}") }
        sse.emit("✓ Tailscale installed")

        sse.emit("")
        sse.emit("Starting Tailscale...")
        result = TailscaleService.start! { |line| sse.emit("  #{line}") }
        raise TailscaleService::TailscaleError, result[:error] unless result[:success]

        if result[:auth_url]
          sse.emit("")
          sse.emit("✓ Open the link above to connect this device to your Tailnet.")
          sse.emit(result[:auth_url], event: "auth_url")
        elsif TailscaleService.running?
          sse.emit("✓ Tailscale is already authenticated and running!")
        else
          sse.emit("⚠ Tailscale started but may need authentication. Check `tailscale status`.")
        end

        sse.done
      rescue TailscaleService::TailscaleError => e
        sse.emit("✗ Error: #{e.message}")
        sse.done("error")
      end
    end
  end

  def start_tailscale
    result = TailscaleService.start!
    render json: { status: result[:success] ? :ok : :error, auth_url: result[:auth_url], error: result[:error] }.compact
  end

  def stop_tailscale
    TailscaleService.stop!
    render json: { status: :ok }
  end

  def logout_tailscale
    TailscaleService.logout!
    render json: { status: :ok }
  end

  private

  def require_no_security_blockers
    blockers = SecurityAudit.blockers
    return if blockers.empty?
    render json: { status: :error, error: blocker_message(blockers) }, status: :forbidden
  end

  def blocker_message(blockers)
    "Fix the security audit's blockers first (Network → Security): #{blockers.map(&:description).join('; ')}"
  end

  # The page reloads after the request; the flash shows the result there as a toast.
  def tunnel_action(ok, action, done)
    if ok
      flash[:notice] = done
      render json: { status: :ok }
    else
      render json: { status: :error, error: "The tunnel didn't #{action}; see the log for details" }, status: :unprocessable_entity
    end
  end
end
