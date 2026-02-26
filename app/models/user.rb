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

  scope :admins, ->{ where(:admin => true)}

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
    pwd_option = password_option()
    Shell.run("usermod #{pwd_option} #{esc_login}")
    unless self.password.nil? && self.password.blank?
      esc_pwd = Shellwords.escape(self.password)
      Shell.run("sh -c '(echo #{esc_pwd}; echo #{esc_pwd}) | pdbedit -d0 -t -a -u #{esc_login}'")
    end
  end

  def needs_auth?
    !password_digest || password_digest.blank?
  end

  protected

  def require_password?
    new_record? || password.present? || password_confirmation.present?
  end

  def before_create_hook
    self.login = self.login.downcase
    return if User.system_user_exists? self.login
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    pwd_option = password_option()
    cmds = ["useradd -m -g users -c #{esc_name} #{pwd_option} #{esc_login}"]
    unless self.password.nil? && self.password.blank?
      esc_pwd = Shellwords.escape(self.password)
      cmds << "sh -c '(echo #{esc_pwd}; echo #{esc_pwd}) | pdbedit -d0 -t -a -u #{esc_login}'"
    end
    Shell.run(*cmds)
  end

  def password_option
    return "" if self.password.nil? || self.password.blank?
    salt = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['.', '/']
    salt = (salt.sort_by{rand}.join)[0,2]
    sys_crypted_password = password.crypt(salt)
    "-p #{Shellwords.escape(sys_crypted_password)}"
  end

  def before_save_hook
    update_pubkey if public_key_changed?

    if admin_changed?
      make_admin
      Share.push_shares
    end

    return unless User.system_user_exists? self.login
    esc_login = Shellwords.escape(self.login)
    esc_name = Shellwords.escape(self.name)
    pwd_option = password_option()
    cmds = ["usermod -c #{esc_name} #{pwd_option} #{esc_login}"]
    if password.present?
      esc_pwd = Shellwords.escape(password)
      cmds << "sh -c '(echo #{esc_pwd}; echo #{esc_pwd}) | pdbedit -d0 -t -a -u #{esc_login}'"
    end
    Shell.run(*cmds)
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
