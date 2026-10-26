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

    # Refused and only logged, every later config was refused too, and nothing on the pages said so.
    it 'keeps why it was refused for the Shares page, until a config is installed' do
      expect(described_class.refusal).to be_nil
      refuse('samba.write_config')
      described_class.write_smb_conf('broken')
      expect(described_class.refusal).to eq('testparm rejected smb.conf')
      allow(Privileged).to receive(:call).with('samba.write_config', any_args).and_return('ok' => true)
      described_class.write_smb_conf('fixed')
      expect(described_class.refusal).to be_nil
    end

    it "leaves no note when the caller hears the refusal itself (a share's extra settings)" do
      refuse('samba.write_config')
      expect { described_class.write_smb_conf('broken', raise_refusal: true) }.to raise_error(Privileged::Error)
      expect(described_class.refusal).to be_nil
    end
  end

  describe '.reload' do
    it 'reports a failed reload instead of raising' do
      allow(Privileged).to receive(:call).with('samba.reload').and_raise(Privileged::Error.new('samba.reload', 'exit 1'))
      expect(described_class.reload).to be false
    end
  end

  describe '.follow_interfaces!' do
    it "pushes the settings, and restarts smbd only when its interfaces line changed (router mode on or off)" do
      allow(described_class).to receive(:push_config).and_return(true)
      allow(described_class).to receive(:restart_for_new_addresses)
      allow(described_class).to receive(:interfaces_line).and_return('interfaces = lo ens19', 'interfaces = lo ens18')
      described_class.follow_interfaces!
      expect(described_class).to have_received(:restart_for_new_addresses).once
      allow(described_class).to receive(:interfaces_line).and_return('interfaces = lo ens18')
      described_class.follow_interfaces!
      expect(described_class).to have_received(:restart_for_new_addresses).once # unchanged: a reload is enough
    end

    it "reads smb.conf's interfaces line" do
      Tempfile.create('smb.conf') do |file|
        file.write("[global]\n\tworkgroup = HOME\n\tinterfaces = lo ens18 tailscale0\n")
        file.flush
        expect(described_class.interfaces_line(file.path)).to eq('interfaces = lo ens18 tailscale0')
      end
      expect(described_class.interfaces_line('/nonexistent/smb.conf')).to be_nil
    end
  end

  describe '.restart_for_new_addresses' do
    it "restarts smbd so it listens on addresses that came after it started, unless it's stopped" do
      allow(Shell).to receive(:success?).with('systemctl', 'is-active', '--quiet', 'smbd').and_return(true)
      expect(described_class.restart_for_new_addresses).to be true
      expect(Privileged.calls).to include(['services.restart', { service: 'smbd' }])
      Privileged.reset!
      allow(Shell).to receive(:success?).with('systemctl', 'is-active', '--quiet', 'smbd').and_return(false)
      expect(described_class.restart_for_new_addresses).to be false
      expect(Privileged.calls).to be_empty
    end
  end
end
