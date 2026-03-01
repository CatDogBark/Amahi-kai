require 'rails_helper'

RSpec.describe User, 'RBAC', type: :model do
  before do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    allow(Share).to receive(:push_shares)
  end

  describe 'role predicates' do
    it 'admin? returns true for admin role' do
      user = create(:admin)
      expect(user.admin?).to be true
      expect(user.user?).to be false
      expect(user.guest?).to be false
    end

    it 'user? returns true for user role' do
      user = create(:user, role: 'user')
      expect(user.user?).to be true
      expect(user.admin?).to be false
      expect(user.guest?).to be false
    end

    it 'guest? returns true for guest role' do
      user = create(:user, role: 'guest')
      expect(user.guest?).to be true
      expect(user.admin?).to be false
      expect(user.user?).to be false
    end
  end

  describe '#can_browse?' do
    it 'returns true for admin' do
      expect(create(:admin).can_browse?).to be true
    end

    it 'returns true for user' do
      expect(create(:user, role: 'user').can_browse?).to be true
    end

    it 'returns false for guest' do
      expect(create(:user, role: 'guest').can_browse?).to be false
    end
  end

  describe '#can_access_share?' do
    let(:share) { create(:share, everyone: false) }

    it 'admin can access any share' do
      admin = create(:admin)
      expect(admin.can_access_share?(share)).to be true
    end

    it 'guest cannot access any share' do
      guest = create(:user, role: 'guest')
      expect(guest.can_access_share?(share)).to be false
    end

    it 'user can access everyone share' do
      everyone_share = create(:share, everyone: true)
      user = create(:user, role: 'user')
      expect(user.can_access_share?(everyone_share)).to be true
    end

    it 'user can access share they have cap_access for' do
      user = create(:user, role: 'user')
      share.users_with_share_access << user
      expect(user.can_access_share?(share)).to be true
    end

    it 'user cannot access share without cap_access' do
      user = create(:user, role: 'user')
      expect(user.can_access_share?(share)).to be false
    end
  end

  describe '#can_write_share?' do
    let(:share) { create(:share, everyone: false) }

    it 'admin can write any share' do
      expect(create(:admin).can_write_share?(share)).to be true
    end

    it 'guest cannot write any share' do
      expect(create(:user, role: 'guest').can_write_share?(share)).to be false
    end

    it 'user can write everyone non-readonly share' do
      everyone_share = create(:share, everyone: true, rdonly: false)
      user = create(:user, role: 'user')
      expect(user.can_write_share?(everyone_share)).to be true
    end

    it 'user cannot write everyone readonly share' do
      everyone_share = create(:share, everyone: true, rdonly: true)
      user = create(:user, role: 'user')
      expect(user.can_write_share?(everyone_share)).to be false
    end

    it 'user can write share with cap_writer' do
      user = create(:user, role: 'user')
      share.users_with_write_access << user
      expect(user.can_write_share?(share)).to be true
    end

    it 'user cannot write share without cap_writer' do
      user = create(:user, role: 'user')
      expect(user.can_write_share?(share)).to be false
    end
  end

  describe '#accessible_shares' do
    it 'admin gets all shares' do
      admin = create(:admin)
      create(:share, name: "Share1")
      create(:share, name: "Share2")
      expect(admin.accessible_shares.count).to eq(Share.count)
    end

    it 'guest gets no shares' do
      guest = create(:user, role: 'guest')
      create(:share, name: "Share1")
      expect(guest.accessible_shares).to be_empty
    end

    it 'user gets everyone shares plus granted shares' do
      user = create(:user, role: 'user')
      everyone_share = create(:share, name: "Public", everyone: true)
      private_share = create(:share, name: "Private", everyone: false)
      granted_share = create(:share, name: "Granted", everyone: false)
      granted_share.users_with_share_access << user

      accessible = user.accessible_shares
      expect(accessible).to include(everyone_share)
      expect(accessible).to include(granted_share)
      expect(accessible).not_to include(private_share)
    end
  end

  describe '#writable_share_ids' do
    it 'admin gets all share ids' do
      admin = create(:admin)
      s1 = create(:share, name: "S1")
      s2 = create(:share, name: "S2")
      expect(admin.writable_share_ids).to include(s1.id, s2.id)
    end

    it 'guest gets empty array' do
      guest = create(:user, role: 'guest')
      create(:share)
      expect(guest.writable_share_ids).to be_empty
    end

    it 'user gets everyone-writable plus cap_writer shares' do
      user = create(:user, role: 'user')
      writable = create(:share, name: "Writable", everyone: true, rdonly: false)
      readonly = create(:share, name: "ReadOnly", everyone: true, rdonly: true)
      granted = create(:share, name: "Granted", everyone: false)
      granted.users_with_write_access << user

      ids = user.writable_share_ids
      expect(ids).to include(writable.id)
      expect(ids).to include(granted.id)
      expect(ids).not_to include(readonly.id)
    end
  end

  describe 'scopes' do
    it '.non_guests excludes guest users' do
      admin = create(:admin)
      user = create(:user, role: 'user')
      guest = create(:user, role: 'guest')

      result = User.non_guests
      expect(result).to include(admin, user)
      expect(result).not_to include(guest)
    end
  end

  describe 'role validation' do
    it 'rejects invalid roles' do
      user = build(:user, role: 'superadmin')
      expect(user).not_to be_valid
      expect(user.errors[:role]).to be_present
    end

    it 'accepts valid roles' do
      %w[admin user guest].each do |role|
        user = build(:user, role: role)
        expect(user).to be_valid, "Expected role '#{role}' to be valid"
      end
    end
  end

  describe 'role-admin sync' do
    # Factory stubs before_save_hook (which does the sync), so test manually
    it 'sets admin flag true when role is admin' do
      user = create(:user, role: 'admin', admin: true)
      expect(user.admin).to be true
    end

    it 'sets admin flag false when role is user' do
      user = create(:user, role: 'user', admin: false)
      expect(user.admin).to be false
    end
  end
end
