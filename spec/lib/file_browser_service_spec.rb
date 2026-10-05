require 'rails_helper'

RSpec.describe FileBrowserService do
  describe '.list_directory' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(dir) }

    before do
      FileUtils.touch(File.join(dir, 'readme.md'))
      FileUtils.touch(File.join(dir, 'photo.jpg'))
      FileUtils.mkdir(File.join(dir, 'subdir'))
      FileUtils.touch(File.join(dir, '.hidden'))
    end

    it 'lists non-hidden entries' do
      result = described_class.list_directory(dir)
      names = result.map { |e| e[:name] }
      expect(names).to contain_exactly('subdir', 'photo.jpg', 'readme.md')
    end

    it 'sorts directories first' do
      result = described_class.list_directory(dir)
      expect(result.first[:name]).to eq('subdir')
      expect(result.first[:directory]).to be true
    end

    it 'includes mime type for files' do
      result = described_class.list_directory(dir)
      jpg = result.find { |e| e[:name] == 'photo.jpg' }
      expect(jpg[:mime]).to eq('image/jpeg')
    end

    it 'returns nil size for directories' do
      result = described_class.list_directory(dir)
      subdir = result.find { |e| e[:name] == 'subdir' }
      expect(subdir[:size]).to be_nil
    end
  end

  describe '.build_breadcrumbs' do
    it 'returns share root for empty path' do
      result = described_class.build_breadcrumbs('Photos', '')
      expect(result).to eq([{ name: 'Photos', path: '' }])
    end

    it 'builds nested breadcrumbs' do
      result = described_class.build_breadcrumbs('Photos', 'vacation/2024')
      expect(result).to eq([
        { name: 'Photos', path: '' },
        { name: 'vacation', path: 'vacation' },
        { name: '2024', path: 'vacation/2024' }
      ])
    end
  end

  describe '.detect_mime_type' do
    it 'returns correct mime for known extensions' do
      expect(described_class.detect_mime_type('photo.jpg')).to eq('image/jpeg')
      expect(described_class.detect_mime_type('doc.pdf')).to eq('application/pdf')
    end

    it 'returns octet-stream for unknown' do
      expect(described_class.detect_mime_type('file.xyz')).to eq('application/octet-stream')
    end
  end

  describe '.previewable?' do
    it 'returns true for small images' do
      expect(described_class.previewable?('image/jpeg', 1.megabyte)).to be true
    end

    it 'returns false for huge files' do
      expect(described_class.previewable?('image/jpeg', 60.megabytes)).to be false
    end

    it 'returns true for video' do
      expect(described_class.previewable?('video/mp4', 40.megabytes)).to be true
    end

    it 'returns false for unknown mime' do
      expect(described_class.previewable?('application/octet-stream', 1.megabyte)).to be false
    end
  end

  describe '.file_icon' do
    it 'returns folder icon for directories' do
      expect(described_class.file_icon('anything', true)).to eq('📁')
    end

    it 'returns correct icon for known extension' do
      expect(described_class.file_icon('song.mp3', false)).to eq('🎵')
    end

    it 'returns default icon for unknown extension' do
      expect(described_class.file_icon('file.xyz', false)).to eq('📄')
    end
  end

  describe '.resolve_path' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    it 'returns relative and full path' do
      relative, full = described_class.resolve_path(dir, 'subdir')
      expect(relative).to eq('subdir')
      expect(full).to eq(File.join(dir, 'subdir'))
    end

    it 'refuses directory traversal' do
      expect { described_class.resolve_path(dir, '../../etc/passwd') }.to raise_error(FileBrowserService::InvalidName)
    end

    it 'keeps folder names that contain two dots' do
      relative, _ = described_class.resolve_path(dir, 'v1..2/notes')
      expect(relative).to eq('v1..2/notes')
    end

    it 'collapses multiple slashes' do
      relative, _ = described_class.resolve_path(dir, 'a///b')
      expect(relative).to eq('a/b')
    end

    # A pooled share holds links to its files' copies on the Greyhole pool drives, in the
    # share's folder there.
    it "follows a pooled share's links into its folder on a pool drive, and nowhere else" do
      pool = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(pool, 'Photos'))
      File.write(File.join(pool, 'Photos', 'beach.jpg'), 'jpg')
      File.write(File.join(pool, 'secret.txt'), 'no')
      File.symlink(File.join(pool, 'Photos', 'beach.jpg'), File.join(dir, 'beach.jpg'))
      File.symlink(File.join(pool, 'secret.txt'), File.join(dir, 'secret.txt'))
      roots = [dir, File.join(pool, 'Photos')]

      expect(described_class.resolve_path(roots, 'beach.jpg')).to eq(['beach.jpg', File.join(dir, 'beach.jpg')])
      expect { described_class.resolve_path(roots, 'secret.txt') }.to raise_error(SecurityError)
      expect { described_class.resolve_path(dir, 'beach.jpg') }.to raise_error(SecurityError)
    ensure
      FileUtils.rm_rf(pool)
    end
  end

  describe '.create_zip' do
    let(:dir) { Dir.mktmpdir }
    let(:outside) { Dir.mktmpdir }
    after { FileUtils.rm_rf([dir, outside]) }

    it "zips the folder's files, leaving out links that point outside the share" do
      FileUtils.mkdir_p(File.join(dir, 'sub'))
      File.write(File.join(dir, 'a.txt'), 'A')
      File.write(File.join(dir, 'sub', 'b.txt'), 'B' * 100_000)
      File.write(File.join(outside, 'secret.env'), 'SECRET')
      File.symlink(File.join(outside, 'secret.env'), File.join(dir, 'link.env'))

      zip = described_class.create_zip(dir, [dir])
      require 'zip'
      entries = Zip::File.open(zip.path) { |z| z.entries.to_h { |e| [e.name, e.get_input_stream.read] } }
      expect(entries).to eq('a.txt' => 'A', 'sub/b.txt' => 'B' * 100_000)
    ensure
      zip&.close
    end

    it 'copies each file in pieces rather than reading it whole' do
      File.write(File.join(dir, 'big.bin'), 'x')
      expect(File).not_to receive(:read)
      described_class.create_zip(dir, [dir]).close
    end
  end
end
