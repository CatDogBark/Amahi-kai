require 'find'
require 'fileutils'

# The Trash (Shares → Trash, admins): every share's deleted files, kept until they've been
# there longer than the Trash keeps them (days, one setting), then deleted by
# amahi-kai-trash.timer (the root helper's trash.expire).
#
# - A pooled share's (kind :pool): Greyhole keeps the old copy of a file deleted or changed
#   there in <drive>/.gh_trash/<share>/<path> on each pool drive that had one. Greyhole
#   makes those folders readable by everyone; restoring and deleting go through the root
#   helper (greyhole.trash_*).
# - Any other share's (kind :share): Samba's recycle bin (Share#share_conf) moves a deleted
#   file to <share folder>/.recycle/<path>, in folders the users group (Amahi-kai's account
#   among them) can change, so the app restores and deletes those itself.
module Trash
  class Error < StandardError; end

  POOL = '.gh_trash'.freeze
  RECYCLE = '.recycle'.freeze
  # How long it keeps files unless set otherwise, and the choices offered. 0 keeps them.
  DEFAULT_DAYS = 30
  DAY_CHOICES = [7, 14, 30, 60, 90, 0].freeze
  # The root helper's copy of the setting, which amahi-kai-trash.timer reads.
  DAYS_FILE = '/etc/amahi-kai/trash-days'.freeze
  # The most the page lists, newest first.
  LIMIT = 1000

  # One file in the trash: its share and path there, its size in bytes, when it went to the
  # trash (its newest copy's), and how many drives keep a copy (1 for a share's recycle bin).
  Item = Struct.new(:kind, :share, :path, :bytes, :trashed_at, :copies, keyword_init: true) do
    # The room its copies take.
    def space
      bytes * copies
    end
  end

  class << self
    # { items: [Item] (the newest LIMIT), count:, space: } for the pool drives' trash and every
    # other share's recycle bin.
    def contents(drives: DiskPoolPartition.pluck(:path), shares: Share.where(disk_pool_copies: 0).to_a)
      found = {}
      drives.each do |drive|
        walk(File.join(drive, POOL)) do |relative, stat|
          share, path = relative.split('/', 2)
          add(found, :pool, share, path, stat) if path
        end
      end
      shares.each do |share|
        walk(File.join(share.path, RECYCLE)) { |path, stat| add(found, :share, share.name, path, stat) }
      end
      items = found.values.sort_by { |item| [-item.trashed_at.to_f, item.share, item.path] }
      { items: items.first(LIMIT), count: items.size, space: items.sum(&:space) }
    end

    # Puts a file back where it was. Raises Trash::Error (or Privileged::Error, with the root
    # helper's reason, for a pooled share's).
    def restore!(kind, share_name, path)
      return Privileged.call('greyhole.trash_restore', share: share_name.to_s, path: path.to_s) if kind.to_s == 'pool'
      share, source = recycled(share_name, path)
      target = File.join(share.path, path)
      raise Error, "#{share.name} has a #{path} now: rename or move it, then restore" if File.exist?(target) || File.symlink?(target)
      FileUtils.mkdir_p(File.dirname(target))
      raise Error, "#{share.name}/#{path} can't go back there" unless inside?(share.path, File.dirname(target))
      File.rename(source, target)
      prune(File.join(share.path, RECYCLE), File.dirname(source))
    rescue SystemCallError => e
      raise Error, "couldn't restore #{share_name}/#{path}: #{e.message}"
    end

    # Deletes a file from the trash for good, every copy of it.
    def delete!(kind, share_name, path)
      return Privileged.call('greyhole.trash_delete', share: share_name.to_s, path: path.to_s) if kind.to_s == 'pool'
      share, source = recycled(share_name, path)
      File.unlink(source)
      prune(File.join(share.path, RECYCLE), File.dirname(source))
    rescue SystemCallError => e
      raise Error, "couldn't delete #{share_name}/#{path}: #{e.message}"
    end

    # Empties every share's trash: Greyhole's on the pool drives, and each recycle bin.
    def empty!
      Privileged.call('greyhole.trash_empty') if Greyhole.installed? && DiskPoolPartition.exists?
      Share.where(disk_pool_copies: 0).find_each do |share|
        bin = File.join(share.path, RECYCLE)
        next unless File.directory?(bin) && !File.symlink?(bin)
        Dir.children(bin).each { |child| FileUtils.rm_rf(File.join(bin, child)) } # rm_rf doesn't follow links
      end
    rescue SystemCallError => e
      raise Error, "couldn't empty the trash: #{e.message}"
    end

    # How many days the Trash keeps files (0: until it's emptied).
    def days
      value = File.read(days_file).strip
      value.match?(/\A\d{1,4}\z/) ? value.to_i : DEFAULT_DAYS
    rescue SystemCallError
      DEFAULT_DAYS
    end

    def set_days!(days)
      days = Integer(days, exception: false)
      raise Error, 'choose one of the lengths offered' unless DAY_CHOICES.include?(days)
      Privileged.call('trash.set_days', days: days)
    end

    def days_file
      Rails.env.production? ? DAYS_FILE : Rails.root.join('tmp', 'trash-days').to_s
    end

    private

    # Yields [path in the folder, lstat] for each file under a trash folder, links not followed.
    def walk(root)
      return unless File.directory?(root) && !File.symlink?(root)
      Find.find(root) do |entry|
        stat = File.lstat(entry)
        yield entry.delete_prefix("#{root}/"), stat if stat.file?
      rescue SystemCallError
        next
      end
    end

    def add(found, kind, share, path, stat)
      item = found[[kind, share, path]] ||= Item.new(kind: kind, share: share, path: path, bytes: 0, trashed_at: stat.ctime, copies: 0)
      item.copies += 1
      item.bytes = [item.bytes, stat.size].max
      item.trashed_at = [item.trashed_at, stat.ctime].max
    end

    # The share, and the file in its recycle bin: a file there, reached through no link.
    def recycled(share_name, path)
      share = Share.find_by(name: share_name.to_s) or raise Error, "there's no share #{share_name}"
      path = path.to_s
      raise Error, "#{path.inspect} isn't a file in the trash" unless relative?(path)
      bin = File.join(share.path, RECYCLE)
      source = File.join(bin, path)
      unless File.file?(source) && !File.symlink?(source) && File.realpath(source) == File.join(File.realpath(bin), path)
        raise Error, "#{share.name}/#{path} isn't in the trash"
      end
      [share, source]
    rescue Errno::ENOENT
      raise Error, "#{share_name}/#{path} isn't in the trash"
    end

    def relative?(path)
      !path.empty? && !path.start_with?('/') && path.split('/').none? { |part| part.empty? || part == '.' || part == '..' }
    end

    def inside?(root, path)
      real = File.realpath(path)
      real == File.realpath(root) || real.start_with?("#{File.realpath(root)}/")
    end

    # Removes the folders a restore or delete left empty, up to the recycle bin itself.
    def prune(bin, dir)
      while dir.start_with?("#{bin}/") && Dir.empty?(dir)
        Dir.rmdir(dir)
        dir = File.dirname(dir)
      end
    rescue SystemCallError
      nil
    end
  end
end
