require 'rails_helper'

# Disks → Pool Trash: what Greyhole keeps of files deleted from pooled shares.
RSpec.describe GreyholeTrash do
  let(:drives) { [Dir.mktmpdir, Dir.mktmpdir] }

  after { FileUtils.rm_rf(drives) }

  def trash(drive, relative, content, at:)
    path = File.join(drive, '.gh_trash', relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.utime(at.to_time, at.to_time, path)
    path
  end

  it 'lists each file once, newest first, with its size, copies and the room they take' do
    trash(drives[0], 'Photos/2026/beach.jpg', 'x' * 300, at: 2.days.ago)
    trash(drives[1], 'Photos/2026/beach.jpg', 'x' * 300, at: 2.days.ago)
    trash(drives[0], 'Docs/notes.odt', 'x' * 50, at: 1.day.ago)
    File.symlink('/etc/hostname', File.join(drives[1], '.gh_trash', 'Photos', 'link'))
    File.write(File.join(drives[1], '.gh_trash', 'stray'), 'x') # not in a share's folder

    result = described_class.contents(drives)
    expect(result[:count]).to eq(2)
    expect(result[:space]).to eq(650)
    expect(result[:items].map { |i| [i.share, i.path, i.bytes, i.copies] })
      .to contain_exactly(['Photos', '2026/beach.jpg', 300, 2], ['Docs', 'notes.odt', 50, 1])
    expect(result[:items].first.trashed_at).to be_within(5.seconds).of(Time.current) # ctime: when it went in
  end

  it 'is empty without a trash folder, and lists at most LIMIT' do
    expect(described_class.contents(drives)).to eq(items: [], count: 0, space: 0)
    stub_const('GreyholeTrash::LIMIT', 1)
    trash(drives[0], 'Docs/a.txt', 'a', at: 1.day.ago)
    trash(drives[0], 'Docs/b.txt', 'b', at: 1.day.ago)
    expect(described_class.contents(drives)).to include(count: 2, space: 2)
    expect(described_class.contents(drives)[:items].size).to eq(1)
  end

  it 'restores, deletes and empties through the root helper' do
    described_class.restore!('Photos', '2026/beach.jpg')
    described_class.delete!('Docs', 'notes.odt')
    described_class.empty!
    expect(Privileged.calls).to eq([['greyhole.trash_restore', { share: 'Photos', path: '2026/beach.jpg' }],
                                    ['greyhole.trash_delete', { share: 'Docs', path: 'notes.odt' }],
                                    ['greyhole.trash_empty', {}]])
  end
end
