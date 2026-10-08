require 'find'

# Disks → Pool Trash: the files deleted from pooled shares, and the old versions of files
# changed there, which Greyhole keeps in <drive>/.gh_trash/<share>/<path> on each pool drive
# that had a copy, until the trash is emptied. Reading it needs no root (Greyhole makes the
# trash's folders readable by everyone); restoring, deleting and emptying go through the root
# helper (greyhole.trash_*).
module GreyholeTrash
  FOLDER = '.gh_trash'.freeze
  # The most the page lists, newest first.
  LIMIT = 1000

  # One file in the trash: its share and path there, its size in bytes, when it went to the trash (its
  # newest copy's), and how many drives keep a copy.
  Item = Struct.new(:share, :path, :bytes, :trashed_at, :copies, keyword_init: true) do
    # The room its copies take on the drives.
    def space
      bytes * copies
    end
  end

  class << self
    # { items: [Item] (the newest LIMIT), count:, space: } for the trash on the pool's drives.
    def contents(drives = DiskPoolPartition.pluck(:path))
      found = {}
      drives.each do |drive|
        root = File.join(drive, FOLDER)
        next unless File.directory?(root) && !File.symlink?(root)
        Find.find(root) do |entry|
          stat = File.lstat(entry) # Find doesn't follow links, and nor does this
          next unless stat.file?
          share, path = entry.delete_prefix("#{root}/").split('/', 2)
          next if path.nil?
          item = found[[share, path]] ||= Item.new(share: share, path: path, bytes: 0, trashed_at: stat.ctime, copies: 0)
          item.copies += 1
          item.bytes = [item.bytes, stat.size].max
          item.trashed_at = [item.trashed_at, stat.ctime].max
        rescue SystemCallError
          next
        end
      end
      items = found.values.sort_by { |item| [-item.trashed_at.to_f, item.share, item.path] }
      { items: items.first(LIMIT), count: items.size, space: items.sum(&:space) }
    end

    # Puts a file back into its share, with its copies, through Greyhole. Raises
    # Privileged::Error with the helper's reason (the share isn't pooled any more, or has a
    # file by that name now).
    def restore!(share, path)
      Privileged.call('greyhole.trash_restore', share: share.to_s, path: path.to_s)
    end

    # Deletes a file from the trash, every copy of it.
    def delete!(share, path)
      Privileged.call('greyhole.trash_delete', share: share.to_s, path: path.to_s)
    end

    # Empties the trash on every pool drive.
    def empty!
      Privileged.call('greyhole.trash_empty')
    end
  end
end
