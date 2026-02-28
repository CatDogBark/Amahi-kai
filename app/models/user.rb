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

  validates_uniqueness_of :pin, :allow_nil => true
  validate :validate_pin,  unless: Proc.new { |user| user.pin.blank? }

  validates :password, :length => { :minimum => 8 }, :if => :require_password?

  before_create :before_create_hook
  before_save :before_save_hook
  before_destroy :before_destroy_hook
  after_save :after_save_hook
  after_create :after_create_hook

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

    def system_all_new_users
      res = []
      Dir.chdir("/home") do
        Dir.glob("*").sort.reverse.each do |login|
          unless User.where(:login=> login).first
            name, uid = system_find_name_by_username login
            res << { :login => login, :name => name } unless name.nil? or name.blank? or uid < 500
          end
        end
      end
      res
    end

    def all_users
      new_users = self.system_all_new_users
      self.create(new_users) unless new_users.blank?
      self.where('login not in (?)', ['root']).sort { |x,y| x.login <=> y.login }
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
  # Linux accounts are created with --disabled-password (no SSH access).
  # Web auth uses bcrypt in Rails DB. Samba uses pdbedit. No DES crypt.
  def sync_samba_password
    return if password.blank?
    esc_login = Shellwords.escape(self.login)
    esc_pwd = Shellwords.escape(self.password)
    Shell.run("sh -c '(echo #{esc_pwd}; echo #{esc_pwd}) | pdbedit -d0 -t -a -u #{esc_login}'")
  end

  def before_create_hook
    self.login = self.login.downcase
    # Set role from admin flag if role not explicitly set (backwards compat)
    self.role ||= 'user'
    return if User.system_user_exists? self.login
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    # Create Linux user with disabled password — no SSH access.
    # Linux account exists only for Samba UID mapping and home directory.
    Shell.run("useradd --disabled-password -m -g users -c #{esc_name} #{esc_login}")
    sync_samba_password
  end

  def before_save_hook
    update_pubkey if public_key_changed?

    # Sync role → admin flag for backwards compatibility
    if role_changed?
      self.admin = (role == 'admin')
    elsif admin_changed?
      # Legacy: if admin flag changed directly, sync to role
      self.role = admin? ? 'admin' : 'user'
    end

    if admin_changed?
      make_admin
      Share.push_shares
    end

    return unless User.system_user_exists? self.login
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    Shell.run("usermod -c #{esc_name} #{esc_login}")
    sync_samba_password if password.present?
  end

  def after_save_hook
    #
  end

  def after_create_hook
    Share.create_logon_script(self.login)
  end

  def before_destroy_hook
    esc_login = Shellwords.escape(self.login)
    Shell.run(
      "pdbedit -d0 -x -u #{esc_login}",
      "userdel -r #{esc_login}"
    )
  end

  def update_pubkey
    Platform.update_user_pubkey(login, public_key)
  end

  def make_admin
    Platform.make_admin(login, admin?)
  end

  def validate_pin
    errors.add(:base, "PIN length must be between 3 to 5") if self.pin.length < 3 || self.pin.length > 5
    errors.add(:base, "PIN format does not match") unless self.pin =~ /\A[A-Za-z0-9]+\z/
  end
end
