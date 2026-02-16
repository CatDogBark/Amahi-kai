require 'spec_helper'

describe "Search", type: :request do

  describe "GET /search/hda (unauthenticated)" do
    it "redirects to login" do
      get search_hda_path, params: { query: "test" }
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /search/hda (authenticated)" do
    before { login_as_admin }

    it "shows search results page" do
      get search_hda_path, params: { query: "test" }
      expect(response).to have_http_status(:ok)
    end

    it "redirects to Google for web search" do
      get search_hda_path, params: { query: "test", button: "Web" }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(/google\.com/)
    end

    it "handles empty query" do
      get search_hda_path, params: { query: "" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/images (authenticated)" do
    before { login_as_admin }

    it "shows image search results" do
      get search_images_path, params: { query: "test" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/audio (authenticated)" do
    before { login_as_admin }

    it "shows audio search results" do
      get search_audio_path, params: { query: "test" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /search/video (authenticated)" do
    before { login_as_admin }

    it "shows video search results" do
      get search_video_path, params: { query: "test" }
      expect(response).to have_http_status(:ok)
    end
  end
end
