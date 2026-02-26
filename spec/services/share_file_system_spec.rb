require 'rails_helper'

RSpec.describe ShareFileSystem do
  let(:admin) { create(:admin) }
  let(:command_instance) { instance_double(Command, submit: nil, execute: nil) }

  before do
    admin  # ensure admin exists
    allow(Command).to receive(:new).and_return(command_instance)
    allow(Share).to receive(:push_shares)
  end

  describe '#setup_directory' do
    it 'creates directory with correct ownership when path changes' do
      share = create(:share, path: '/var/hda/files/old')
      share.path = '/var/hda/files/movies'
      # Simulate path_changed? being true
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('/var/hda/files/old')

      fs = described_class.new(share)
      fs.setup_directory

      expect(command_instance).to have_received(:submit).with(/rmdir.*\/var\/hda\/files\/old/)
      expect(command_instance).to have_received(:submit).with(/mkdir -p.*\/var\/hda\/files\/movies/)
      expect(command_instance).to have_received(:submit).with(/chown.*#{admin.login}:users.*\/var\/hda\/files\/movies/)
      expect(command_instance).to have_received(:submit).with(/chmod g\+w.*\/var\/hda\/files\/movies/)
      expect(command_instance).to have_received(:execute)
    end

    it 'skips rmdir when path_was is blank (new share)' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('')

      fs = described_class.new(share)
      fs.setup_directory

      expect(command_instance).not_to have_received(:submit).with(/rmdir/)
      expect(command_instance).to have_received(:submit).with(/mkdir -p/)
    end

    it 'does nothing when path has not changed' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(false)

      fs = described_class.new(share)
      fs.setup_directory

      expect(command_instance).not_to have_received(:execute)
    end

    it 'does nothing when path is blank' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(true)
      share.path = ''

      fs = described_class.new(share)
      fs.setup_directory

      expect(command_instance).not_to have_received(:execute)
    end

    it 'shell-escapes paths with spaces' do
      share = create(:share, path: '/var/hda/files/old')
      share.path = '/var/hda/files/my movies'
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('/var/hda/files/old')

      fs = described_class.new(share)
      fs.setup_directory

      expect(command_instance).to have_received(:submit).with(/mkdir -p.*my\\ movies/)
    end
  end

  describe '#update_guest_permissions' do
    it 'calls make_guest_writeable when guest_writeable changed to true' do
      share = create(:share, guest_writeable: true)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)
      allow(share).to receive(:guest_writeable).and_return(true)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(command_instance).to have_received(:submit).with(/chmod o\+w/)
    end

    it 'calls make_guest_non_writeable when guest_writeable changed to false' do
      share = create(:share, guest_writeable: false)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)
      allow(share).to receive(:guest_writeable).and_return(false)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(command_instance).to have_received(:submit).with(/chmod o-w/)
    end

    it 'does nothing when guest_writeable has not changed' do
      share = create(:share)
      allow(share).to receive(:guest_writeable_changed?).and_return(false)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(command_instance).not_to have_received(:execute)
    end
  end

  describe '#cleanup_directory' do
    it 'runs rmdir with ignore-fail-on-non-empty' do
      share = create(:share, path: '/var/hda/files/movies')

      fs = described_class.new(share)
      fs.cleanup_directory

      expect(command_instance).to have_received(:submit).with(nil) # Command.new(cmd) doesn't use submit
    end

    it 'shell-escapes the path' do
      # Command.new(cmd) passes cmd directly, so check the constructor
      share = create(:share, path: '/var/hda/files/my movies')

      expect(Command).to receive(:new).with(/rmdir --ignore-fail-on-non-empty.*my\\ movies/).and_return(command_instance)

      fs = described_class.new(share)
      fs.cleanup_directory
    end
  end

  describe '#clear_permissions' do
    it 'runs chmod -R a+rwx' do
      share = create(:share, path: '/var/hda/files/movies')

      fs = described_class.new(share)
      fs.clear_permissions

      expect(command_instance).to have_received(:submit).with(/chmod -R a\+rwx.*\/var\/hda\/files\/movies/)
    end
  end

  describe '#make_guest_writeable' do
    it 'runs chmod o+w' do
      share = create(:share, path: '/var/hda/files/public')

      fs = described_class.new(share)
      fs.make_guest_writeable

      expect(command_instance).to have_received(:submit).with(/chmod o\+w/)
    end
  end

  describe '#make_guest_non_writeable' do
    it 'runs chmod o-w' do
      share = create(:share, path: '/var/hda/files/public')

      fs = described_class.new(share)
      fs.make_guest_non_writeable

      expect(command_instance).to have_received(:submit).with(/chmod o-w/)
    end
  end
end
