require 'rails_helper'

RSpec.describe ShareAccessManager do
  before do
    create(:admin)
    create(:setting, name: 'net', value: '1')
    create(:setting, name: 'self-address', value: '1')
    allow(Share).to receive(:push_shares)
  end

  describe '#sync_everyone_access' do
    it 'populates access lists with all users when everyone is true' do
      user1 = create(:user)
      user2 = create(:user)
      share = create(:share, everyone: true)

      manager = described_class.new(share)
      manager.sync_everyone_access

      expect(share.users_with_share_access).to include(user1, user2)
      expect(share.users_with_write_access).to include(user1, user2)
    end

    it 'does nothing when everyone is false' do
      user = create(:user)
      share = create(:share, everyone: false)

      manager = described_class.new(share)
      manager.sync_everyone_access

      expect(share.users_with_share_access).not_to include(user)
    end
  end

  describe '#toggle_everyone!' do
    it 'switches from everyone to per-user with all users seeded' do
      user = create(:user)
      share = create(:share, everyone: true)

      manager = described_class.new(share)
      manager.toggle_everyone!

      share.reload
      expect(share.everyone).to eq(false)
      expect(share.rdonly).to eq(true)
      expect(share.users_with_share_access).to include(user)
      expect(share.users_with_write_access).to include(user)
    end

    it 'switches from per-user to everyone, clears access lists and guest' do
      user = create(:user)
      share = create(:share, everyone: false, guest_access: true, guest_writeable: true)
      share.users_with_share_access << user

      manager = described_class.new(share)
      manager.toggle_everyone!

      share.reload
      expect(share.everyone).to eq(true)
      expect(share.guest_access).to eq(false)
      expect(share.guest_writeable).to eq(false)
    end
  end

  describe '#toggle_access!' do
    let(:user) { create(:user) }
    let(:share) { create(:share, everyone: false) }
    let(:manager) { described_class.new(share) }

    it 'adds user access when not present' do
      manager.toggle_access!(user.id)
      expect(share.users_with_share_access).to include(user)
    end

    it 'removes user access when already present' do
      share.users_with_share_access << user
      manager.toggle_access!(user.id)
      expect(share.reload.users_with_share_access).not_to include(user)
    end

    it 'does nothing when everyone is true' do
      share.update_column(:everyone, true)
      share.reload

      manager.toggle_access!(user.id)
      # No error, just a no-op
    end
  end

  describe '#toggle_write!' do
    let(:user) { create(:user) }
    let(:share) { create(:share, everyone: false) }
    let(:manager) { described_class.new(share) }

    it 'adds write access when not present' do
      manager.toggle_write!(user.id)
      expect(share.users_with_write_access).to include(user)
    end

    it 'removes write access when already present' do
      share.users_with_write_access << user
      manager.toggle_write!(user.id)
      expect(share.reload.users_with_write_access).not_to include(user)
    end

    it 'does nothing when everyone is true' do
      share.update_column(:everyone, true)
      share.reload

      manager.toggle_write!(user.id)
    end
  end

  describe '#toggle_guest_access!' do
    it 'enables guest access and forces non-writeable' do
      share = create(:share, guest_access: false, guest_writeable: true)
      manager = described_class.new(share)
      manager.toggle_guest_access!

      share.reload
      expect(share.guest_access).to eq(true)
      expect(share.guest_writeable).to eq(false)
    end

    it 'disables guest access' do
      share = create(:share, guest_access: true)
      manager = described_class.new(share)
      manager.toggle_guest_access!

      expect(share.reload.guest_access).to eq(false)
    end
  end

  describe '#toggle_guest_writeable!' do
    it 'toggles guest writeable on' do
      share = create(:share, guest_writeable: false)
      manager = described_class.new(share)
      manager.toggle_guest_writeable!

      expect(share.reload.guest_writeable).to eq(true)
    end

    it 'toggles guest writeable off' do
      share = create(:share, guest_writeable: true)
      manager = described_class.new(share)
      manager.toggle_guest_writeable!

      expect(share.reload.guest_writeable).to eq(false)
    end
  end
end
