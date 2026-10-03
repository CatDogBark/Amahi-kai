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

    # Remove the old folder only if it's empty. This used to be the first step of
    # one command chain, so an old folder with files in it stopped the new one
    # from being created.
    remove_empty_directory(share.path_was) unless share.path_was.blank?

    path = Shellwords.escape(share.path)
    created = Shell.run("mkdir -p #{path}", "chown amahi:users #{path}", "chmod 2775 #{path}")
    return if created

    # Say so instead of saving a share whose folder doesn't exist.
    share.errors.add(:path, "#{share.path} couldn't be created")
    throw :abort
  end

  def remove_empty_directory(path)
    Dir.rmdir(path) if Dir.exist?(path) && Dir.empty?(path)
  rescue SystemCallError
    Shell.run("rmdir --ignore-fail-on-non-empty #{Shellwords.escape(path)}")
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
