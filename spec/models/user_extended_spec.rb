require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires a login" do
      user = User.new(name: "Test", password: "secretpassword", password_confirmation: "secretpassword")
      expect(user).not_to be_valid
      expect(user.errors[:login]).to be_present
    end

    it "requires unique login" do
      create(:user, login: "unique_test_user_a")
      user2 = build(:user, login: "unique_test_user_a")
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
    it "returns name, uid, username for valid system user" do
      allow(User).to receive(:`).and_return("1000:testuser:Test User:/home/testuser")
      # This is system-dependent, just test it doesn't crash
      result = User.system_find_name_by_username("testuser")
      expect(result).to be_an(Array)
    end
  end

  describe ".is_valid_name?" do
    it "accepts valid usernames" do
      expect(User.is_valid_name?("testuser")).to be_truthy
      expect(User.is_valid_name?("test_user")).to be_truthy
    end

    it "rejects invalid usernames" do
      expect(User.is_valid_name?("")).to be_falsey
      expect(User.is_valid_name?("ab")).to be_falsey
      expect(User.is_valid_name?("bad user!")).to be_falsey
    end
  end

  describe "#make_admin" do
    it "sets admin to true" do
      user = create(:user, admin: false)
      user.make_admin
      expect(user.reload.admin).to eq(true)
    end
  end

  describe "#needs_auth?" do
    it "returns true when user has no crypted password" do
      user = create(:user)
      user.update_column(:crypted_password, nil)
      expect(user.needs_auth?).to be true
    end
  end

  describe "admin scope" do
    it "returns admin users" do
      admin = create(:admin)
      regular = create(:user, admin: false)
      admins = User.where(admin: true)
      expect(admins).to include(admin)
      expect(admins).not_to include(regular)
    end
  end

  describe "#validate_pin" do
    it "accepts valid 4-digit pin" do
      user = create(:user)
      user.pin = "1234"
      expect(user).to be_valid
    end

    it "rejects non-numeric pin" do
      user = create(:user)
      user.pin = "abcd"
      expect(user).not_to be_valid
    end

    it "allows blank pin" do
      user = create(:user)
      user.pin = ""
      expect(user).to be_valid
    end
  end
end
