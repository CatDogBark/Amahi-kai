require 'rails_helper'

# The Trash: Greyhole's on the pool drives, and each other share's recycle bin.
RSpec.describe Trash do
  let(:drives) { [Dir.mktmpdir, Dir.mktmpdir] }
  let(:folder) { Dir.mktmpdir }
  let!(:share) { create(:share, name: 'Docs', path: folder, disk_pool_copies: 0) }

  before { allow(Share).to receive(:push_shares) }
  after { FileUtils.rm_rf([*drives, folder]) }

  def put(root, relative, content, at: nil)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.utime(at.to_time, at.to_time, path) if at
    path
  end

  it "lists each file once, newest first, from the pool drives and the shares' recycle bins" do
    put(drives[0], '.gh_trash/Photos/2026/beach.jpg', 'x' * 300)
    put(drives[1], '.gh_trash/Photos/2026/beach.jpg', 'x' * 300)
    put(folder, '.recycle/reports/q3.odt', 'x' * 50)
    File.symlink('/etc/hostname', File.join(drives[1], '.gh_trash', 'Photos', 'link'))
    File.symlink('/etc/hostname', File.join(folder, '.recycle', 'link'))
    File.write(File.join(drives[1], '.gh_trash', 'stray'), 'x') # not in a share's folder

    result = described_class.contents(drives: drives, shares: [share])
    expect(result).to include(count: 2, space: 650)
    expect(result[:items].map { |i| [i.kind, i.share, i.path, i.bytes, i.copies] })
      .to contain_exactly([:pool, 'Photos', '2026/beach.jpg', 300, 2], [:share, 'Docs', 'reports/q3.odt', 50, 1])
  end

  it 'is empty without trash folders, and lists at most LIMIT' do
    expect(described_class.contents(drives: drives, shares: [share])).to eq(items: [], count: 0, space: 0)
    stub_const('Trash::LIMIT', 1)
    put(folder, '.recycle/a.txt', 'a')
    put(folder, '.recycle/b.txt', 'b')
    expect(described_class.contents(drives: drives, shares: [share])).to include(count: 2, space: 2)
    expect(described_class.contents(drives: drives, shares: [share])[:items].size).to eq(1)
  end

  describe "a share's recycle bin" do
    it 'restores a file where it was, making its folder again, and tidies the bin' do
      put(folder, '.recycle/reports/2026/q3.odt', 'report')
      described_class.restore!('share', 'Docs', 'reports/2026/q3.odt')
      expect(File.read(File.join(folder, 'reports/2026/q3.odt'))).to eq('report')
      expect(Dir.children(File.join(folder, '.recycle'))).to be_empty
    end

    it "won't restore over a file there now, or anything reached through a link or outside the bin" do
      put(folder, '.recycle/q3.odt', 'old')
      put(folder, 'q3.odt', 'new')
      expect { described_class.restore!('share', 'Docs', 'q3.odt') }.to raise_error(Trash::Error, 'Docs has a q3.odt now: rename or move it, then restore')
      outside = Dir.mktmpdir
      File.write(File.join(outside, 'secret'), 's')
      File.symlink(outside, File.join(folder, '.recycle', 'out'))
      expect { described_class.restore!('share', 'Docs', 'out/secret') }.to raise_error(Trash::Error, "Docs/out/secret isn't in the trash")
      expect { described_class.delete!('share', 'Docs', '../q3.odt') }.to raise_error(Trash::Error, /isn't a file in the trash/)
      expect { described_class.delete!('share', 'Nope', 'q3.odt') }.to raise_error(Trash::Error, "there's no share Nope")
      expect(File.exist?(File.join(outside, 'secret'))).to be true
    ensure
      FileUtils.rm_rf(outside) if outside
    end

    it 'deletes a file for good, and empties every bin' do
      put(folder, '.recycle/a/one.txt', '1')
      put(folder, '.recycle/two.txt', '2')
      described_class.delete!('share', 'Docs', 'a/one.txt')
      expect(Dir.children(File.join(folder, '.recycle'))).to eq(['two.txt'])
      described_class.empty!
      expect(Dir.children(File.join(folder, '.recycle'))).to be_empty
    end
  end

  it "restores, deletes and empties a pooled share's through the root helper" do
    create(:disk_pool_partition, path: '/mnt/storage-1')
    described_class.restore!('pool', 'Photos', '2026/beach.jpg')
    described_class.delete!('pool', 'Photos', '2026/beach.jpg')
    described_class.empty!
    expect(Privileged.calls).to eq([['greyhole.trash_restore', { share: 'Photos', path: '2026/beach.jpg' }],
                                    ['greyhole.trash_delete', { share: 'Photos', path: '2026/beach.jpg' }],
                                    ['greyhole.trash_empty', {}]])
  end

  it 'keeps files 30 days unless set otherwise, through the root helper' do
    FileUtils.rm_f(described_class.days_file)
    expect(described_class.days).to eq(30)
    File.write(described_class.days_file, "7\n")
    expect(described_class.days).to eq(7)
    described_class.set_days!('0')
    expect(Privileged.calls).to eq([['trash.set_days', { days: 0 }]])
    expect { described_class.set_days!('45') }.to raise_error(Trash::Error, /lengths offered/)
  ensure
    FileUtils.rm_f(described_class.days_file)
  end
end
