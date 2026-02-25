require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires a login" do
      user = User.new(name: "Test", password: "secretpassword", password_confirmation: "secretpassword")
      expect(user).not_to be_valid
      expect(user.errors[:login]).to be_present
    end

    it "requires unique login" do
      existing = create(:user)
      user2 = build(:user, login: existing.login)
      expect(user2).not_to be_valid
    end

    it "requires login between 3-32 chars" do
      short = build(:user, login: "ab")
      expect(short).not_to be_valid

      long = build(:user, login: "a" * 33)
      expect(long).not_to be_valid
    end

    it "requires password minimum 8 chars" do
      user = build(:user, password: "short", password_confirmation: "short")
      expect(user).not_to be_valid
    end

    it "requires password confirmation to match" do
      user = build(:user, password: "secretpassword", password_confirmation: "different")
      expect(user).not_to be_valid
    end
  end

  describe ".system_find_name_by_username" do
    it "returns nil for nonexistent user" do
      result = User.system_find_name_by_username("nonexistent_user_#{SecureRandom.hex(8)}")
      expect(result).to be_nil
    end
  end

  describe "#make_admin" do
    it "calls Platform.make_admin" do
      allow(Platform).to receive(:make_admin)
      user = create(:user, admin: true)
      user.make_admin
      expect(Platform).to have_received(:make_admin).with(user.login, true)
    end
  end

  describe "admin scope" do
    it "filters admin users" do
      admin = create(:admin)
      regular = create(:user, admin: false)
      admins = User.where(admin: true)
      expect(admins).to include(admin)
      expect(admins).not_to include(regular)
    end
  end
end
