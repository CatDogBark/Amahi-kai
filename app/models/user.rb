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

require 'strscan'
require 'shell'
require 'shellwords'
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

  validates :role, inclusion: { in: ROLES }

  scope :admins, -> { where(role: 'admin') }
  scope :non_guests, -> { where.not(role: 'guest') }

  validates :login, :presence => true,
  :format => { :with => /\A[A-Za-z][A-Za-z0-9]+\z/ },
  :length => { :in => 3..32 },
  :uniqueness => { :case_sensitive => false },
  :user_not_exist_in_system => {:message => 'already exists in system', :on => :create}

  # this is a very coarse check on the public key! sshd(8) explains each key can be up to 8k?
  validates_length_of :public_key, :in => 300..8192, :allow_nil => true

  validates :name, :presence => true

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

  # Can this user write to a specific share via the web UI?
  def can_write_share?(share)
    return true if admin?
    return false if guest?
    return !share.rdonly if share.everyone?
    share.users_with_write_access.include?(self)
  end

  class << self
    def system_find_name_by_username(username)
      u = ENV['USER']
      if Rails.env.development? && username == u
        return [u, 4444, u]
      end
      pwd = StringScanner.new(File.open('/etc/passwd').readlines.join)
      user = Regexp.new("^(#{username}):[^:]*:(\\d+):\\d+:([^:]*):", Regexp::MULTILINE | Regexp::IGNORECASE)
      pwd.scan_until user or return nil
      uid = pwd[2].to_i
      name = pwd[3].gsub(/,*$/,'')
      [name, uid, pwd[1]]
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
  end

  def add_to_users_group
    esc_login = Shellwords.escape(self.login)
    Shell.run("usermod -g users -a -G users #{esc_login}")
  end

  def add_or_passwd_change_samba_user
    esc_login = Shellwords.escape(self.login)
    Shell.run("usermod #{esc_login}")
    sync_samba_password
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

  # Writable share IDs for this user
  def writable_share_ids
    return Share.pluck(:id) if admin?
    return [] if guest?

    everyone_writable = Share.where(everyone: true, rdonly: false).pluck(:id)
    granted_write = CapWriter.where(user_id: id).pluck(:share_id)
    (everyone_writable + granted_write).uniq
  end

  protected

  def require_password?
    new_record? || password.present? || password_confirmation.present?
  end

  # Sync password to Samba's pdbedit database.
  # Linux accounts are created with a locked password (no SSH password login).
  # Web auth uses bcrypt in Rails DB. Samba uses pdbedit. No DES crypt.
  # The password goes to pdbedit on stdin (-t reads it twice), never in argv or the log.
  def sync_samba_password
    return if password.blank?
    esc_login = Shellwords.escape(self.login)
    Shell.run_with_input("pdbedit -d0 -t -a -u #{esc_login}", "#{password}\n#{password}\n")
  end

  # Create the Linux user. useradd leaves the password locked, so there is no
  # SSH password login; the account exists for Samba UID mapping and a home directory.
  # (--disabled-password is an adduser option; useradd rejects it.)
  def create_system_account
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    Shell.run("useradd -m -g users -c #{esc_name} #{esc_login}")
  end

  def before_create_hook
    self.login = self.login.downcase
    # Set role from admin flag if role not explicitly set (backwards compat)
    self.role ||= 'user'
    return if User.system_user_exists? self.login
    unless create_system_account
      # Without a Linux account the user couldn't use Samba; don't create a half user.
      errors.add(:base, "Couldn't create the Linux account for #{login}")
      throw :abort
    end
    # The account exists now, so a Samba failure here is logged rather than undone;
    # setting the password again retries it.
    Rails.logger.error("Couldn't set the Samba password for #{login}") unless sync_samba_password
  end

  def before_save_hook
    update_pubkey if public_key_changed?

    # Sync role → admin flag for backwards compatibility
    if has_attribute?(:role) && role_changed?
      self.admin = (role == 'admin')
    elsif admin_changed?
      # Legacy: if admin flag changed directly, sync to role
      self.role = admin? ? 'admin' : 'user'
    end

    if admin_changed?
      make_admin
      Share.push_shares
    end

    # Users created while account creation was broken have no Linux account.
    # Setting their password creates it, so the Samba sync below can add them.
    create_system_account if persisted? && password.present? && !User.system_user_exists?(login)

    return unless User.system_user_exists? self.login
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    Shell.run("usermod -c #{esc_name} #{esc_login}")
    # Keep web and Samba passwords in step: if Samba refuses the new one, keep the old.
    if password.present? && !sync_samba_password
      errors.add(:base, "Couldn't update the Samba password for #{login}")
      throw :abort
    end
  end

  # Run each step on its own: a user can have a Linux account but no Samba entry,
  # and a failed pdbedit used to stop the Linux account from being removed.
  def before_destroy_hook
    esc_login = Shellwords.escape(self.login)
    Shell.run("pdbedit -d0 -x -u #{esc_login}")
    Shell.run("userdel -r #{esc_login}") if app_created_system_account?
  end

  # Only remove Linux accounts this app made: create_system_account gives them the
  # `users` group as their primary group. An account that existed before, such as
  # the install user, is left alone along with its home directory.
  def app_created_system_account?
    pw = Etc.getpwnam(login)
    pw.uid >= 1000 && pw.gid == Etc.getgrnam(Platform::DEFAULT_GROUP).gid
  rescue ArgumentError
    false
  end

  def update_pubkey
    Platform.update_user_pubkey(login, public_key)
  end

  def make_admin
    Platform.make_admin(login, admin?)
  end
end
