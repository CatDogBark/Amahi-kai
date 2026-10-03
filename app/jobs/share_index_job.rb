require 'share_indexer'

# Indexes a new share's files for search. Runs on Active Job's in-process queue,
# which manages its own database connection (a bare Thread.new did not).
class ShareIndexJob < ApplicationJob
  queue_as :default

  def perform(share_id)
    share = Share.find_by(id: share_id)
    ShareIndexer.index_share(share) if share
  rescue Errno::ENOENT, Errno::EACCES, IOError => e
    Rails.logger.error("ShareIndexJob failed for share #{share_id}: #{e.message}")
  end
end
