# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."

require 'etc'

class User < ApplicationRecord

  # Rails built-in auth: bcrypt password hashing via `password_digest` column.
  # Provides: password, password_confirmation, authenticate(password)
  has_secure_password

  # --- Roles ---
  # admin  — full web UI access, all shares, system configuration
  # user   — dashboard, file browser (share-filtered), search
  # guest  — Samba-only access, no web UI beyond login
  ROLES = %w[admin user guest].freeze

  # The account db/seeds.rb creates. Its password is public (it's in this repo), so the
  # setup wizard can't finish and the security audit fails while it still works.
  SEED_ADMIN_LOGIN = 'admin'.freeze
  SEED_ADMIN_PASSWORD = 'secretpassword'.freeze

  validates :role, inclusion: { in: ROLES }

  scope :admins, -> { where(role: 'admin') }
  scope :non_guests, -> { where.not(role: 'guest') }

  validates :login, :presence => true,
  :format => { :with => /\A[A-Za-z][A-Za-z0-9]+\z/ },
  :length => { :in => 3..32 },
  :uniqueness => { :case_sensitive => false },
  :user_not_exist_in_system => {:message => 'already exists in system', :on => :create}

  # The name is also the Linux account's full name (GECOS field).
  validates :name, :presence => true, :length => { :maximum => 64 },
  :format => { :without => /[[:cntrl:]:]/, :message => "can't contain a colon or control characters" }

  validates :password, :length => { :minimum => 8 }, :if => :require_password?

  before_create :before_create_hook
  # A new password gets a new session token, which signs out every other session.
  before_save :rotate_session_token, if: :will_save_change_to_password_digest?
  before_save :before_save_hook
  before_destroy :before_destroy_hook

  # --- Role helpers ---

  def admin?
    role == 'admin'
  end

  def user?
    role == 'user'
  end

  def guest?
    role == 'guest'
  end

  # Can this user access the web file browser / search?
  def can_browse?
    admin? || user?
  end

  # Can this user access a specific share via the web UI?
  def can_access_share?(share)
    return true if admin?
    return false if guest?
    return true if share.everyone?
    share.users_with_share_access.include?(self)
  end

  class << self
    # True while the seeded admin account still accepts the seeded password.
    def seed_admin_password_in_use?
      admin = find_by(login: SEED_ADMIN_LOGIN)
      admin.present? && admin.authenticate(SEED_ADMIN_PASSWORD).present?
    end

    # [full name, uid, login] of the Linux account for +username+, or nil.
    # Logins are lowercased when users are created, so look up the lowercase name.
    def system_find_name_by_username(username)
      u = ENV['USER']
      if Rails.env.development? && username == u
        return [u, 4444, u]
      end
      pw = Etc.getpwnam(username.to_s.downcase)
      [pw.gecos.sub(/,*\z/, ''), pw.uid, pw.name]
    rescue ArgumentError
      nil
    end

    # Every user except root, by login. (This used to scan /home on each call and try
    # to add the accounts it found, which always failed: they had no password.)
    def all_users
      where.not(login: 'root').order(:login)
    end

    def system_user_exists? (username)
      system_find_name_by_username(username)
    end

    def is_valid_name? (username)
      name, uid = system_find_name_by_username(username)
      name == nil
    end

    # Brings each user's Linux account to the current standard: no login shell and no
    # extra groups. bin/amahi-update runs this; the helper skips accounts the app
    # didn't create. Returns how many accounts were checked.
    def normalize_system_accounts
      find_each.count do |user|
        next false unless system_user_exists?(user.login)
        Privileged.call('users.normalize', login: user.login)
        true
      rescue Privileged::Error => e
        Rails.logger.warn("User #{user.login}: account left as it is: #{e.message}")
        false
      end
    end
  end

  def rotate_session_token
    self.session_token = SecureRandom.hex(20)
  end

  def needs_auth?
    !password_digest || password_digest.blank?
  end

  # Accessible shares for this user (for file browser / search filtering)
  def accessible_shares
    return Share.by_name if admin?
    return Share.none if guest?

    everyone_ids = Share.where(everyone: true).pluck(:id)
    granted_ids = CapAccess.where(user_id: id).pluck(:share_id)
    Share.where(id: (everyone_ids + granted_ids).uniq).by_name
  end

  protected

  def require_password?
    new_record? || password.present? || password_confirmation.present?
  end

  # Set the Samba password. Web logins use bcrypt in the app's database; the Linux
  # password stays locked. The helper hands the password to pdbedit on stdin.
  def sync_samba_password
    return true if password.blank?
    system_call('users.set_password', login: login, password: password)
  end

  # Create the Linux user: primary group users, no login shell, locked password. The
  # account exists for Samba's user mapping and a home directory.
  def create_system_account
    system_call('users.create', login: login, name: name)
  end

  # Runs a root helper operation. Returns true, or false with the helper's reason
  # logged and kept in @system_error for the error shown in the UI.
  def system_call(operation, **args)
    Privileged.call(operation, **args)
    true
  rescue Privileged::Error => e
    Rails.logger.error("User #{login}: #{operation} failed: #{e.message}")
    @system_error = e.message
    false
  end

  def before_create_hook
    self.login = self.login.downcase
    # Set role from admin flag if role not explicitly set (backwards compat)
    self.role ||= 'user'
    return if User.system_user_exists? self.login
    unless create_system_account
      # Without a Linux account the user couldn't use Samba; don't create a half user.
      errors.add(:base, "Couldn't create the Linux account for #{login}: #{@system_error}")
      throw :abort
    end
    # The account exists now, so a Samba failure here is logged rather than undone;
    # setting the password again retries it.
    Rails.logger.error("Couldn't set the Samba password for #{login}") unless sync_samba_password
  end

  # Web admin and Linux admin are separate: being an admin here adds no Linux groups.
  def before_save_hook
    # Sync role → admin flag for backwards compatibility
    if has_attribute?(:role) && role_changed?
      self.admin = (role == 'admin')
    elsif admin_changed?
      # Legacy: if admin flag changed directly, sync to role
      self.role = admin? ? 'admin' : 'user'
    end

    # Users created while account creation was broken have no Linux account.
    # Setting their password creates it, so the Samba sync below can add them.
    create_system_account if persisted? && password.present? && !User.system_user_exists?(login)

    return unless User.system_user_exists? self.login
    # The Linux full name is cosmetic, so a failure is only logged.
    system_call('users.set_name', login: login, name: name) if persisted? && will_save_change_to_name?
    # Keep web and Samba passwords in step: if Samba refuses the new one, keep the old.
    if password.present? && !sync_samba_password
      errors.add(:base, "Couldn't update the Samba password for #{login}: #{@system_error}")
      throw :abort
    end
  end

  # The helper removes the Samba user, then the Linux account and its home directory,
  # but only an account the app created (primary group users): one that existed
  # before, such as the install user, is left alone. A refusal is logged, and the web
  # user is still deleted.
  def before_destroy_hook
    system_call('users.delete', login: login)
  end
end
