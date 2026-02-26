require 'rails_helper'

RSpec.describe ShareFileSystem do
  let(:admin) { create(:admin) }

  before do
    admin
    allow(Shell).to receive(:run).and_return(true)
    allow(Share).to receive(:push_shares)
  end

  describe '#setup_directory' do
    it 'runs commands when path changes' do
      share = create(:share, path: '/var/hda/files/old')
      share.path = '/var/hda/files/movies'
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('/var/hda/files/old')

      fs = described_class.new(share)
      fs.setup_directory

      expect(Shell).to have_received(:run).with(
        /rmdir.*old/,
        /mkdir -p.*movies/,
        /chown.*#{admin.login}:users.*movies/,
        /chmod g\+w.*movies/
      )
    end

    it 'skips rmdir when path_was is blank (new share)' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('')

      fs = described_class.new(share)
      fs.setup_directory

      expect(Shell).to have_received(:run) do |*args|
        expect(args.none? { |a| a =~ /rmdir/ }).to be true
      end
    end

    it 'does nothing when path has not changed' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(false)

      fs = described_class.new(share)
      fs.setup_directory

      expect(Shell).not_to have_received(:run)
    end

    it 'does nothing when path is blank' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(true)
      share.path = ''

      fs = described_class.new(share)
      fs.setup_directory

      expect(Shell).not_to have_received(:run)
    end

    it 'shell-escapes paths with spaces' do
      share = create(:share, path: '/var/hda/files/old')
      share.path = '/var/hda/files/my movies'
      allow(share).to receive(:path_changed?).and_return(true)
      allow(share).to receive(:path_was).and_return('/var/hda/files/old')

      fs = described_class.new(share)
      fs.setup_directory

      expect(Shell).to have_received(:run) do |*args|
        expect(args.any? { |a| a =~ /my\\ movies/ }).to be true
      end
    end
  end

  describe '#update_guest_permissions' do
    it 'calls make_guest_writeable when guest_writeable changed to true' do
      share = create(:share, guest_writeable: true)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)
      allow(share).to receive(:guest_writeable).and_return(true)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(Shell).to have_received(:run).with(/chmod o\+w/)
    end

    it 'calls make_guest_non_writeable when guest_writeable changed to false' do
      share = create(:share, guest_writeable: false)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)
      allow(share).to receive(:guest_writeable).and_return(false)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(Shell).to have_received(:run).with(/chmod o-w/)
    end

    it 'does nothing when guest_writeable has not changed' do
      share = create(:share)
      allow(share).to receive(:guest_writeable_changed?).and_return(false)

      fs = described_class.new(share)
      fs.update_guest_permissions

      expect(Shell).not_to have_received(:run)
    end
  end

  describe '#cleanup_directory' do
    it 'runs rmdir with ignore-fail-on-non-empty' do
      share = create(:share, path: '/var/hda/files/movies')

      fs = described_class.new(share)
      fs.cleanup_directory

      expect(Shell).to have_received(:run).with(/rmdir --ignore-fail-on-non-empty/)
    end
  end

  describe '#clear_permissions' do
    it 'runs chmod -R a+rwx' do
      share = create(:share, path: '/var/hda/files/movies')

      fs = described_class.new(share)
      fs.clear_permissions

      expect(Shell).to have_received(:run).with(/chmod -R a\+rwx/)
    end
  end

  describe '#make_guest_writeable' do
    it 'runs chmod o+w' do
      share = create(:share, path: '/var/hda/files/public')

      fs = described_class.new(share)
      fs.make_guest_writeable

      expect(Shell).to have_received(:run).with(/chmod o\+w/)
    end
  end

  describe '#make_guest_non_writeable' do
    it 'runs chmod o-w' do
      share = create(:share, path: '/var/hda/files/public')

      fs = described_class.new(share)
      fs.make_guest_non_writeable

      expect(Shell).to have_received(:run).with(/chmod o-w/)
    end
  end
end
