# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#

require 'leases'

class NetworkController < ApplicationController
  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :set_page_title
  IP_RANGE = 10

  def index
    @leases = use_sample_data? ? SampleData.load('leases') : Leases.all
  end

  def hosts
    get_hosts
  end

  def create_host
    sleep 2 if development?
    @host = Host.create(params_host)
    get_hosts
    respond_to do |format|
      if @host.errors.any?
        format.html { render :hosts, status: :unprocessable_entity }
      else
        format.html { redirect_to "/tab/network/hosts" }
      end
      format.json
    end
  end

  def destroy_host
    sleep 2 if development?
    @host = Host.find params[:id]
    @host.destroy
    render json: {:status=>:ok,id: @host.id }
  end

  def dns_aliases
    unless @advanced
      redirect_to network_engine_path
    else
      get_dns_aliases
    end
  end

  def create_dns_alias
    sleep 2 if development?
    @dns_alias = DnsAlias.create(params_create_alias)
    get_dns_aliases
    respond_to do |format|
      if @dns_alias.errors.any?
        format.html { render :dns_aliases, status: :unprocessable_entity }
      else
        format.html { redirect_to "/tab/network/dns_aliases" }
      end
      format.json
    end
  end

  def destroy_dns_alias
    sleep 2 if development?
    @dns_alias = DnsAlias.find params[:id]
    @dns_alias.destroy
    render json: { :status=>:ok, id: @dns_alias.id }
  end

  def settings
    unless @advanced
      redirect_to network_engine_path
    else
      @net = Setting.get 'net'
      @dns = Setting.find_or_create_by(KIND, 'dns', 'opendns')
      @dns_ip_1, @dns_ip_2 = DnsIpSetting.custom_dns_ips
      @dnsmasq_dhcp = Setting.find_or_create_by(KIND, 'dnsmasq_dhcp', '1')
      @dnsmasq_dns = Setting.find_or_create_by(KIND, 'dnsmasq_dns', '1')
      @lease_time = Setting.get("lease_time") || "14400"
      @gateway = Setting.find_or_create_by(KIND, 'gateway', '1').value
      @dyn_lo = Setting.find_or_create_by(KIND, 'dyn_lo', '100').value
      @dyn_hi = Setting.find_or_create_by(KIND, 'dyn_hi', '254').value
    end
  end

  def update_dns
    sleep 2 if development?
    case params[:setting_dns]
    when 'opendns', 'google', 'opennic', 'cloudflare'
      @saved = Setting.set("dns", params[:setting_dns], KIND)
      system("hda-ctl-hup")
    else
      @saved = true
    end
    render :json => { :status => @saved ? :ok : :not_acceptable }
  end

  def update_dns_ips
    sleep 2 if development?
    Setting.transaction do
      @ip_1_saved = DnsIpSetting.set("dns_ip_1", params[:dns_ip_1], KIND)
      @ip_2_saved = DnsIpSetting.set("dns_ip_2", params[:dns_ip_2], KIND)
      Setting.set("dns", 'custom', KIND)
      system("hda-ctl-hup")
    end
    if @ip_1_saved && @ip_2_saved
      render json: {status: :ok}
    else
      render json: {status: :not_acceptable, ip_1_saved: @ip_1_saved, ip_2_saved: @ip_2_saved}
    end
  end

  def update_lease_time
    sleep 2 if development?
    @saved = params[:lease_time].present? && params[:lease_time].to_i > 0 ? Setting.set("lease_time", params[:lease_time], KIND) : false
    render :json => { :status => @saved ? :ok : :not_acceptable }
    system("hda-ctl-hup")
  end

  def update_gateway
    sleep 2 if development?
    @saved = params[:gateway].to_i > 0 && params[:gateway].to_i < 255 ? Setting.set("gateway", params[:gateway], KIND) : false
    if @saved
      @net = Setting.get 'net'
      render json: { status: :ok, data: @net + '.' + params[:gateway] }
    else
      render json: { status: :not_acceptable }
    end
  end

  def toggle_setting
		sleep 2 if development?
		id = params[:id]
		s = Setting.find id
		s.value = (1 - s.value.to_i).to_s
		if s.save
			render json: { status: 'ok' }
			system("hda-ctl-hup")
		else
			render json: { status: 'error' }
		end
  end

  def update_dhcp_range
    if(params[:id] == "min")
      dyn_lo = params[:dyn_lo].to_i
      dyn_hi = Setting.find_by_name("dyn_hi").value.to_i
    else
      dyn_lo = Setting.find_by_name("dyn_lo").value.to_i
      dyn_hi = params[:dyn_hi].to_i
    end
    @saved = dyn_lo > 0 && dyn_hi < 255 && dyn_hi - dyn_lo > IP_RANGE
    if @saved
      Setting.set("dyn_lo", dyn_lo, KIND)
      Setting.set("dyn_hi", dyn_hi, KIND)
      system("hda-ctl-hup")
      render json: { status: :ok }
    else
      render json: { status: :not_acceptable }
    end
  end

  # --- Remote Access (Cloudflare Tunnel) ---

  def remote_access
    @tunnel_status = CloudflareService.status
    @security_blockers = SecurityAudit.blockers
  end

  def configure_tunnel
    sleep 2 if development?
    token = params[:tunnel_token].to_s.strip
    if token.blank?
      render json: { status: :not_acceptable, error: 'Token is required' }
      return
    end
    begin
      CloudflareService.configure!(token)
      CloudflareService.start!
      render json: { status: :ok }
    rescue => e
      render json: { status: :error, error: e.message }
    end
  end

  def start_tunnel
    sleep 1 if development?
    CloudflareService.start!
    render json: { status: :ok }
  end

  def stop_tunnel
    sleep 1 if development?
    CloudflareService.stop!
    render json: { status: :ok }
  end

  def install_cloudflared_stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    self.response_body = Enumerator.new do |yielder|
      sse_send = ->(data, event = nil) {
        msg = ""
        msg += "event: #{event}\n" if event
        msg += "data: #{data}\n\n"
        yielder << msg
      }

      sse_send.call("Starting cloudflared installation...")

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
          sse_send.call(line)
        end
        sse_send.call("", "done")
        next
      end

      begin
        CloudflareService.install!
        sse_send.call("✓ cloudflared installed successfully!")
      rescue => e
        sse_send.call("✗ Installation failed: #{e.message}")
      end
      sse_send.call("", "done")
    end
  end

  # --- Security ---

  def security
    @checks = SecurityAudit.run_all
    @has_blockers = SecurityAudit.has_blockers?
  end

  def security_fix
    sleep 1 if development?
    check_name = params[:check_name].to_s
    result = SecurityAudit.fix!(check_name)
    render json: { status: result ? :ok : :error, check: check_name }
  end

  def security_fix_stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    self.response_body = Enumerator.new do |yielder|
      sse_send = ->(data, event = nil) {
        msg = ""
        msg += "event: #{event}\n" if event
        msg += "data: #{data}\n\n"
        yielder << msg
      }

      sse_send.call("Starting security fixes...")

      unless Rails.env.production?
        lines = [
          "Enabling UFW firewall...",
          "  Default incoming policy changed to 'deny'",
          "  Rule added: allow 22/tcp",
          "  Rule added: allow 3000/tcp",
          "  Firewall is active and enabled on system startup",
          "✓ UFW firewall enabled",
          "",
          "Hardening SSH configuration...",
          "  Setting PermitRootLogin no",
          "  Setting PasswordAuthentication no",
          "  Restarting sshd...",
          "✓ SSH hardened",
          "",
          "Installing fail2ban...",
          "  Reading package lists...",
          "  Setting up fail2ban...",
          "✓ Fail2ban installed",
          "",
          "Installing unattended-upgrades...",
          "  Setting up unattended-upgrades...",
          "✓ Automatic security updates enabled",
          "",
          "Configuring Samba LAN binding...",
          "  Adding interface binding to smb.conf",
          "  Restarting smbd...",
          "✓ Samba bound to LAN only",
          "",
          "✓ All security fixes applied!"
        ]
        lines.each do |line|
          sleep 0.2
          sse_send.call(line)
        end
        sse_send.call("", "done")
        next
      end

      begin
        results = SecurityAudit.fix_all!
        results.each do |r|
          if r[:fixed]
            sse_send.call("✓ Fixed: #{r[:name]}")
          else
            sse_send.call("✗ Failed to fix: #{r[:name]}")
          end
        end
        sse_send.call("✓ Security fix-all complete!")
      rescue => e
        sse_send.call("✗ Error: #{e.message}")
      end
      sse_send.call("", "done")
    end
  end

private
  def set_page_title
    @page_title = t('network')
  end

  def get_hosts
    @hosts = Host.order('name ASC')
    @net = Setting.get 'net'
    # for development ease
    @net ||= '192.168.1' if Rails.env.development?
  end

  def get_dns_aliases
    @dns_aliases = DnsAlias.order('name ASC')
    @net = Setting.get 'net'
    # for development ease
    @net ||= '192.168.1' if Rails.env.development?
  end

  def params_create_alias
    params.require(:dns_alias).permit([:name, :address])
  end

  def params_host
    params.require(:host).permit(:name, :mac, :address)
  end

  def params_create_alias    
    params.require(:dns_alias).permit([:name, :address])
  end

  def params_host
    params.require(:host).permit(:name, :mac, :address)
  end
end
