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
end
