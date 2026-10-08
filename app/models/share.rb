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
require 'ipaddr'

class Share < ApplicationRecord
  # Samba's free-space answer for a pooled share (libexec/amahi-dfree): Greyhole's own
  # greyhole-dfree can't read greyhole.conf as the person connected, and answered no space.
  DFREE_COMMAND = '/opt/amahi-kai/libexec/amahi-dfree'.freeze
  # Samba's recycle bin, the Trash of a share that isn't pooled (share_conf; Trash).
  RECYCLE_PARAMS = [
    'recycle:repository = .recycle', 'recycle:keeptree = yes', 'recycle:versions = yes',
    'recycle:directory_mode = 0770', 'recycle:subdir_mode = 0770', 'recycle:exclude_dir = .recycle',
    'recycle:exclude = *.tmp,*.temp,~$*,.~lock.*,Thumbs.db,.DS_Store'
  ].freeze


  def to_param
    name
  end

  DEFAULT_SHARES_ROOT = '/var/lib/amahi-kai/files'

  SIGNATURE = "Amahi configuration"
  DEFAULT_SHARES = %w[Books Pictures Movies Videos Music Docs Public TV].freeze

  scope :by_name, -> { order(:name) }

  has_many :cap_accesses, :dependent => :destroy
  has_many :users_with_share_access, :through => :cap_accesses, :source => :user

  has_many :cap_writers, :dependent => :destroy
  has_many :users_with_write_access, :through => :cap_writers, :source => :user

  has_many :share_files, dependent: :destroy

  # --- Callbacks (delegate to services) ---
  # Folder first: guest write access is set on the folder setup_directory creates.
  before_save -> { file_system.setup_directory }
  before_save -> { file_system.update_guest_permissions }
  before_destroy -> { file_system.cleanup_directory }
  after_create_commit :index_share_files
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
    e = "#{e.chomp}\n" unless e.empty?
    # Samba takes one vfs objects line per share (a later one replaces an earlier), so the
    # modules the share's features ask for go on one line. A pooled share has Greyhole's first,
    # as Greyhole's own tools put it, and no recycle: Greyhole's trash keeps deleted files.
    modules = e.scan(/^\s*vfs objects\s*=\s*(.*)$/i).flatten.flat_map(&:split).uniq
    e = e.gsub(/^\s*vfs objects\s*=.*\n?/i, '')
    if disk_pool_copies > 0
      e = e.gsub(/^\s*dfree command.*\n?/, '')
      e += "\tdfree command = #{DFREE_COMMAND}\n"
      modules = ['greyhole', *(modules - %w[greyhole recycle])]
    end
    # Amahi-kai sets the recycle bin's settings itself (a pooled share has none).
    e = e.gsub(/^\s*recycle:.*\n?/, '')
    unless disk_pool_copies > 0
      # The Trash: Samba moves what's deleted here into the share's .recycle folder (hidden, a
      # dot folder), in folders the users group can change, so Amahi-kai can restore and delete
      # them; amahi-kai-trash.timer deletes what's been there too long. Temporary and lock files
      # aren't kept.
      e += RECYCLE_PARAMS.map { |param| "\t#{param}\n" }.join
      modules |= ['recycle']
    end
    e += "\tvfs objects = #{modules.join(' ')}\n" if modules.any?
    ret % [name, name, path, wr, br, allowed, writes, masks, e]
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

  def update_extras!(params)
    self.update(params)
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
      # No printer sharing: the NAS has no print server.
      "\tload printers = no",
      "\tprinting = bsd",
      "\tprintcap name = /dev/null",
      "\tdisable spoolss = yes",
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
      *samba_network_lines,
      *greyhole_samba_lines,
      "",
      "[homes]",
      "\tcomment = Home Directories",
      "\tvalid users = %%S",
      # The guest account has no home; without this, anonymous browsing showed a "nobody" share.
      "\tinvalid users = nobody",
      "\tbrowseable = no",
      "\twritable = yes",
      "\tcreate mask = 0644",
    "\tdirectory mask = 0755"].join "\n"
    ret % [short_domain, domain]
  end

  # Tailscale's address ranges (IPv4 CGNAT block and its IPv6 ULA prefix).
  TAILSCALE_RANGES = %w[100.64.0.0/10 fd7a:115c:a1e0::/48].freeze

  # Samba answers only the NAS itself, the LAN and Tailscale. Anything else, including
  # Docker containers' private ranges, is refused: Docker apps get share folders as
  # mounted volumes, not over SMB. Binding to interfaces alone wouldn't do it, since a
  # container can still reach the LAN address; `hosts allow` filters by source.
  def self.samba_network_lines
    lines = []
    net = Setting.value_by_name('net').to_s.strip
    iface = primary_interface
    # Without the LAN prefix the allow list would lock out the LAN, so leave it off.
    if net.match?(/\A\d{1,3}(\.\d{1,3}){2}\z/)
      allow = ["127.0.0.1", "::1", "#{net}.", "fe80::/10", *lan_ipv6_prefixes(iface), *TAILSCALE_RANGES]
      lines << "\thosts allow = #{allow.join(' ')}"
    end
    if iface.present?
      ifaces = ["lo", iface]
      ifaces << "tailscale0" if File.exist?("/sys/class/net/tailscale0")
      lines << "\tinterfaces = #{ifaces.join(' ')}" << "\tbind interfaces only = yes"
    end
    lines
  end

  # The interface of the default route, such as ens18.
  def self.primary_interface
    Shell.output('ip', '-4', 'route', 'show', 'default')[/\bdev\s+(\S+)/, 1]
  end

  # Global IPv6 prefixes on the LAN interface, so IPv6 clients on the LAN are allowed too.
  def self.lan_ipv6_prefixes(iface)
    return [] if iface.blank?
    out = Shell.output('ip', '-6', '-o', 'addr', 'show', 'dev', iface, 'scope', 'global')
    out.scan(%r{inet6\s+([0-9a-f:]+)/(\d+)}).map { |addr, len| "#{IPAddr.new(addr).mask(len.to_i)}/#{len}" }.uniq
  rescue IPAddr::InvalidAddressError
    []
  end

  # Greyhole leaves pooled files as symlinks to the pool drives, so Samba has to follow
  # them. These used to be added only at Greyhole install time and were lost the next
  # time smb.conf was generated.
  GREYHOLE_SAMBA_LINES = ["\twide links = yes", "\tfollow symlinks = yes", "\tallow insecure wide links = yes"].freeze

  def self.greyhole_samba_lines
    require 'greyhole'
    Greyhole.installed? ? GREYHOLE_SAMBA_LINES : []
  rescue LoadError
    []
  end

  def self.header(domain)
    header_workgroup(domain) + "\n\n"
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

  def push_samba_config
    Share.push_shares
  rescue Shell::CommandError, Errno::ENOENT, Errno::EACCES, IOError => e
    Rails.logger.error("Failed to push Samba config: #{e.message}")
  end

  # Index files in this share once it's committed, so the job can find the row.
  # (An after_create Thread.new ran before commit and outside the connection pool.)
  def index_share_files
    ShareIndexJob.perform_later(id)
  end
end
