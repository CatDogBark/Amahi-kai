# Manages share access control — user permissions, guest access, everyone toggle.
#
# Extracted from Share model to separate access control logic
# from the ActiveRecord lifecycle.

class ShareAccessManager
  attr_reader :share

  def initialize(share)
    @share = share
  end

  # When everyone=true, sync all users into access/write associations
  # Called after save.
  def sync_everyone_access
    return unless share.everyone

    users = User.all
    share.users_with_share_access = users
    share.users_with_write_access = users
  end

  # Toggle between everyone and per-user access
  def toggle_everyone!
    if share.everyone
      # Switching FROM everyone TO per-user: seed with all users, lock down
      users = User.all
      share.users_with_share_access = users
      share.users_with_write_access = users
      share.everyone = false
      share.rdonly = true
    else
      # Switching TO everyone: clear per-user lists, disable guest
      share.users_with_share_access = []
      share.users_with_write_access = []
      share.guest_access = false
      share.guest_writeable = false
      share.everyone = true
    end
    share.save
  end

  # Toggle read access for a specific user
  def toggle_access!(user_id)
    return if share.everyone

    user = User.find(user_id)
    if share.users_with_share_access.include?(user)
      share.users_with_share_access -= [user]
    else
      share.users_with_share_access += [user]
    end
    share.save
  end

  # Toggle write access for a specific user
  def toggle_write!(user_id)
    return if share.everyone

    user = User.find(user_id)
    if share.users_with_write_access.include?(user)
      share.users_with_write_access -= [user]
    else
      share.users_with_write_access += [user]
    end
    share.save
  end

  # Toggle guest read access
  def toggle_guest_access!
    if share.guest_access
      share.guest_access = false
    else
      share.guest_access = true
      share.guest_writeable = false  # force read-only as default
    end
    share.save
  end

  # Toggle guest write access
  def toggle_guest_writeable!
    share.guest_writeable = !share.guest_writeable
    share.save
  end
end
