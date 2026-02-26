require 'rails_helper'

RSpec.describe SambaService do
  let(:command_instance) { instance_double(Command, submit: nil, execute: nil) }

  before do
    create(:admin)
    create(:setting, name: 'net', value: '192.168.1')
    create(:setting, name: 'self-address', value: '100')
    create(:setting, name: 'domain', value: 'example.local')
    Setting.find_or_create_by!(name: 'workgroup', kind: Setting::GENERAL) { |s| s.value = 'WORKGROUP' }
    Setting.find_or_create_by!(name: 'pdc', kind: Setting::SHARES) { |s| s.value = '0' }
    Setting.find_or_create_by!(name: 'debug', kind: Setting::SHARES) { |s| s.value = '0' }

    allow(Command).to receive(:new).and_return(command_instance)
    allow(Platform).to receive(:reload)
    allow(TempCache).to receive(:unique_filename).and_return('/tmp/test_samba_conf')
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).with('/tmp/test_samba_conf', 'w').and_yield(StringIO.new)
    allow(Share).to receive(:push_shares)
  end

  describe '.push_config' do
    it 'writes smb.conf and lmhosts then reloads nmb' do
      create(:share, name: 'TestShare')

      described_class.push_config

      # Should have written two files (smb.conf + lmhosts) and reloaded
      expect(command_instance).to have_received(:submit).with(/cp.*\/etc\/samba\/smb.conf/).at_least(:once)
      expect(command_instance).to have_received(:submit).with(/cp.*\/etc\/samba\/lmhosts/).at_least(:once)
      expect(Platform).to have_received(:reload).with(:nmb)
    end

    it 'creates debug backups when debug is enabled' do
      Setting.find_by(name: 'debug', kind: Setting::SHARES).update!(value: '1')
      create(:share, name: 'DebugShare')

      described_class.push_config

      expect(command_instance).to have_received(:submit).with(/cp \/etc\/samba\/smb.conf.*\/tmp\/smb.conf/)
    end

    it 'does not create debug backups when debug is disabled' do
      create(:share, name: 'NoDebug')

      described_class.push_config

      expect(command_instance).not_to have_received(:submit).with(/cp \/etc\/samba\/smb.conf.*\/tmp\/smb.conf/)
    end
  end

  describe '.write_smb_conf' do
    it 'writes content to temp file and copies to /etc/samba/smb.conf' do
      described_class.write_smb_conf('test content')

      expect(command_instance).to have_received(:submit).with(/cp.*\/etc\/samba\/smb.conf/)
      expect(command_instance).to have_received(:submit).with(/rm -f/)
      expect(command_instance).to have_received(:execute)
    end
  end

  describe '.write_lmhosts' do
    it 'writes content to temp file and copies to /etc/samba/lmhosts' do
      described_class.write_lmhosts('test content')

      expect(command_instance).to have_received(:submit).with(/cp.*\/etc\/samba\/lmhosts/)
      expect(command_instance).to have_received(:execute)
    end
  end
end
