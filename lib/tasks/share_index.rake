require 'share_indexer'

namespace :shares do
  desc "Full reindex of all share files (wipe and rebuild)"
  task reindex: :environment do
    count = ShareIndexer.full_reindex
    puts "Indexed #{count} files across all shares"
  end

  desc "Quick incremental update (add new, remove deleted, update changed)"
  task update_index: :environment do
    result = ShareIndexer.quick_update
    puts "Quick update: added #{result[:added]}, removed #{result[:removed]}, updated #{result[:updated]}"
  end

  desc "Remove stale index entries for files that no longer exist"
  task clean_index: :environment do
    removed = ShareIndexer.remove_stale
    puts "Removed #{removed} stale entries"
  end
end
