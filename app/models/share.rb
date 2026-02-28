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

require 'shell'
require 'platform'
require 'temp_cache'
require 'shellwords'

class Share < ApplicationRecord

  def to_param
    name
  end

  DEFAULT_SHARES_ROOT = '/var/lib/amahi-kai/files'

  SIGNATURE = "Amahi configuration"
  DEFAULT_SHARES = [ "Books", "Pictures", "Movies", "Videos", "Music", "Docs", "Public", "TV" ].each {|s| I18n.t s }
  PDC_SETTINGS = "/var/lib/amahi-kai/domain-settings"

  scope :by_name, -> { order(:name) }

  has_many :cap_accesses, :dependent => :destroy
  has_many :users_with_share_access, :through => :cap_accesses, :source => :user

  has_many :cap_writers, :dependent => :destroy
  has_many :users_with_write_access, :through => :cap_writers, :source => :user

  has_many :share_files, dependent: :destroy

  # --- Callbacks (delegate to services) ---
  before_save :normalize_tags, if: :tags_changed?
  before_save -> { file_system.update_guest_permissions }
  before_save -> { file_system.setup_directory }
  before_destroy -> { file_system.cleanup_directory }
  after_create :index_share_files
  after_save -> { access_manager.sync_everyone_access }
  after_commit :push_samba_config, on: [:create, :update, :destroy]

  validates :name, presence: true,
    format: { :with => /\A\S[\S ]+\z/ },
    length: 1..32,
    uniqueness: { :case_sensitive => false }

  validates :path, presence: true,
    length: 2..64

  # --- Service accessors ---

  def file_system
    @file_system ||= ShareFileSystem.new(self)
  end

  def access_manager
    @access_manager ||= ShareAccessManager.new(self)
  end

  # --- Class methods ---

  def self.default_full_path(name)
    File.join(DEFAULT_SHARES_ROOT, name.downcase)
  end

  # Save the samba config file — delegates to SambaService
  def self.push_shares
    SambaService.push_config
  end

  def self.create_default_shares
    DEFAULT_SHARES.each do |s|
      sh = Share.new
      sh.path = Share.default_full_path(s)
      sh.name = s
      sh.rdonly = false
      sh.visible = true
      sh.tags = s.downcase
      sh.extras = ""
      sh.disk_pool_copies = 0
      sh.save!
    end
  end

  # --- Samba config generation ---

  def share_conf
    ret = "[%s]\n"    \
    "\tcomment = %s\n"   \
    "\tpath = %s\n"   \
    "\twriteable = %s\n"   \
    "\tbrowseable = %s\n%s%s%s%s\n"
    wr = rdonly ? "no" : "yes"
    br = visible ? "yes" : "no"
    allowed  = ''
    writes  = ''
    masks = "\tcreate mask = 0775\n"
    masks += "\tforce create mode = 0664\n"
    masks += "\tdirectory mask = 0775\n"
    masks += "\tforce directory mode = 0775\n"
    unless everyone
      allowed = "\tvalid users = "
      writes = "\twrite list = "
      u = users_with_share_access.map{ |acc| acc.login } rescue nil
      w = users_with_write_access.select{ |wrt| u.include?(wrt.login) }.map{ |user| user.login } rescue nil
      u = ['nobody'] if !u or u.empty?
      u |= ['nobody'] if guest_access
      allowed += u.join(', ') + "\n"
      w = ['nobody'] if !w or w.empty?
      w |= ['nobody'] if guest_writeable
      writes += w.join(', ') + "\n"
    end
    if (guest_access || guest_writeable) && !everyone
      writes += "\tguest ok = yes\n"
    end
    e = ""
    e = "\t" + (extras.gsub /\n/, "\n\t") unless extras.nil?
    if disk_pool_copies > 0
      tmp = e.gsub /\tdfree command.*\n/, ''
      e = tmp.gsub /\tvfs objects.*greyhole.*\n/, ''
      e += "\n\t" + 'dfree command = /usr/bin/greyhole-dfree' + "\n"
      e += "\t" + 'vfs objects = greyhole' + "\n"
    end
    ret % [name, name, path, wr, br, allowed, writes, masks, e]
  end

  def tag_list
    (tags || '').split(',').map(&:strip).reject(&:blank?)
  end

  def self.basenames
    all.map { |s| [s.path, s.name] }
  end

  # --- Delegated instance methods ---

  def make_guest_writeable
    file_system.make_guest_writeable
  end

  def make_guest_non_writeable
    file_system.make_guest_non_writeable
  end

  def toggle_everyone!
    access_manager.toggle_everyone!
  end

  def toggle_visible!
    self.visible = !self.visible
    self.save
  end

  def toggle_readonly!
    self.rdonly = !self.rdonly
    self.save
  end

  def toggle_access!(user_id)
    access_manager.toggle_access!(user_id)
  end

  def toggle_write!(user_id)
    access_manager.toggle_write!(user_id)
  end

  def toggle_guest_access!
    access_manager.toggle_guest_access!
  end

  def toggle_guest_writeable!
    access_manager.toggle_guest_writeable!
  end

  def update_tags!(params)
    unless params[:path].blank?
      self.update(params)
    else
      # Strip any HTML tags and whitespace from input
      name = ActionController::Base.helpers.strip_tags(params[:tags]).strip.downcase
      return false if name.blank?

      # Parse existing tags into a clean array
      current = (self.tags || '').split(',').map { |t| ActionController::Base.helpers.strip_tags(t).strip.downcase }.reject(&:blank?).uniq

      if current.include?(name)
        current.delete(name)
      else
        current << name
      end

      self.tags = current.join(', ')
      self.save
    end
  end

  def toggle_disk_pool!
    self.disk_pool_copies = (self.disk_pool_copies > 0) ? 0 : 1
    self.save
  end

  def update_extras!(params)
    self.update(params)
  end

  def clear_permissions
    file_system.clear_permissions
  end

  # --- Samba config class methods ---

  def self.samba_conf(domain)
    ret = self.header(domain)
    Share.all.each do |s|
      ret += s.share_conf
    end
    ret
  end

  def self.header_workgroup(domain)
    short_domain = Setting.find_or_create_by(Setting::GENERAL, 'workgroup', 'WORKGROUP').value
    debug = Setting.shares.value_by_name('debug') == '1'
    win98 = Setting.shares.value_by_name('win98') == '1'
    ret = ["# This file is automatically generated for WORKGROUP setup.",
      "# Any manual changes MAY BE OVERWRITTEN\n# #{SIGNATURE}, generated on #{Time.now}",
      "[global]",
      "\tworkgroup = %s",
      "\tserver string = %s",
      "\tnetbios name = #{Setting.get('server-name') || 'amahi-kai'}",
      "\tprinting = cups",
      "\tprintcap name = cups",
      "\tload printers = yes",
      "\tcups options = raw",
      "\tlog file = /var/log/samba/%%m.log",
      "\tlog level = #{debug ? 5 : 0}",
      "\tmax log size = 150",
      "\tpreferred master = yes",
      "\tos level = 60",
      "\ttime server = yes",
      "\tunix extensions = no",
      "\tsecurity = user",
      "\tlarge readwrite = yes",
      "\tencrypt passwords = yes",
      "\tdos charset = CP850",
      "\tunix charset = UTF8",
      "\tguest account = nobody",
      "\tmap to guest = Bad User",
      "\twins support = yes",
      win98 ? "client lanman auth = yes" : "",
      "",
      "[homes]",
      "\tcomment = Home Directories",
      "\tvalid users = %%S",
      "\tbrowseable = no",
      "\twritable = yes",
      "\tcreate mask = 0644",
    "\tdirectory mask = 0755"].join "\n"
    ret % [short_domain, domain]
  end

  def self.header_pdc(domain)
    short_domain = Setting.shares.value_by_name("workgroup") || 'workgroup'
    debug = Setting.shares.value_by_name('debug') == '1'
    admins = User.admins rescue ["no_such_user"]
    ret = ["# This file is automatically generated for PDC setup.",
      "# Any manual changes MAY BE OVERWRITTEN\n# #{SIGNATURE}, generated on #{Time.now}",
      "[global]",
      "\tworkgroup = %s",
      "\tserver string = %s",
      "\tnetbios name = #{Setting.get('server-name') || 'amahi-kai'}",
      "\tprinting = cups",
      "\tprintcap name = cups",
      "\tload printers = yes",
      "\tcups options = raw",
      "\tlog file = /var/log/samba/%%m.log",
      "\tlog level = #{debug ? 5 : 0}",
      "\tmax log size = 150",
      "\tpreferred master = yes",
      "\tos level = 65",
      "\tdomain master = yes",
      "\tlocal master = yes",
      "\tadmin users = #{admins.map{|u| u.login}.join ', '}",
      "\tdomain logons = yes",
      "\tlogon path = \\\\%%L\\profiles\\%%U",
      "\tlogon drive = q:",
      "\tlogon home = \\\\%%N\\%%U",
      "\ttime server = yes",
      "\tunix extensions = no",
      "\tsecurity = user",
      "\tlarge readwrite = yes",
      "\tencrypt passwords = yes",
      "\tdos charset = CP850",
      "\tunix charset = UTF8",
      "\tguest account = nobody",
      "\tmap to guest = Bad User",
      "\twins support = yes",
      "\tlogon script = %%U.bat",
      "\tadd machine script = /usr/sbin/useradd -d /dev/null -g 99 -s /bin/false -M %%u",
      "",
      "[netlogon]",
      "\tpath = #{PDC_SETTINGS}/netlogon",
      "\tguest ok = yes",
      "\twritable = no",
      "\tshare modes = no",
      "",
      "[profiles]",
      "\tpath = #{PDC_SETTINGS}/profiles",
      "\twritable = yes",
      "\tbrowseable = no",
      "\tread only = no",
      "\tcreate mode = 0777",
      "\tdirectory mode = 0777",
      "",
      "[homes]",
      "\tcomment = Home Directories",
      "\tread only = no",
      "\twriteable = yes",
      "\tbrowseable = yes",
      "\tcreate mask = 0640",
      "\tdirectory mask = 0750",
    "\n"].join "\n"
    ret % [short_domain, domain]
  end

  def self.header_common
    ["",
      "[print$]",
      "\tpath = /var/lib/samba/drivers",
      "\tread only = yes",
      "\tforce group = root",
      "\twrite list = @ntadmin root",
      "\tforce group = root",
      "\tcreate mask = 0664",
      "\tdirectory mask = 0775",
      "\tguest ok = yes",
      "",
      "[printers]",
      "\tpath = /var/spool/samba",
      "\twriteable = yes",
      "\tbrowseable = yes",
      "\tprintable = yes",
    "\tpublic = yes\n\n"].join("\n")
  end

  def self.header(domain)
    pdc = Setting.shares.value_by_name('pdc') == '1'
    h = pdc ? header_pdc(domain) : header_workgroup(domain)
    h + "\n" + self.header_common
  end

  def self.create_logon_script(username)
    pdc = Setting.shares.value_by_name('pdc') == '1'
    return unless pdc
    return if File.exist?("#{PDC_SETTINGS}/netlogon/#{username}.bat")
    File.open("#{PDC_SETTINGS}/netlogon/#{username}.bat", "w", 0644) do |f|
      f.puts "REM Initial content generated by Amahi on #{Time.now}"
      f.puts "REM can be safely customized by Admin"
      f.puts "logon.bat"
    end
  end

  def self.samba_lmhosts(domain)
    ip = "#{Setting.value_by_name('net')}.#{Setting.value_by_name('self-address')}"
    hostname = Setting.get('server-name') || 'amahi-kai'
    ret = ["# This file is automatically generated. Any manual changes MAY BE OVERWRITTEN\n# #{SIGNATURE}, generated on #{Time.now}",
      "127.0.0.1 localhost",
      "#{ip} #{hostname}",
      "#{ip} files",
      "#{ip} #{hostname}.#{domain}",
    "#{ip} files.#{domain}"].join "\n"
    ret
  end

  def self.default_samba_domain(domain)
    d = domain.gsub /\.(com|net|org|local|co.uk|mobi|pro|info|asia|biz|..)$/, ''
    d = d.gsub /\./, '_'
    d = domain if d.size == 0
    d = d[-15..-1] if d.size > 15
    d
  end

  private

  def normalize_tags
    self.tags = (self.tags || '').split(/\s*,\s*|\s+/)
      .map { |t| ActionController::Base.helpers.strip_tags(t).strip.downcase }
      .reject(&:blank?)
      .uniq
      .join(', ')
  end

  def push_samba_config
    Share.push_shares
  rescue StandardError => e
    Rails.logger.error("Failed to push Samba config: #{e.message}")
  end

  # Index files in this share after creation
  def index_share_files
    Thread.new do
      begin
        require 'share_indexer'
        ShareIndexer.index_share(self)
      rescue StandardError => e
        Rails.logger.error("Share#index_share_files failed: #{e.message}")
      end
    end
  end
end
