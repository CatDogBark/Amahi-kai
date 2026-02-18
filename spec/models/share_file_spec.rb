require 'spec_helper'

describe ShareFile, type: :model do
  describe 'validations' do
    it 'requires name, path, and relative_path' do
      sf = ShareFile.new
      expect(sf).not_to be_valid
      expect(sf.errors[:name]).to be_present
      expect(sf.errors[:path]).to be_present
      expect(sf.errors[:relative_path]).to be_present
    end
  end

  describe '.classify_extension' do
    it 'classifies audio files' do
      expect(ShareFile.classify_extension('mp3')).to eq('audio')
      expect(ShareFile.classify_extension('flac')).to eq('audio')
    end

    it 'classifies image files' do
      expect(ShareFile.classify_extension('jpg')).to eq('image')
      expect(ShareFile.classify_extension('png')).to eq('image')
    end

    it 'classifies video files' do
      expect(ShareFile.classify_extension('mp4')).to eq('video')
      expect(ShareFile.classify_extension('mkv')).to eq('video')
    end

    it 'classifies document files' do
      expect(ShareFile.classify_extension('pdf')).to eq('document')
      expect(ShareFile.classify_extension('txt')).to eq('document')
    end

    it 'classifies unknown extensions as file' do
      expect(ShareFile.classify_extension('xyz')).to eq('file')
      expect(ShareFile.classify_extension('')).to eq('file')
    end

    it 'is case insensitive' do
      expect(ShareFile.classify_extension('MP3')).to eq('audio')
      expect(ShareFile.classify_extension('JPG')).to eq('image')
    end
  end

  describe 'scopes' do
    let(:share) { create(:share) }

    before do
      ShareFile.create!(share: share, name: 'song.mp3', path: '/var/hda/files/test/song.mp3',
                        relative_path: 'song.mp3', content_type: 'audio', extension: 'mp3', size: 1000)
      ShareFile.create!(share: share, name: 'photo.jpg', path: '/var/hda/files/test/photo.jpg',
                        relative_path: 'photo.jpg', content_type: 'image', extension: 'jpg', size: 2000)
      ShareFile.create!(share: share, name: 'docs', path: '/var/hda/files/test/docs',
                        relative_path: 'docs', content_type: 'directory', directory: true)
    end

    it 'filters files only' do
      expect(ShareFile.files_only.count).to eq(2)
    end

    it 'filters directories only' do
      expect(ShareFile.directories_only.count).to eq(1)
    end

    it 'filters by content type' do
      expect(ShareFile.by_type('audio').count).to eq(1)
      expect(ShareFile.by_type('image').count).to eq(1)
    end

    it 'searches by name' do
      expect(ShareFile.search('song').count).to eq(1)
      expect(ShareFile.search('photo').count).to eq(1)
      expect(ShareFile.search('nope').count).to eq(0)
    end
  end
end
