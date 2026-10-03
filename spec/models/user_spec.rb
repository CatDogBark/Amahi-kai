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
      expect(create(:user, login: "validlogin")).to be_valid
      expect(create(:user, login: "vld")).to be_valid
      expect(create(:user, login: "Login789")).to be_valid
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
    it "should return true when no password_digest exists" do
      user = create(:user)
      user.password_digest = nil
      expect(user.needs_auth?).to be true
    end

    it "should return true when password_digest is blank" do
      user = create(:user)
      user.password_digest = ""
      expect(user.needs_auth?).to be true
    end

    it "should return false when password_digest exists" do
      user = create(:user)
      expect(user.needs_auth?).to be false
    end
  end

  describe "system account commands" do
    let(:user) { User.new(login: "newperson", name: "New Person", password: "longenough1") }

    before do
      allow(User).to receive(:system_user_exists?).and_return(false)
      allow(Shell).to receive(:run).and_return(true)
      allow(Shell).to receive(:run_with_input).and_return(true)
    end

    it "creates the Linux account with options useradd accepts" do
      user.send(:before_create_hook)
      expect(Shell).to have_received(:run).with("useradd -m -g users -c New\\ Person newperson")
    end

    it "sends the Samba password on stdin, not in the command" do
      user.send(:sync_samba_password)
      expect(Shell).to have_received(:run_with_input)
        .with("pdbedit -d0 -t -a -u newperson", "longenough1\nlongenough1\n")
      expect(Shell).not_to have_received(:run).with(/longenough1/)
    end

    it "creates a missing Linux account when an existing user's password is set" do
      existing = User.find(create(:user, login: "olduser", name: "Old User").id)
      allow(User).to receive(:system_user_exists?).and_return(false, true)
      existing.password = existing.password_confirmation = "newpassword1"
      existing.save!
      expect(Shell).to have_received(:run).with("useradd -m -g users -c Old\\ User olduser")
      expect(Shell).to have_received(:run_with_input)
        .with("pdbedit -d0 -t -a -u olduser", "newpassword1\nnewpassword1\n")
    end

    it "leaves an existing Linux account alone when the password changes" do
      existing = User.find(create(:user, login: "hasaccount", name: "Has Account").id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      existing.password = existing.password_confirmation = "newpassword1"
      existing.save!
      expect(Shell).not_to have_received(:run).with(/\Auseradd/)
      expect(Shell).to have_received(:run_with_input)
        .with("pdbedit -d0 -t -a -u hasaccount", "newpassword1\nnewpassword1\n")
    end
  end

  describe "system account cleanup on delete" do
    let(:user) { User.new(login: "leaving", name: "Leaving User") }
    let(:users_group) { Struct.new(:gid).new(100) }

    before do
      allow(Etc).to receive(:getpwnam).and_call_original
      allow(Etc).to receive(:getgrnam).and_call_original
      allow(Etc).to receive(:getgrnam).with("users").and_return(users_group)
    end

    it "removes an app-created Linux account even when it has no Samba entry" do
      allow(Etc).to receive(:getpwnam).with("leaving").and_return(Struct.new(:uid, :gid).new(1002, 100))
      allow(Shell).to receive(:run).with("pdbedit -d0 -x -u leaving").and_return(false)
      allow(Shell).to receive(:run).with("userdel -r leaving").and_return(true)
      user.send(:before_destroy_hook)
      expect(Shell).to have_received(:run).with("userdel -r leaving")
    end

    it "leaves a Linux account the app didn't create alone" do
      allow(Etc).to receive(:getpwnam).with("leaving").and_return(Struct.new(:uid, :gid).new(1000, 1000))
      allow(Shell).to receive(:run).and_return(true)
      user.send(:before_destroy_hook)
      expect(Shell).to have_received(:run).with("pdbedit -d0 -x -u leaving")
      expect(Shell).not_to have_received(:run).with(/userdel/)
    end

    it "skips userdel when there is no Linux account" do
      allow(Etc).to receive(:getpwnam).with("leaving").and_raise(ArgumentError)
      allow(Shell).to receive(:run).and_return(true)
      user.send(:before_destroy_hook)
      expect(Shell).not_to have_received(:run).with(/userdel/)
    end
  end
  describe "session token" do
    it "changes when the password changes" do
      user = User.find(create(:user).id)
      before = user.session_token
      user.update!(password: 'brandnew123', password_confirmation: 'brandnew123')
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(before)
    end

    it "stays the same for other changes" do
      user = User.find(create(:user).id)
      expect { user.update!(name: 'Someone Else') }.not_to change { user.reload.session_token }
    end
  end
end
