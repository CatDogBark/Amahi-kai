require 'rails_helper'
require 'share_indexer'

RSpec.describe ShareIndexer do
  let(:tmpdir) { Dir.mktmpdir('share_indexer_test') }

  # Create share without triggering callbacks that need system commands
  let(:share) do
    Share.new(name: "TestShare", path: tmpdir, rdonly: false, visible: true, everyone: true, tags: "test").tap do |s|
      s.save(validate: false)
    end
  end

  after do
    FileUtils.remove_entry(tmpdir, true)
  end

  def create_file(dir, name, content: 'hello', mtime: nil)
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.utime(Time.now, mtime, path) if mtime
    path
  end

  describe '.index_share' do
    it 'indexes files in a directory' do
      create_file(tmpdir, 'file1.txt')
      create_file(tmpdir, 'file2.mp3')

      count = ShareIndexer.index_share(share)
      expect(count).to eq(2)
      expect(ShareFile.where(share_id: share.id).count).to eq(2)
    end

    it 'indexes subdirectories and nested files' do
      create_file(tmpdir, 'subdir/nested.txt')

      count = ShareIndexer.index_share(share)
      # Should index both the subdir and the file
      expect(count).to be >= 2
      expect(ShareFile.where(share_id: share.id, directory: true).count).to be >= 1
    end

    it 'returns 0 for empty directories' do
      count = ShareIndexer.index_share(share)
      expect(count).to eq(0)
    end

    it 'clears existing records when clear_first is true' do
      create_file(tmpdir, 'file1.txt')
      ShareIndexer.index_share(share)

      # Remove file, re-index with clear
      File.delete(File.join(tmpdir, 'file1.txt'))
      create_file(tmpdir, 'file2.txt')
      count = ShareIndexer.index_share(share, clear_first: true)
      expect(count).to eq(1)
      expect(ShareFile.where(share_id: share.id).pluck(:name)).to eq(['file2.txt'])
    end

    it 'does not clear existing records when clear_first is false' do
      create_file(tmpdir, 'file1.txt')
      ShareIndexer.index_share(share)

      create_file(tmpdir, 'file2.txt')
      ShareIndexer.index_share(share, clear_first: false)
      expect(ShareFile.where(share_id: share.id).count).to be >= 2
    end

    it 'returns 0 and logs warning for non-existent directory' do
      share.update_column(:path, '/tmp/nonexistent_share_path_xyz')
      count = ShareIndexer.index_share(share)
      expect(count).to eq(0)
    end

    it 'returns 0 when path is blank' do
      share.update_column(:path, '')
      count = ShareIndexer.index_share(share)
      expect(count).to eq(0)
    end

    it 'sets correct attributes on ShareFile records' do
      create_file(tmpdir, 'document.pdf', content: 'PDF content here')

      ShareIndexer.index_share(share)
      sf = ShareFile.find_by(share_id: share.id, name: 'document.pdf')
      expect(sf).not_to be_nil
      expect(sf.extension).to eq('pdf')
      expect(sf.content_type).to eq('document')
      expect(sf.size).to eq(16)
      expect(sf.directory).to be false
      expect(sf.relative_path).to eq('document.pdf')
      expect(sf.path).to eq(File.join(tmpdir, 'document.pdf'))
    end
  end

  describe '.full_reindex' do
    it 'indexes all shares' do
      share # ensure share record exists
      create_file(tmpdir, 'file1.txt')

      total = ShareIndexer.full_reindex
      expect(total).to be >= 1
    end

    it 'handles empty shares gracefully' do
      expect { ShareIndexer.full_reindex }.not_to raise_error
    end

    it 'removes orphan share_file entries for deleted shares' do
      create_file(tmpdir, 'file1.txt')
      ShareIndexer.index_share(share)

      # Create an orphan entry with a fake share_id
      orphan_share = Share.new(name: "GhostShare", path: "/tmp/nonexistent_share", rdonly: false, visible: true, everyone: true, tags: "").tap { |s| s.save(validate: false) }
      ShareFile.create!(
        share_id: orphan_share.id,
        name: 'orphan.txt',
        path: '/tmp/orphan.txt',
        relative_path: 'orphan.txt'
      )
      orphan_id = orphan_share.id
      orphan_share.delete

      ShareIndexer.full_reindex
      expect(ShareFile.where(share_id: orphan_id).count).to eq(0)
    end
  end

  describe '.quick_update' do
    it 'detects new files' do
      create_file(tmpdir, 'existing.txt')
      ShareIndexer.index_share(share)

      create_file(tmpdir, 'new_file.txt')
      result = ShareIndexer.quick_update
      expect(result[:added]).to be >= 1
    end

    it 'detects removed files' do
      path = create_file(tmpdir, 'to_delete.txt')
      ShareIndexer.index_share(share)

      File.delete(path)
      result = ShareIndexer.quick_update
      expect(result[:removed]).to be >= 1
    end

    it 'detects changed files (mtime)' do
      create_file(tmpdir, 'changing.txt', mtime: Time.now - 3600)
      ShareIndexer.index_share(share)

      # Update the file with a new mtime
      create_file(tmpdir, 'changing.txt', content: 'updated content', mtime: Time.now)
      result = ShareIndexer.quick_update
      expect(result[:updated]).to be >= 1
    end

    it 'returns a hash with added, removed, updated keys' do
      result = ShareIndexer.quick_update
      expect(result).to have_key(:added)
      expect(result).to have_key(:removed)
      expect(result).to have_key(:updated)
    end

    it 'skips shares with non-existent paths' do
      share.update_column(:path, '/tmp/nonexistent_quick_update_xyz')
      result = ShareIndexer.quick_update
      expect(result[:added]).to eq(0)
    end
  end

  describe '.remove_stale' do
    it 'removes entries for files that no longer exist on disk' do
      path = create_file(tmpdir, 'will_vanish.txt')
      ShareIndexer.index_share(share)
      expect(ShareFile.where(share_id: share.id).count).to be >= 1

      File.delete(path)
      removed = ShareIndexer.remove_stale
      expect(removed).to be >= 1
      expect(ShareFile.where(share_id: share.id, name: 'will_vanish.txt').count).to eq(0)
    end

    it 'keeps entries for files that still exist' do
      create_file(tmpdir, 'still_here.txt')
      ShareIndexer.index_share(share)

      removed = ShareIndexer.remove_stale
      expect(removed).to eq(0)
      expect(ShareFile.where(share_id: share.id, name: 'still_here.txt').count).to eq(1)
    end
  end

  describe 'walk_directory (via index_share)' do
    it 'skips . and .. entries' do
      create_file(tmpdir, 'real_file.txt')
      ShareIndexer.index_share(share)
      names = ShareFile.where(share_id: share.id).pluck(:name)
      expect(names).not_to include('.', '..')
    end

    it 'handles deeply nested directories' do
      create_file(tmpdir, 'a/b/c/deep.txt')
      count = ShareIndexer.index_share(share)
      expect(count).to be >= 4 # a, b, c dirs + deep.txt
    end

    it 'handles permission errors gracefully' do
      # Create a directory that can't be read
      restricted = File.join(tmpdir, 'restricted')
      FileUtils.mkdir(restricted)
      File.chmod(0o000, restricted)

      expect { ShareIndexer.index_share(share) }.not_to raise_error

      # Restore permissions for cleanup
      File.chmod(0o755, restricted)
    end
  end

  describe 'upsert_batch (via index_share)' do
    it 'handles duplicate relative_paths via upsert' do
      create_file(tmpdir, 'dup.txt', content: 'v1')
      ShareIndexer.index_share(share)

      # Re-index without clearing — upsert should handle duplicates
      create_file(tmpdir, 'dup.txt', content: 'v2 longer')
      expect { ShareIndexer.index_share(share, clear_first: false) }.not_to raise_error
      expect(ShareFile.where(share_id: share.id, name: 'dup.txt').count).to eq(1)
    end

    it 'handles large batches' do
      20.times { |i| create_file(tmpdir, "file_#{i}.txt") }
      # Use a smaller batch size temporarily isn't easy, but we can at least verify it works
      count = ShareIndexer.index_share(share)
      expect(count).to eq(20)
    end
  end

  describe 'BATCH_SIZE' do
    it 'is defined as a positive integer' do
      expect(ShareIndexer::BATCH_SIZE).to be_a(Integer)
      expect(ShareIndexer::BATCH_SIZE).to be > 0
    end
  end
end
