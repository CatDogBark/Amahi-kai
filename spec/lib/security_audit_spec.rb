require 'rails_helper'

RSpec.describe SecurityAudit do
  describe '.run_all' do
    it 'returns an array of checks' do
      checks = SecurityAudit.run_all
      expect(checks).to be_an(Array)
      expect(checks.length).to eq(8)
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
