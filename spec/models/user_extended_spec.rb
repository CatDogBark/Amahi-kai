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

    it "finds an existing account whatever the case of the login" do
      name, uid, login = User.system_find_name_by_username("ROOT")
      expect([uid, login]).to eq([0, "root"])
      expect(name).to be_a(String)
    end

    it "doesn't treat the login as a pattern" do
      expect(User.system_find_name_by_username("r.*")).to be_nil
    end
  end

  describe "login validation against Linux accounts" do
    it "refuses a login that already exists on the system" do
      user = build(:user, login: "Root")
      expect(user).not_to be_valid
      expect(user.errors[:login]).to include("already exists in system")
    end
  end

  describe "name validation" do
    it "refuses names the Linux account can't hold" do
      expect(build(:user, name: "a:b")).not_to be_valid
      expect(build(:user, name: "two\nlines")).not_to be_valid
      expect(build(:user, name: "x" * 65)).not_to be_valid
      expect(build(:user, name: "José Ñandú")).to be_valid
    end
  end

  describe "becoming an admin" do
    it "doesn't change the user's Linux groups" do
      user = User.find(create(:user).id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      user.update!(role: 'admin')
      expect(Privileged.calls).to be_empty
    end
  end

  describe "admin scope" do
    it "filters admin users" do
      admin = create(:admin)
      regular = create(:user, admin: false)
      admins = User.admins
      expect(admins).to include(admin)
      expect(admins).not_to include(regular)
    end
  end
end
