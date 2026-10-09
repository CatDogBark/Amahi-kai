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

  # Linux and Samba accounts are changed by the root helper (spec/lib/amahi_helper_spec.rb
  # covers what it runs); here, which operations the model asks for.
  describe "system account operations" do
    let(:user) { User.new(login: "newperson", name: "New Person", password: "longenough1") }

    def helper_error(message)
      Privileged::Error.new('op', message)
    end

    before do
      allow(User).to receive(:system_user_exists?).and_return(false)
    end

    it "creates the Linux account, then sets the Samba password" do
      user.send(:before_create_hook)
      expect(Privileged.calls).to eq([
        ['users.create', { login: "newperson", name: "New Person" }],
        ['users.set_password', { login: "newperson", password: "longenough1" }]
      ])
    end

    it "creates a missing Linux account when an existing user's password is set" do
      existing = User.find(create(:user, login: "olduser", name: "Old User").id)
      allow(User).to receive(:system_user_exists?).and_return(false, true)
      existing.password = existing.password_confirmation = "newpassword1"
      existing.save!
      expect(Privileged.calls.map(&:first)).to eq(['users.create', 'users.set_password'])
    end

    it "refuses to create a user whose Linux account can't be made, and says why" do
      allow(Privileged).to receive(:call).with('users.create', anything).and_raise(helper_error("no space left"))
      expect(user.save).to be false
      expect(user).not_to be_persisted
      expect(user.errors.full_messages.join).to include("Couldn't create the Linux account for newperson: no space left")
    end

    it "keeps the old password when Samba refuses the new one" do
      existing = User.find(create(:user, login: "sambafail", name: "Samba Fail").id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      allow(Privileged).to receive(:call).and_raise(helper_error("pdbedit exited 1"))
      existing.password = existing.password_confirmation = "newpassword1"
      expect(existing.save).to be false
      expect(existing.errors.full_messages.join).to include("Couldn't update the Samba password for sambafail: pdbedit exited 1")
      expect(User.find(existing.id).authenticate("secretpassword")).to be_truthy
    end

    it "only sets the password when the password changes" do
      existing = User.find(create(:user, login: "hasaccount", name: "Has Account").id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      existing.password = existing.password_confirmation = "newpassword1"
      existing.save!
      expect(Privileged.calls).to eq([['users.set_password', { login: "hasaccount", password: "newpassword1" }]])
    end

    it "sets the Linux full name only when the name changes" do
      existing = User.find(create(:user, login: "renamed", name: "Old Name").id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      existing.update!(name: "New Name")
      existing.update!(role: 'admin')
      expect(Privileged.calls).to eq([['users.set_name', { login: "renamed", name: "New Name" }]])
    end

    it "still saves a new name when the Linux account refuses it" do
      existing = User.find(create(:user, login: "notmine", name: "Old Name").id)
      allow(User).to receive(:system_user_exists?).and_return(true)
      allow(Privileged).to receive(:call).and_raise(helper_error("notmine is not an account Amahi created"))
      expect(existing.update(name: "New Name")).to be true
    end
  end

  describe "system account cleanup on delete" do
    let(:user) { User.new(login: "leaving", name: "Leaving User") }

    it "asks the helper to delete the accounts (it decides what it may remove)" do
      user.send(:before_destroy_hook)
      expect(Privileged.calls).to eq([['users.delete', { login: "leaving" }]])
    end

    it "still deletes the web user when the helper refuses (an account that existed before)" do
      existing = User.find(create(:user, login: "leaving").id)
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('users.delete', 'not an account Amahi created', refused: true))
      existing.destroy
      expect(User.exists?(existing.id)).to be false
    end

    it "keeps the web user, saying why, when the Linux account couldn't be deleted" do
      existing = User.find(create(:user, login: "leaving").id)
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('users.delete', 'userdel exited 8: user leaving is currently used by process 158525'))
      expect(existing.destroy).to be false
      expect(User.exists?(existing.id)).to be true
      expect(existing.errors.full_messages.first).to eq("Couldn't delete leaving's account on the NAS: userdel exited 8: user leaving is currently used by process 158525")
    end
  end

  describe ".normalize_system_accounts" do
    it "normalizes each user that has a Linux account and skips refusals" do
      create(:user, login: "first")
      create(:user, login: "second")
      create(:user, login: "nolinux")
      allow(User).to receive(:system_user_exists?) { |login| login != "nolinux" }
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('users.normalize', login: "second")
        .and_raise(Privileged::Error.new('users.normalize', 'not an account Amahi created'))
      expect(User.normalize_system_accounts).to eq(User.count - 2)
      expect(Privileged.calls).to include(['users.normalize', { login: "first" }])
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
  describe ".seed_admin_password_in_use?" do
    # spec_helper loads db/seeds.rb before each example, as on a fresh install.
    let(:seeded_admin) { User.find_by(login: User::SEED_ADMIN_LOGIN) }

    it "is true while the seeded admin still logs in with the seeded password" do
      expect(User.seed_admin_password_in_use?).to be true
    end

    it "is false once that password has changed" do
      seeded_admin.update!(password: "a-new-passphrase")
      expect(User.seed_admin_password_in_use?).to be false
    end

    it "is false when the seeded admin account is gone" do
      seeded_admin.delete
      expect(User.seed_admin_password_in_use?).to be false
    end

    it "is true while the admin keeps the installer's random first password, and false once it's changed" do
      seeded_admin.update!(password: 'Xk3f9QvL2mT8wRz5BnYc')
      Setting.set(User::FIRST_PASSWORD_SETTING, seeded_admin.password_digest)
      expect(User.seed_admin_password_in_use?).to be true
      seeded_admin.update!(password: 'a-new-passphrase')
      expect(User.seed_admin_password_in_use?).to be false
    end
  end
end
