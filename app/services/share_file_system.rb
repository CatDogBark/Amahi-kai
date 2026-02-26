# Handles filesystem operations for shares:
# - Directory creation/removal
# - Ownership and permissions
# - Guest writeable chmod
#
# Extracted from Share model callbacks to keep the model thin
# and make side effects testable in isolation.

require 'shellwords'
require 'command'

class ShareFileSystem
  attr_reader :share

  def initialize(share)
    @share = share
  end

  # Called before save when path changes — create new dir, remove old empty one
  def setup_directory
    return unless share.path_changed?
    return if share.path.blank?

    admin = User.admins.first
    return unless admin

    c = Command.new
    c.submit("rmdir #{Shellwords.escape(share.path_was)}") unless share.path_was.blank?
    c.submit("mkdir -p #{Shellwords.escape(share.path)}")
    c.submit("chown #{Shellwords.escape(admin.login)}:users #{Shellwords.escape(share.path)}")
    c.submit("chmod g+w #{Shellwords.escape(share.path)}")
    c.execute
  end

  # Called before save when guest_writeable changes
  def update_guest_permissions
    return unless share.guest_writeable_changed?

    if share.guest_writeable
      make_guest_writeable
    else
      make_guest_non_writeable
    end
  end

  # Called before destroy — remove empty share directory
  def cleanup_directory
    c = Command.new("rmdir --ignore-fail-on-non-empty #{Shellwords.escape(share.path)}")
    c.execute
  end

  # chmod o+w on the share path
  def make_guest_writeable
    c = Command.new
    c.submit("chmod o+w #{Shellwords.escape(share.path)}")
    c.execute
  end

  # chmod o-w on the share path
  def make_guest_non_writeable
    c = Command.new
    c.submit("chmod o-w #{Shellwords.escape(share.path)}")
    c.execute
  end

  # chmod -R a+rwx on the share path (clear all permissions)
  def clear_permissions
    c = Command.new
    c.submit("chmod -R a+rwx #{Shellwords.escape(share.path)}")
    c.execute
  end
end
