require 'rails_helper'

RSpec.describe SambaService do
  before do
    create(:admin)
    create(:setting, name: 'net', value: '192.168.1')
    create(:setting, name: 'self-address', value: '100')
    create(:setting, name: 'domain', value: 'example.local')
    Setting.find_or_create_by!(name: 'workgroup', kind: Setting::GENERAL) { |s| s.value = 'WORKGROUP' }
    Setting.find_or_create_by!(name: 'debug', kind: Setting::SHARES) { |s| s.value = '0' }
    allow(Share).to receive(:push_shares)
  end

  def refuse(operation)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with(operation, any_args)
      .and_raise(Privileged::Error.new(operation, 'testparm rejected smb.conf', refused: true))
  end

  describe '.push_config' do
    it 'installs smb.conf and lmhosts through the helper, then reloads Samba' do
      create(:share, name: 'TestShare')

      expect(described_class.push_config).to be true

      expect(Privileged.calls.map(&:first)).to eq(%w[samba.write_config samba.write_lmhosts samba.reload])
      config = Privileged.calls.first.last[:content]
      expect(config).to include('[TestShare]')
      expect(Privileged.calls[1].last[:content]).to include('127.0.0.1 localhost')
    end

    it 'returns false and still reloads for lmhosts when smb.conf is refused' do
      refuse('samba.write_config')

      expect(described_class.push_config).to be false

      expect(Privileged.calls.map(&:first)).to eq(%w[samba.write_lmhosts samba.reload])
    end
  end

  describe '.write_smb_conf' do
    it 'keeps the current smb.conf when the helper refuses the new one' do
      refuse('samba.write_config')
      expect(described_class.write_smb_conf('broken')).to be false
    end
  end

  describe '.reload' do
    it 'reports a failed reload instead of raising' do
      allow(Privileged).to receive(:call).with('samba.reload').and_raise(Privileged::Error.new('samba.reload', 'exit 1'))
      expect(described_class.reload).to be false
    end
  end
end
