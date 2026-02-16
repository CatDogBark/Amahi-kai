require 'spec_helper'

describe User do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  it "should have a valid factory" do
    expect(create(:user)).to be_valid
  end

  it "should have a valid admin factory" do
    admin = create(:admin)
    expect(admin).to be_valid
    expect(admin.admin).to be true
  end

  describe "login validations" do
    it "should require a login" do
      expect { create(:user, login: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should require login to be at least 3 characters" do
      expect { create(:user, login: "ab") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should require login to be at most 32 characters" do
      expect { create(:user, login: "a" * 33) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should require login to start with a letter" do
      expect { create(:user, login: "1badlogin") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should only allow alphanumeric logins" do
      expect { create(:user, login: "bad-login") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { create(:user, login: "bad login") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { create(:user, login: "bad_login") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should require unique logins (case-insensitive)" do
      create(:user, login: "testuser")
      expect { create(:user, login: "testuser") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { create(:user, login: "TestUser") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should allow valid logins" do
      expect(create(:user, login: "validuser")).to be_valid
      expect(create(:user, login: "abc")).to be_valid
      expect(create(:user, login: "User123")).to be_valid
    end
  end

  describe "name validations" do
    it "should require a name" do
      expect { create(:user, name: nil) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { create(:user, name: "") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "password validations" do
    it "should require password of at least 8 characters on create" do
      expect { create(:user, password: "short") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "should accept passwords of 8 or more characters" do
      expect(create(:user, password: "longpassword")).to be_valid
    end
  end

  describe "pin validations" do
    it "should allow nil pin" do
      user = create(:user)
      user.pin = nil
      expect(user).to be_valid
    end

    it "should require pin to be between 3 and 5 characters" do
      user = create(:user)
      user.pin = "ab"
      expect(user).not_to be_valid

      user.pin = "abc"
      expect(user).to be_valid

      user.pin = "abcde"
      expect(user).to be_valid

      user.pin = "abcdef"
      expect(user).not_to be_valid
    end

    it "should only allow alphanumeric pins" do
      user = create(:user)
      user.pin = "ab!"
      expect(user).not_to be_valid

      user.pin = "abc"
      expect(user).to be_valid
    end

    it "should require unique pins" do
      user1 = create(:user)
      user1.update!(pin: "abc")

      user2 = create(:user)
      user2.pin = "abc"
      expect(user2).not_to be_valid
    end
  end

  describe "public_key validations" do
    it "should allow nil public_key" do
      expect(create(:user, public_key: nil)).to be_valid
    end

    it "should reject public keys shorter than 300 characters" do
      user = create(:user)
      user.public_key = "x" * 299
      expect(user).not_to be_valid
    end

    it "should reject public keys longer than 8192 characters" do
      user = create(:user)
      user.public_key = "x" * 8193
      expect(user).not_to be_valid
    end
  end

  describe "scopes" do
    it "should return only admins with .admins scope" do
      regular = create(:user)
      admin = create(:admin)
      admins = User.admins
      expect(admins).to include(admin)
      expect(admins).not_to include(regular)
    end
  end

  describe "#needs_auth?" do
    it "should return true when no crypted_password exists" do
      user = create(:user)
      user.crypted_password = nil
      expect(user.needs_auth?).to be true
    end

    it "should return true when crypted_password is blank" do
      user = create(:user)
      user.crypted_password = ""
      expect(user.needs_auth?).to be true
    end

    it "should return false when crypted_password exists" do
      user = create(:user)
      expect(user.needs_auth?).to be false
    end
  end
end
