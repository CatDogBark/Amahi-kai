# Handles filesystem operations for shares:
# - Directory creation/removal
# - Ownership and permissions
# - Guest write access
#
# Extracted from Share model callbacks to keep the model thin
# and make side effects testable in isolation. The changes themselves are made by the
# root helper (shares.* operations), which only works inside the share root
# (/var/lib/amahi-kai/files) or a mounted data drive under /mnt.

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

    # amahi:users, mode 2775: group-writable, and new files keep the users group.
    Privileged.call('shares.create_dir', path: share.path)
  rescue Privileged::Error => e
    # Say so instead of saving a share whose folder doesn't exist.
    share.errors.add(:path, "#{share.path} couldn't be created: #{e.message}")
    throw :abort
  end

  # Removes +path+ if it's an empty folder; a folder with files in it stays.
  def remove_empty_directory(path)
    Privileged.call('shares.remove_dir', path: path)
  rescue Privileged::Error => e
    Rails.logger.warn("ShareFileSystem: #{path} not removed: #{e.message}")
  end

  # Called before save, after setup_directory: when guest_writeable changes, or when a
  # guest-writeable share gets a new folder (created without guest write access).
  def update_guest_permissions
    return unless share.guest_writeable_changed? || (share.path_changed? && share.guest_writeable)

    if share.guest_writeable
      make_guest_writeable
    else
      make_guest_non_writeable
    end
  end

  # Called before destroy — remove empty share directory
  def cleanup_directory
    remove_empty_directory(share.path)
  end

  # o+w on the share folder
  def make_guest_writeable
    set_guest_write(true)
  end

  # o-w on the share folder
  def make_guest_non_writeable
    set_guest_write(false)
  end

  private

  def set_guest_write(writable)
    Privileged.call('shares.set_guest_write', path: share.path, writable: writable)
    true
  rescue Privileged::Error => e
    Rails.logger.error("ShareFileSystem: guest write for #{share.path} not changed: #{e.message}")
    false
  end
end
