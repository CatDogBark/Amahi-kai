require 'rails_helper'

# The folder changes themselves are made by the root helper (spec/lib/amahi_helper_spec.rb);
# here, which operations a share asks for and how failures are reported.
RSpec.describe ShareFileSystem do
  let(:admin) { create(:admin) }

  before do
    admin
    allow(Share).to receive(:push_shares)
  end

  def path_change(share, from:, to:)
    share.path = to
    allow(share).to receive(:path_changed?).and_return(true)
    allow(share).to receive(:path_was).and_return(from)
  end

  describe '#setup_directory' do
    it 'removes the old folder if empty, then creates the new one' do
      share = create(:share, path: '/var/lib/amahi-kai/files/old')
      path_change(share, from: '/var/lib/amahi-kai/files/old', to: '/var/lib/amahi-kai/files/movies')

      described_class.new(share).setup_directory

      expect(Privileged.calls).to eq([
        ['shares.remove_dir', { path: '/var/lib/amahi-kai/files/old' }],
        ['shares.create_dir', { path: '/var/lib/amahi-kai/files/movies' }]
      ])
    end

    it 'still creates the new folder when the old one is kept' do
      share = create(:share)
      path_change(share, from: '/var/lib/amahi-kai/files/old', to: '/var/lib/amahi-kai/files/movies')
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('shares.remove_dir', anything)
        .and_raise(Privileged::Error.new('shares.remove_dir', 'not inside the share root'))

      described_class.new(share).setup_directory

      expect(Privileged.calls).to eq([['shares.create_dir', { path: '/var/lib/amahi-kai/files/movies' }]])
    end

    it 'stops the save with the reason when the folder cannot be created' do
      share = create(:share)
      path_change(share, from: '', to: '/etc/cannot')
      allow(Privileged).to receive(:call)
        .and_raise(Privileged::Error.new('shares.create_dir', 'path /etc/cannot is not inside /var/lib/amahi-kai/files'))

      expect { described_class.new(share).setup_directory }.to throw_symbol(:abort)
      expect(share.errors[:path].join).to include("couldn't be created: path /etc/cannot is not inside")
    end

    it 'skips the removal for a new share' do
      share = create(:share)
      path_change(share, from: '', to: '/var/lib/amahi-kai/files/new')

      described_class.new(share).setup_directory

      expect(Privileged.calls.map(&:first)).to eq(['shares.create_dir'])
    end

    it 'does nothing when path has not changed' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(false)

      described_class.new(share).setup_directory

      expect(Privileged.calls).to be_empty
    end

    it 'does nothing when path is blank' do
      share = create(:share)
      allow(share).to receive(:path_changed?).and_return(true)
      share.path = ''

      described_class.new(share).setup_directory

      expect(Privileged.calls).to be_empty
    end
  end

  describe '#update_guest_permissions' do
    it 'turns guest write on when guest_writeable changes to true' do
      share = create(:share, path: '/var/lib/amahi-kai/files/public', guest_writeable: true)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)

      described_class.new(share).update_guest_permissions

      expect(Privileged.calls).to eq([['shares.set_guest_write', { path: '/var/lib/amahi-kai/files/public', writable: true }]])
    end

    it 'turns guest write off when guest_writeable changes to false' do
      share = create(:share, guest_writeable: false)
      allow(share).to receive(:guest_writeable_changed?).and_return(true)

      described_class.new(share).update_guest_permissions

      expect(Privileged.calls).to eq([['shares.set_guest_write', { path: share.path, writable: false }]])
    end

    it 'gives a guest-writeable share its guest write access again on a new folder' do
      share = create(:share, guest_writeable: true)
      allow(share).to receive(:guest_writeable_changed?).and_return(false)
      allow(share).to receive(:path_changed?).and_return(true)

      described_class.new(share).update_guest_permissions

      expect(Privileged.calls).to eq([['shares.set_guest_write', { path: share.path, writable: true }]])
    end

    it 'does nothing when guest_writeable has not changed' do
      share = create(:share)
      allow(share).to receive(:guest_writeable_changed?).and_return(false)

      described_class.new(share).update_guest_permissions

      expect(Privileged.calls).to be_empty
    end

    it 'reports a failure instead of raising' do
      share = create(:share, guest_writeable: true)
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('shares.set_guest_write', "doesn't exist"))

      expect(described_class.new(share).make_guest_writeable).to be false
    end
  end

  describe '#cleanup_directory' do
    it 'removes the share folder if it is empty' do
      share = create(:share, path: '/var/lib/amahi-kai/files/movies')

      described_class.new(share).cleanup_directory

      expect(Privileged.calls).to eq([['shares.remove_dir', { path: '/var/lib/amahi-kai/files/movies' }]])
    end
  end

  describe 'callback order' do
    it 'creates the folder before setting guest write access on it' do
      share = Share.new(name: 'Guests', path: '/var/lib/amahi-kai/files/guests', guest_writeable: true,
                        rdonly: false, visible: true, disk_pool_copies: 0)
      allow(SambaService).to receive(:push_config)
      share.save!

      expect(Privileged.calls.map(&:first)).to eq(%w[shares.create_dir shares.set_guest_write])
    end
  end
end
