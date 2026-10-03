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

  describe '.upload_files' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    it 'writes the upload into the folder' do
      file = double('upload', original_filename: 'test file.txt', read: 'content')
      result = described_class.upload_files(dir, [file])
      expect(result).to eq(['test file.txt'])
      expect(File.read(File.join(dir, 'test file.txt'))).to eq('content')
    end

    it 'streams from the uploaded tempfile and keeps only the file name' do
      tempfile = Tempfile.new('upload').tap { |f| f.write('big data'); f.flush }
      file = double('upload', original_filename: 'C:\\Users\\troy\\report.pdf', tempfile: tempfile)
      expect(described_class.upload_files(dir, [file])).to eq(['report.pdf'])
      expect(File.read(File.join(dir, 'report.pdf'))).to eq('big data')
    ensure
      tempfile&.close!
    end

    it 'skips objects without original_filename' do
      result = described_class.upload_files(dir, ['not a file'])
      expect(result).to eq([])
    end

    it 'skips existing files without overwrite flag' do
      FileUtils.touch(File.join(dir, 'exists.txt'))
      file = double('upload', original_filename: 'exists.txt', read: 'new')
      result = described_class.upload_files(dir, [file])
      expect(result).to eq([])
    end

    it 'overwrites with overwrite flag' do
      FileUtils.touch(File.join(dir, 'exists.txt'))
      file = double('upload', original_filename: 'exists.txt', read: 'new')
      result = described_class.upload_files(dir, [file], overwrite: true)
      expect(result).to eq(['exists.txt'])
    end
  end

  describe '.create_folder' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    it 'creates the folder' do
      result = described_class.create_folder(dir, 'New Folder')
      expect(result).to eq('New Folder')
      expect(File.directory?(File.join(dir, 'New Folder'))).to be true
    end

    it 'refuses a folder named ..' do
      expect { described_class.create_folder(dir, '..') }.to raise_error(FileBrowserService::InvalidName)
    end

    it 'raises if folder already exists' do
      FileUtils.mkdir(File.join(dir, 'exists'))
      expect { described_class.create_folder(dir, 'exists') }.to raise_error('Already exists')
    end
  end

  describe '.rename_entry' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    before { FileUtils.touch(File.join(dir, 'old.txt')) }

    it 'renames the entry' do
      result = described_class.rename_entry(dir, 'old.txt', 'new.txt')
      expect(result).to eq({ old_name: 'old.txt', new_name: 'new.txt' })
      expect(File.exist?(File.join(dir, 'new.txt'))).to be true
    end

    it 'raises if source not found' do
      expect { described_class.rename_entry(dir, 'missing.txt', 'new.txt') }.to raise_error('Not found')
    end

    it 'renames a file whose name contains two dots, not a different one' do
      FileUtils.touch([File.join(dir, 'a..b.txt'), File.join(dir, 'ab.txt')])
      described_class.rename_entry(dir, 'a..b.txt', 'renamed.txt')
      expect(File.exist?(File.join(dir, 'ab.txt'))).to be true
      expect(File.exist?(File.join(dir, 'renamed.txt'))).to be true
    end

    it 'raises if target exists' do
      FileUtils.touch(File.join(dir, 'new.txt'))
      expect { described_class.rename_entry(dir, 'old.txt', 'new.txt') }.to raise_error('Name already taken')
    end
  end

  describe '.delete_entries' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    before do
      FileUtils.touch(File.join(dir, 'file.txt'))
      FileUtils.mkdir(File.join(dir, 'folder'))
    end

    it 'deletes files and folders' do
      result = described_class.delete_entries(dir, ['file.txt', 'folder'])
      expect(result).to contain_exactly('file.txt', 'folder')
    end

    it 'skips nonexistent entries' do
      result = described_class.delete_entries(dir, ['missing'])
      expect(result).to eq([])
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

  describe '.check_name!' do
    it 'accepts ordinary names, including ones with dots' do
      expect(described_class.check_name!('a..b.txt')).to eq('a..b.txt')
      expect(described_class.check_name!(' notes 12:30.txt ')).to eq('notes 12:30.txt')
    end

    it 'refuses names it would otherwise have to rewrite' do
      ['..', '.', '', 'a/b', 'a\\b', "nul\x00.txt", 'x' * 256].each do |name|
        expect { described_class.check_name!(name) }.to raise_error(FileBrowserService::InvalidName), name.inspect
      end
    end
  end

  describe '.safe_join' do
    let(:dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(dir) }

    it 'joins paths safely' do
      FileUtils.touch(File.join(dir, 'file.txt'))
      expect(described_class.safe_join(dir, 'file.txt')).to eq(File.join(dir, 'file.txt'))
    end

    it 'refuses a symlink to a sibling folder whose name starts the same' do
      share = File.join(dir, 'movies')
      FileUtils.mkdir_p([share, File.join(dir, 'movies-private')])
      File.symlink(File.join(dir, 'movies-private'), File.join(share, 'peek'))
      expect { described_class.safe_join(share, 'peek') }.to raise_error(SecurityError)
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
  end
end
