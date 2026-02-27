# Handles filesystem operations for shares:
# - Directory creation/removal
# - Ownership and permissions
# - Guest writeable chmod
#
# Extracted from Share model callbacks to keep the model thin
# and make side effects testable in isolation.

require 'shellwords'
require 'shell'

class ShareFileSystem
  attr_reader :share

  def initialize(share)
    @share = share
  end

  # Called before save when path changes — create new dir, remove old empty one
  def setup_directory
    return unless share.path_changed?
    return if share.path.blank?

    cmds = []
    cmds << "rmdir #{Shellwords.escape(share.path_was)}" unless share.path_was.blank?
    cmds << "mkdir -p #{Shellwords.escape(share.path)}"
    cmds << "chown amahi:users #{Shellwords.escape(share.path)}"
    cmds << "chmod 2775 #{Shellwords.escape(share.path)}"
    Shell.run(*cmds)
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
    Shell.run("rmdir --ignore-fail-on-non-empty #{Shellwords.escape(share.path)}")
  end

  # chmod o+w on the share path
  def make_guest_writeable
    Shell.run("chmod o+w #{Shellwords.escape(share.path)}")
  end

  # chmod o-w on the share path
  def make_guest_non_writeable
    Shell.run("chmod o-w #{Shellwords.escape(share.path)}")
  end

  # chmod -R a+rwx on the share path (clear all permissions)
  def clear_permissions
    Shell.run("chmod -R a+rwx #{Shellwords.escape(share.path)}")
  end
end
