# Amahi Home Server
# Copyright (C) 2007-2013 Amahi

require 'leases'

class NetworkController < ApplicationController
  KIND = Setting::NETWORK
  before_action :admin_required
  before_action :set_page_title
  IP_RANGE = 10

  def index
    @leases = Leases.all
  end

  def hosts
    get_hosts
  end

  def create_host
    @host = Host.create(params_host)
    get_hosts
    respond_to do |format|
      if @host.errors.any?
        format.html { render :hosts, status: :unprocessable_entity }
      else
        format.html { redirect_to network_hosts_path }
      end
      format.json
    end
  end

  def destroy_host
    @host = Host.find(params[:id])
    @host.destroy
    render json: { status: :ok, id: @host.id }
  end

  def dns_aliases
    unless @advanced
      redirect_to network_index_path
    else
      get_dns_aliases
    end
  end

  def create_dns_alias
    @dns_alias = DnsAlias.create(params_create_alias)
    get_dns_aliases
    respond_to do |format|
      if @dns_alias.errors.any?
        format.html { render :dns_aliases, status: :unprocessable_entity }
      else
        format.html { redirect_to network_dns_aliases_path }
      end
      format.json
    end
  end

  def destroy_dns_alias
    @dns_alias = DnsAlias.find(params[:id])
    @dns_alias.destroy
    render json: { status: :ok, id: @dns_alias.id }
  end

  def settings
    unless @advanced
      redirect_to network_index_path
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
    case params[:setting_dns]
    when 'opendns', 'google', 'opennic', 'cloudflare'
      @saved = Setting.set("dns", params[:setting_dns], KIND)
      system("hda-ctl-hup")
    else
      @saved = true
    end
    render json: { status: @saved ? :ok : :not_acceptable }
  end

  def update_dns_ips
    Setting.transaction do
      @ip_1_saved = DnsIpSetting.set("dns_ip_1", params[:dns_ip_1], KIND)
      @ip_2_saved = DnsIpSetting.set("dns_ip_2", params[:dns_ip_2], KIND)
      Setting.set("dns", 'custom', KIND)
      system("hda-ctl-hup")
    end
    if @ip_1_saved && @ip_2_saved
      render json: { status: :ok }
    else
      render json: { status: :not_acceptable, ip_1_saved: @ip_1_saved, ip_2_saved: @ip_2_saved }
    end
  end

  def update_lease_time
    @saved = params[:lease_time].present? && params[:lease_time].to_i > 0 ? Setting.set("lease_time", params[:lease_time], KIND) : false
    render json: { status: @saved ? :ok : :not_acceptable }
    system("hda-ctl-hup")
  end

  def update_gateway
    @saved = params[:gateway].to_i > 0 && params[:gateway].to_i < 255 ? Setting.set("gateway", params[:gateway], KIND) : false
    if @saved
      @net = Setting.get 'net'
      render json: { status: :ok, data: @net + '.' + params[:gateway] }
    else
      render json: { status: :not_acceptable }
    end
  end

  def toggle_setting
    id = params[:id]
    s = Setting.find(id)
    s.value = (1 - s.value.to_i).to_s
    if s.save
      render json: { status: 'ok' }
      system("hda-ctl-hup")
    else
      render json: { status: 'error' }
    end
  end

  def update_dhcp_range
    if params[:id] == "min"
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

  # --- Gateway (dnsmasq DHCP/DNS) ---

  def gateway
    unless @advanced
      redirect_to network_index_path
      return
    end
    @dnsmasq_installed = File.exist?('/usr/sbin/dnsmasq')
    @dnsmasq_running = @dnsmasq_installed && `systemctl is-active dnsmasq 2>/dev/null`.strip == 'active'
    @net = Setting.get('net') || '192.168.1'
    @gateway_ip = Setting.find_or_create_by(KIND, 'gateway', '1').value
    @dnsmasq_dhcp = Setting.find_or_create_by(KIND, 'dnsmasq_dhcp', '1')
    @dnsmasq_dns = Setting.find_or_create_by(KIND, 'dnsmasq_dns', '1')
    @dyn_lo = Setting.find_or_create_by(KIND, 'dyn_lo', '100').value
    @dyn_hi = Setting.find_or_create_by(KIND, 'dyn_hi', '254').value
    @lease_time = Setting.get("lease_time") || "14400"
    @dns = Setting.find_or_create_by(KIND, 'dns', 'opendns')
  end

  def install_dnsmasq
    redirect_to network_gateway_path
  end

  def install_dnsmasq_stream
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

      sse_send.call("Installing dnsmasq...")

      unless Rails.env.production?
        lines = [
          "Updating package lists...",
          "  Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease",
          "Installing dnsmasq...",
          "  Reading package lists...",
          "  Building dependency tree...",
          "  The following NEW packages will be installed:",
          "    dnsmasq dnsmasq-base",
          "  Setting up dnsmasq (2.90-4) ...",
          "Stopping dnsmasq (will not start until configured)...",
          "  Stopped.",
          "",
          "✓ dnsmasq installed successfully!",
          "  Configure DHCP/DNS settings below, then start the service."
        ]
        lines.each do |line|
          sleep 0.3
          sse_send.call(line)
        end
        sse_send.call("success", "done")
      else
        success = true

        steps = [
          { label: "Updating package lists...", cmd: "sudo apt-get update 2>&1" },
          { label: "Installing dnsmasq...", cmd: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq 2>&1" },
        ]

        steps.each do |step|
          sse_send.call(step[:label])
          IO.popen(step[:cmd]) do |io|
            io.each_line { |line| sse_send.call("  #{line.chomp}") }
          end
          unless $?.success?
            sse_send.call("  ✗ Command failed")
            success = false
            break
          end
        end

        if success
          sse_send.call("Stopping dnsmasq (safe until configured)...")
          system("sudo systemctl stop dnsmasq.service 2>/dev/null")
          system("sudo systemctl disable dnsmasq.service 2>/dev/null")
          sse_send.call("  ✓ Stopped and disabled (configure settings, then start)")

          sse_send.call("")
          sse_send.call("✓ dnsmasq installed successfully!")
          sse_send.call("success", "done")
        else
          sse_send.call("✗ Installation failed.")
          sse_send.call("error", "done")
        end
      end
    end
  end

  def start_dnsmasq
    system("sudo systemctl enable dnsmasq.service 2>/dev/null")
    system("sudo systemctl start dnsmasq.service 2>/dev/null")
    redirect_to network_gateway_path
  end

  def stop_dnsmasq
    system("sudo systemctl stop dnsmasq.service 2>/dev/null")
    system("sudo systemctl disable dnsmasq.service 2>/dev/null")
    redirect_to network_gateway_path
  end

  def update_dnsmasq_config
    net = Setting.get('net') || '192.168.1'

    Setting.set("dyn_lo", params[:dyn_lo], KIND) if params[:dyn_lo].present?
    Setting.set("dyn_hi", params[:dyn_hi], KIND) if params[:dyn_hi].present?
    Setting.set("lease_time", params[:lease_time], KIND) if params[:lease_time].present?
    Setting.set("gateway", params[:gateway], KIND) if params[:gateway].present?

    dhcp_enabled = params[:dhcp_enabled] == '1'
    dns_enabled = params[:dns_enabled] == '1'

    dyn_lo = (params[:dyn_lo] || Setting.get("dyn_lo") || "100").to_i
    dyn_hi = (params[:dyn_hi] || Setting.get("dyn_hi") || "254").to_i
    gateway = params[:gateway] || Setting.get("gateway") || "1"
    lease_time = (params[:lease_time] || Setting.get("lease_time") || "14400").to_i

    config_lines = []
    config_lines << "# Amahi-kai dnsmasq configuration"
    config_lines << "# Auto-generated — do not edit manually"
    config_lines << ""

    if dhcp_enabled
      config_lines << "dhcp-range=#{net}.#{dyn_lo},#{net}.#{dyn_hi},#{lease_time}s"
      config_lines << "dhcp-option=option:router,#{net}.#{gateway}"
      config_lines << "dhcp-authoritative"
    end

    if dns_enabled
      config_lines << "local=/#{Setting.get('domain') || 'local'}/"
      config_lines << "expand-hosts"
      config_lines << "domain=#{Setting.get('domain') || 'local'}"
    end

    config_lines << "bind-interfaces"
    config_lines << "except-interface=lo"

    begin
      staged = "/tmp/amahi-staging/dnsmasq-amahi.conf"
      FileUtils.mkdir_p('/tmp/amahi-staging')
      File.write(staged, config_lines.join("\n") + "\n")
      system("sudo cp #{staged} /etc/dnsmasq.d/amahi.conf")

      if `systemctl is-active dnsmasq 2>/dev/null`.strip == 'active'
        system("sudo systemctl restart dnsmasq.service")
      end

      flash[:notice] = "Configuration saved"
      redirect_to network_gateway_path
    rescue StandardError => e
      flash[:alert] = "Failed to save: #{e.message}"
      redirect_to network_gateway_path
    end
  end

  # --- Remote Access (Cloudflare Tunnel) ---

  def remote_access
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
      rescue StandardError => e
        sse_send.call("✗ Installation failed: #{e.message}")
      end
      sse_send.call("", "done")
    end
  end

  def setup_tunnel_stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    token = params[:token].to_s.strip

    self.response_body = Enumerator.new do |yielder|
      sse_send = ->(data, event = nil) {
        msg = ""
        msg += "event: #{event}\n" if event
        msg += "data: #{data}\n\n"
        yielder << msg
      }

      if token.blank?
        sse_send.call("✗ No tunnel token provided")
        sse_send.call("error", "done")
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
          sse_send.call(line)
        end
        sse_send.call("success", "done")
        next
      end

      begin
        unless CloudflareService.installed?
          sse_send.call("Installing cloudflared...")
          CloudflareService.install!
          sse_send.call("✓ cloudflared installed")
        else
          sse_send.call("✓ cloudflared already installed")
        end

        sse_send.call("Configuring tunnel service...")
        CloudflareService.configure!(token)
        sse_send.call("✓ Tunnel service configured")

        sse_send.call("Starting tunnel...")
        CloudflareService.start!
        sleep 2
        if CloudflareService.running?
          sse_send.call("✓ Cloudflare Tunnel is connected!")
        else
          sse_send.call("⚠ Service started but may take a moment to connect")
        end

        sse_send.call("success", "done")
      rescue StandardError => e
        sse_send.call("✗ Error: #{e.message}")
        sse_send.call("error", "done")
      end
    end
  end

  # --- Security ---

  def security
    @checks = SecurityAudit.run_all
    @has_blockers = SecurityAudit.has_blockers?
  end

  def security_audit_stream
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

      sse_send.call("Running security audit...")
      sse_send.call("")

      checks = SecurityAudit.run_all
      passed = 0
      warnings = 0
      blockers = 0
      has_fixable = false

      checks.each do |check|
        sleep 0.4 unless Rails.env.production?
        sleep 0.15 if Rails.env.production?

        sse_send.call("Checking #{check.description.downcase}...")

        case check.status
        when :pass
          passed += 1
          sse_send.call("  ✓ #{check.description}")
        when :warn
          warnings += 1
          sse_send.call("  ⚠ #{check.description} (recommended to fix)")
          has_fixable = true if check.fix_command && check.name != 'admin_password'
        when :fail
          if check.severity == :blocker
            blockers += 1
            sse_send.call("  ✗ #{check.description} (BLOCKER)")
          else
            warnings += 1
            sse_send.call("  ✗ #{check.description}")
          end
          has_fixable = true if check.fix_command && check.name != 'admin_password' && check.name != 'open_ports'
        end

        sse_send.call("")
      end

      sse_send.call("─── Audit Complete ───")
      sse_send.call("✓ #{passed} passed")
      sse_send.call("⚠ #{warnings} warnings") if warnings > 0
      sse_send.call("✗ #{blockers} blocker#{'s' if blockers != 1}") if blockers > 0

      if blockers > 0
        sse_send.call("")
        sse_send.call("✗ Blockers must be fixed before enabling remote access.")
      end

      sse_send.call(has_fixable.to_s, "has_fixable")
      sse_send.call("", "done")
    end
  end

  def security_fix
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
      rescue StandardError => e
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
    @net ||= '192.168.1' if Rails.env.development?
  end

  def get_dns_aliases
    @dns_aliases = DnsAlias.order('name ASC')
    @net = Setting.get 'net'
    @net ||= '192.168.1' if Rails.env.development?
  end

  def params_create_alias
    params.require(:dns_alias).permit(:name, :address)
  end

  def params_host
    params.require(:host).permit(:name, :mac, :address)
  end
end
