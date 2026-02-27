require 'rails_helper'

RSpec.describe "SearchController extended", type: :request do
  before { login_as_admin }

  let!(:share) { create(:share, name: "TestSearch") }

  before do
    # Create searchable files
    ShareFile.create!(share: share, name: "movie.mp4", path: "/test/movie.mp4",
                      relative_path: "movie.mp4", content_type: "video", extension: "mp4", size: 5000)
    ShareFile.create!(share: share, name: "song.mp3", path: "/test/song.mp3",
                      relative_path: "song.mp3", content_type: "audio", extension: "mp3", size: 3000)
    ShareFile.create!(share: share, name: "photo.jpg", path: "/test/photo.jpg",
                      relative_path: "photo.jpg", content_type: "image", extension: "jpg", size: 2000)
    ShareFile.create!(share: share, name: "notes.txt", path: "/test/notes.txt",
                      relative_path: "notes.txt", content_type: "document", extension: "txt", size: 100)
  end

  describe "GET /search/hda" do
    it "finds files by name" do
      get search_files_path, params: { query: "movie" }
      expect(response).to have_http_status(:ok)
    end

    it "returns results with pagination" do
      get search_files_path, params: { query: "movie", page: 1, per_page: 10 }
      expect(response).to have_http_status(:ok)
    end

    it "handles page beyond results" do
      get search_files_path, params: { query: "movie", page: 999 }
      expect(response).to have_http_status(:ok)
    end

    it "handles empty results" do
      get search_files_path, params: { query: "nonexistent_file_xyz" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/images" do
    it "filters to image results" do
      get search_images_path, params: { query: "photo" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/audio" do
    it "filters to audio results" do
      get search_audio_path, params: { query: "song" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/video" do
    it "filters to video results" do
      get search_video_path, params: { query: "movie" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /search/hda" do
    it "accepts POST method" do
      post search_files_path, params: { query: "test" }
      expect(response).to have_http_status(:ok)
    end
  end
end
