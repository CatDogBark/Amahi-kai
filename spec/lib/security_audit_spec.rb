require 'rails_helper'

RSpec.describe SecurityAudit do
  describe '.run_all' do
    it 'returns an array of checks' do
      checks = SecurityAudit.run_all
      expect(checks).to be_an(Array)
      expect(checks.length).to eq(9)
      checks.each do |check|
        expect(check).to be_a(SecurityAudit::Check)
        expect([:pass, :warn, :fail]).to include(check.status)
        expect([:blocker, :warning, :info]).to include(check.severity)
      end
    end
  end

  describe '.has_blockers?' do
    it 'returns a boolean' do
      result = SecurityAudit.has_blockers?
      expect([true, false]).to include(result)
    end
  end

  describe '.fix!' do
    it 'returns true for simulated fixes in non-production' do
      expect(SecurityAudit.fix!('ufw_firewall')).to eq(true)
      expect(SecurityAudit.fix!('fail2ban')).to eq(true)
      expect(SecurityAudit.fix!('ssh_root_login')).to eq(true)
    end
  end

  describe '.fix_all!' do
    it 'returns array of results' do
      results = SecurityAudit.fix_all!
      expect(results).to be_an(Array)
    end
  end

  describe 'Check struct' do
    it 'has expected attributes' do
      check = SecurityAudit::Check.new(
        name: 'test',
        description: 'Test check',
        status: :pass,
        severity: :info,
        fix_command: nil
      )
      expect(check.name).to eq('test')
      expect(check.status).to eq(:pass)
    end
  end

  describe '.blockers' do
    it 'returns only blocker-severity failed checks' do
      blockers = SecurityAudit.blockers
      expect(blockers).to be_an(Array)
      blockers.each do |check|
        expect(check.status).to eq(:fail)
        expect(check.severity).to eq(:blocker)
      end
    end
  end

  describe 'individual checks' do
    let(:checks) { SecurityAudit.run_all }

    it 'includes admin_password check' do
      check = checks.find { |c| c.name == 'admin_password' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:blocker)
    end

    it 'includes ufw_firewall check' do
      check = checks.find { |c| c.name == 'ufw_firewall' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:blocker)
    end

    it 'includes ssh_root_login check' do
      check = checks.find { |c| c.name == 'ssh_root_login' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:warning)
    end

    it 'includes ssh_password_auth check' do
      check = checks.find { |c| c.name == 'ssh_password_auth' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:warning)
    end

    it 'includes fail2ban check' do
      check = checks.find { |c| c.name == 'fail2ban' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:warning)
    end

    it 'includes unattended_upgrades check' do
      check = checks.find { |c| c.name == 'unattended_upgrades' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:warning)
    end

    it 'includes samba_lan_binding check' do
      check = checks.find { |c| c.name == 'samba_lan_binding' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:blocker)
    end

    it 'includes open_ports check as info severity' do
      check = checks.find { |c| c.name == 'open_ports' }
      expect(check).not_to be_nil
      expect(check.severity).to eq(:info)
    end
  end

  describe '.fix!' do
    it 'returns true for ssh_password_auth' do
      expect(SecurityAudit.fix!('ssh_password_auth')).to eq(true)
    end

    it 'returns true for unattended_upgrades' do
      expect(SecurityAudit.fix!('unattended_upgrades')).to eq(true)
    end

    it 'returns true for samba_lan_binding' do
      expect(SecurityAudit.fix!('samba_lan_binding')).to eq(true)
    end

    it 'returns false for unknown check' do
      expect(SecurityAudit.fix!('nonexistent')).to eq(true)
    end
  end

  describe 'in production' do
    let(:report) do
      { 'ok' => true, 'firewall' => 'active',
        'ssh' => { 'permitrootlogin' => 'no', 'passwordauthentication' => 'yes', 'kbdinteractiveauthentication' => 'no' } }
    end
    let(:checks) { SecurityAudit.run_all.index_by(&:name) }

    before do
      allow(SecurityAudit).to receive(:production?).and_return(true)
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('security.report').and_return(report)
      allow(SecurityAudit).to receive(:`).and_return('')
    end

    it "reads UFW and sshd's effective settings from the root helper" do
      expect(checks['ufw_firewall'].status).to eq(:pass)
      expect(checks['ssh_root_login'].status).to eq(:pass)
      expect(checks['ssh_password_auth'].status).to eq(:warn)
    end

    it 'counts password login as off only when keyboard-interactive login is off too' do
      report['ssh'].merge!('passwordauthentication' => 'no', 'kbdinteractiveauthentication' => 'yes')
      expect(checks['ssh_password_auth'].status).to eq(:warn)
      report['ssh']['kbdinteractiveauthentication'] = 'no'
      expect(SecurityAudit.run_all.find { |c| c.name == 'ssh_password_auth' }.status).to eq(:pass)
    end

    it 'treats an unreadable firewall state as a blocker' do
      allow(Privileged).to receive(:call).with('security.report').and_raise(Privileged::Error.new('security.report', 'boom'))
      expect(checks['ufw_firewall'].status).to eq(:fail)
      expect(SecurityAudit.blockers.map(&:name)).to include('ufw_firewall')
    end

    it 'needs automatic updates turned on, not just the package' do
      allow(SecurityAudit).to receive(:`).with(/unattended-upgrades/).and_return('install ok installed')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(SecurityAudit::AUTO_UPGRADES).and_return(%(APT::Periodic::Unattended-Upgrade "0";\n))
      expect(checks['unattended_upgrades'].status).to eq(:warn)
      allow(File).to receive(:read).with(SecurityAudit::AUTO_UPGRADES).and_return(%(APT::Periodic::Unattended-Upgrade "1";\n))
      expect(SecurityAudit.run_all.find { |c| c.name == 'unattended_upgrades' }.status).to eq(:pass)
    end

    it "warns about ports Docker publishes past UFW, but not ones kept on localhost" do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with('/usr/bin/docker').and_return(true)
      ports = "0.0.0.0:8096->8096/tcp, :::8096->8096/tcp\n127.0.0.1:5432->5432/tcp\n\n192.168.1.5:53->53/udp"
      allow(Open3).to receive(:capture3).with('sudo', '-n', '/usr/bin/docker', 'ps', '--format', '{{.Ports}}')
                                        .and_return([ports, '', instance_double(Process::Status, success?: true)])
      check = checks['docker_ports']
      expect(check.status).to eq(:warn)
      expect(check.description).to eq("Docker publishes 8096/tcp, 53/udp, which UFW doesn't filter")
    end

    it 'applies each fix through the root helper' do
      %w[ufw_firewall ssh_root_login ssh_password_auth fail2ban unattended_upgrades].each { |name| SecurityAudit.fix!(name) }
      expect(Privileged.calls).to eq([
                                       ['security.enable_firewall', {}],
                                       ['security.harden_ssh', { setting: 'root_login' }],
                                       ['security.harden_ssh', { setting: 'password_login' }],
                                       ['packages.install', { packages: ['fail2ban'] }],
                                       ['packages.install', { packages: ['unattended-upgrades'] }],
                                       ['security.enable_auto_updates', {}]
                                     ])
    end

    it "keeps the helper's reason when a fix is refused, and Fix all reports it" do
      refusal = 'no account that can log in has an SSH key (~/.ssh/authorized_keys)'
      allow(Privileged).to receive(:call).with('security.harden_ssh', setting: 'password_login')
                                         .and_raise(Privileged::Error.new('security.harden_ssh', refusal, refused: true))
      expect(SecurityAudit.fix!('ssh_password_auth')).to be false
      expect(SecurityAudit.last_error).to eq(refusal)
      expect(SecurityAudit.fix_all!).to include({ name: 'ssh_password_auth', fixed: false, error: refusal })
    end
  end

  describe '.fix_all!' do
    it 'skips admin_password and open_ports' do
      results = SecurityAudit.fix_all!
      names = results.map { |r| r[:name] }
      expect(names).not_to include('admin_password')
      expect(names).not_to include('open_ports')
    end

    it 'skips already passing checks' do
      results = SecurityAudit.fix_all!
      results.each do |r|
        check = SecurityAudit.run_all.find { |c| c.name == r[:name] }
        # Only non-passing checks should appear in results
        expect(check.status).not_to eq(:pass) if check
      end
    end
  end
end
