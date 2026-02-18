# ShareIndexer — scans share directories and maintains the ShareFile index
#
# Usage:
#   ShareIndexer.full_reindex          # Rebuild entire index from scratch
#   ShareIndexer.index_share(share)    # Reindex a single share
#   ShareIndexer.remove_stale          # Remove entries for files that no longer exist
#   ShareIndexer.quick_update          # Incremental: add new, remove deleted, update changed
#
# Designed to be called from:
#   - A Rake task (bin/rails shares:reindex)
#   - A background job
#   - After share create/destroy callbacks

class ShareIndexer
  BATCH_SIZE = 500

  class << self

    # Full reindex: wipe and rebuild everything
    def full_reindex
      Rails.logger.info("ShareIndexer: starting full reindex")
      total = 0

      Share.find_each do |share|
        count = index_share(share, clear_first: true)
        total += count
      end

      # Remove entries for shares that no longer exist
      orphan_share_ids = ShareFile.distinct.pluck(:share_id) - Share.pluck(:id)
      ShareFile.where(share_id: orphan_share_ids).delete_all if orphan_share_ids.any?

      Rails.logger.info("ShareIndexer: full reindex complete — #{total} files indexed")
      total
    end

    # Index a single share
    def index_share(share, clear_first: false)
      root = share.path
      unless root.present? && File.directory?(root)
        Rails.logger.warn("ShareIndexer: share '#{share.name}' path '#{root}' is not a directory, skipping")
        return 0
      end

      ShareFile.where(share_id: share.id).delete_all if clear_first

      count = 0
      batch = []

      walk_directory(root) do |full_path|
        entry = ShareFile.build_from_path(share, full_path, root)
        next unless entry

        batch << entry
        if batch.size >= BATCH_SIZE
          upsert_batch(batch, share.id)
          count += batch.size
          batch = []
        end
      end

      # Flush remaining
      if batch.any?
        upsert_batch(batch, share.id)
        count += batch.size
      end

      Rails.logger.info("ShareIndexer: indexed #{count} files in share '#{share.name}'")
      count
    end

    # Quick incremental update: scan for new/changed/deleted files
    def quick_update
      Rails.logger.info("ShareIndexer: starting quick update")
      added = 0
      removed = 0
      updated = 0

      Share.find_each do |share|
        root = share.path
        next unless root.present? && File.directory?(root)

        # Get current filesystem state
        fs_paths = Set.new
        walk_directory(root) { |p| fs_paths << p }

        # Get current index state
        indexed = ShareFile.where(share_id: share.id).pluck(:path, :id, :file_modified_at)
        indexed_paths = {}
        indexed.each { |path, id, mtime| indexed_paths[path] = { id: id, mtime: mtime } }

        # Find new files (in filesystem but not in index)
        new_paths = fs_paths - indexed_paths.keys.to_set
        batch = []
        new_paths.each do |full_path|
          entry = ShareFile.build_from_path(share, full_path, root)
          next unless entry
          batch << entry
          if batch.size >= BATCH_SIZE
            upsert_batch(batch, share.id)
            added += batch.size
            batch = []
          end
        end
        if batch.any?
          upsert_batch(batch, share.id)
          added += batch.size
        end

        # Find deleted files (in index but not in filesystem)
        deleted_paths = indexed_paths.keys.to_set - fs_paths
        if deleted_paths.any?
          ids_to_delete = deleted_paths.map { |p| indexed_paths[p][:id] }
          ShareFile.where(id: ids_to_delete).delete_all
          removed += ids_to_delete.size
        end

        # Find changed files (mtime differs)
        common_paths = fs_paths & indexed_paths.keys.to_set
        common_paths.each do |full_path|
          begin
            stat = File.stat(full_path)
            db_mtime = indexed_paths[full_path][:mtime]
            if db_mtime.nil? || stat.mtime.to_i != db_mtime.to_i
              entry = ShareFile.build_from_path(share, full_path, root)
              if entry
                existing = ShareFile.find(indexed_paths[full_path][:id])
                existing.update(
                  size: entry.size,
                  file_modified_at: entry.file_modified_at,
                  extension: entry.extension,
                  content_type: entry.content_type
                )
                updated += 1
              end
            end
          rescue Errno::ENOENT, Errno::EACCES
            # File disappeared between scan and stat
          end
        end
      end

      Rails.logger.info("ShareIndexer: quick update complete — added: #{added}, removed: #{removed}, updated: #{updated}")
      { added: added, removed: removed, updated: updated }
    end

    # Remove entries for files that no longer exist on disk
    def remove_stale
      removed = 0
      ShareFile.find_each do |sf|
        unless File.exist?(sf.path)
          sf.destroy
          removed += 1
        end
      end
      Rails.logger.info("ShareIndexer: removed #{removed} stale entries")
      removed
    end

    private

    # Walk a directory tree, yielding each file and subdirectory path
    def walk_directory(root, &block)
      return unless File.directory?(root)
      Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).each do |path|
        # Skip . and .. entries
        basename = File.basename(path)
        next if basename == '.' || basename == '..'
        yield path
      end
    rescue Errno::EACCES => e
      Rails.logger.warn("ShareIndexer: access denied walking #{root}: #{e.message}")
    end

    # Batch upsert using Rails 7+ upsert_all
    def upsert_batch(entries, share_id)
      records = entries.compact.map do |e|
        {
          share_id: e.share_id,
          name: e.name,
          path: e.path,
          relative_path: e.relative_path,
          extension: e.extension,
          content_type: e.content_type,
          size: e.size,
          directory: e.directory,
          file_modified_at: e.file_modified_at,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
      return if records.empty?

      ShareFile.upsert_all(
        records,
        unique_by: [:share_id, :relative_path],
        update_only: [:name, :extension, :content_type, :size, :directory, :file_modified_at, :updated_at]
      )
    rescue => e
      Rails.logger.error("ShareIndexer: upsert failed: #{e.message}")
      # Fallback: insert one by one
      entries.compact.each do |entry|
        begin
          existing = ShareFile.find_by(share_id: entry.share_id, relative_path: entry.relative_path)
          if existing
            existing.update(size: entry.size, file_modified_at: entry.file_modified_at,
                          extension: entry.extension, content_type: entry.content_type)
          else
            entry.save
          end
        rescue => inner
          Rails.logger.warn("ShareIndexer: skipping entry: #{inner.message}")
        end
      end
    end

  end
end
