require 'spec_helper'

describe "FileBrowser Controller", type: :request do
  let(:tmpdir) { Dir.mktmpdir }
  let(:share) { create(:share, path: tmpdir, name: "testshare", everyone: true) }

  after { FileUtils.remove_entry(tmpdir, true) }

  describe "unauthenticated" do
    it "redirects to login" do
      get "/files/#{share.name}/browse"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { @admin = login_as_admin }

    describe "GET /files/:share_id/browse" do
      it "shows directory listing" do
        FileUtils.touch(File.join(tmpdir, "hello.txt"))
        get "/files/#{share.name}/browse"
        expect(response).to have_http_status(:ok)
      end

      it "serves a file when path points to a file" do
        File.write(File.join(tmpdir, "hello.txt"), "content")
        get "/files/#{share.name}/browse/hello.txt"
        # Browse on a file triggers send_file (200) or redirect
        expect(response).to have_http_status(:ok).or have_http_status(:found)
      end
    end

    describe "GET /files/:share_id/download" do
      it "downloads a file" do
        File.write(File.join(tmpdir, "test.txt"), "hello")
        get "/files/#{share.name}/download/test.txt"
        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('test.txt')
      end

      it "returns error for missing file" do
        get "/files/#{share.name}/download/nonexistent.txt"
        expect(response).to redirect_to(file_browser_path(share.name, path: "nonexistent.txt"))
      end
    end

    describe "POST /files/:share_id/upload" do
      it "uploads a file" do
        file = Rack::Test::UploadedFile.new(StringIO.new("data"), "text/plain", false, original_filename: "upload.txt")
        post "/files/#{share.name}/upload", params: { files: [file] }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end

      it "rejects missing files param" do
        post "/files/#{share.name}/upload", params: {}
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "POST /files/:share_id/new_folder" do
      it "creates a new folder" do
        post "/files/#{share.name}/new_folder", params: { name: "newfolder" }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end

      it "rejects blank name" do
        post "/files/#{share.name}/new_folder", params: { name: "" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PUT /files/:share_id/rename" do
      it "renames an entry" do
        File.write(File.join(tmpdir, "old.txt"), "data")
        put "/files/#{share.name}/rename", params: { old_name: "old.txt", new_name: "new.txt" }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end

      it "rejects blank names" do
        put "/files/#{share.name}/rename", params: { old_name: "", new_name: "" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "DELETE /files/:share_id/delete" do
      it "deletes entries" do
        File.write(File.join(tmpdir, "doomed.txt"), "bye")
        delete "/files/#{share.name}/delete", params: { names: ["doomed.txt"] }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end

      it "rejects empty names" do
        delete "/files/#{share.name}/delete", params: { names: [] }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "path traversal" do
      it "blocks traversal attempts" do
        get "/files/#{share.name}/browse/..%2F..%2Fetc%2Fpasswd"
        # Should redirect (access denied) — not serve the file
        expect(response.status).to be_in([302, 403, 404])
      end
    end
  end
end
