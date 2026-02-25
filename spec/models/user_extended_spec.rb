require 'rails_helper'

RSpec.describe User, type: :model do
  before do
    allow_any_instance_of(Command).to receive(:execute)
    allow_any_instance_of(Command).to receive(:submit).and_return(nil)
  end

  describe "validations" do
    it "requires a login" do
      user = User.new(name: "Test", password: "secretpassword", password_confirmation: "secretpassword")
      expect(user).not_to be_valid
      expect(user.errors[:login]).to be_present
    end

    it "requires unique login" do
      create(:user, login: "unique_test_user_a1")
      user2 = build(:user, login: "unique_test_user_a1")
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
    it "returns array for valid system user from /etc/passwd" do
      # Read a real user from /etc/passwd
      passwd_line = File.readlines('/etc/passwd').find { |l| l.split(':')[2].to_i >= 1000 }
      if passwd_line
        login = passwd_line.split(':').first
        result = User.system_find_name_by_username(login)
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
      end
    end

    it "returns nil for nonexistent user" do
      result = User.system_find_name_by_username("nonexistent_user_xyz_#{SecureRandom.hex(8)}")
      expect(result).to be_nil
    end
  end

  describe "#make_admin" do
    it "sets admin to true" do
      user = create(:user, admin: false)
      user.make_admin
      expect(user.reload.admin).to eq(true)
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

    it "allows blank pin" do
      user = create(:user)
      user.pin = ""
      expect(user).to be_valid
    end

    it "allows nil pin" do
      user = create(:user)
      user.pin = nil
      expect(user).to be_valid
    end
  end
end
