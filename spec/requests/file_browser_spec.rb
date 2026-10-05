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

    describe "GET /files/:share_id/raw" do
      def raw(name, content)
        File.write(File.join(tmpdir, name), content)
        get "/files/#{share.name}/raw/#{name}"
      end

      it "serves HTML as plain text in a sandbox" do
        raw("page.html", "<script>document.title='ran'</script>")
        expect(response.media_type).to eq("text/plain")
        expect(response.headers["Content-Security-Policy"]).to eq("sandbox")
      end

      it "serves JavaScript as plain text" do
        raw("app.js", "alert(1)")
        expect(response.media_type).to eq("text/plain")
      end

      it "keeps SVG as an image for previews, sandboxed" do
        raw("pic.svg", "<svg xmlns='http://www.w3.org/2000/svg'></svg>")
        expect(response.media_type).to eq("image/svg+xml")
        expect(response.headers["Content-Security-Policy"]).to eq("sandbox")
      end

      it "serves images with their own type" do
        raw("photo.png", "\x89PNG")
        expect(response.media_type).to eq("image/png")
      end

      it "leaves PDFs unsandboxed so the browser's viewer can open them" do
        raw("doc.pdf", "%PDF-1.4")
        expect(response.media_type).to eq("application/pdf")
        expect(response.headers["Content-Security-Policy"]).to be_nil
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

    # The browser only views: files change over SMB, so Samba (and Greyhole) sees every change.
    describe "read-only" do
      it "has no way to upload, make folders, rename or delete" do
        %w[POST:upload POST:new_folder PUT:rename DELETE:delete].each do |route|
          verb, action = route.split(':')
          expect { Rails.application.routes.recognize_path("/files/#{share.name}/#{action}", method: verb) }
            .to raise_error(ActionController::RoutingError), route
        end
        FileUtils.mkdir_p(File.join(tmpdir, "album"))
        File.write(File.join(tmpdir, "hello.txt"), "hi")
        get "/files/#{share.name}/browse"
        page = Nokogiri::HTML(response.body)
        expect(page.text).not_to include("Upload", "New Folder", "Rename", "Delete")
        expect(page.css('input[type=file], input[type=checkbox]')).to be_empty
        menus = page.css('.fb-row .dropdown-item').map { |a| a.text.squish }
        expect(menus).to eq(['Download as zip', 'Download'])
        expect(page.at_css('#fb-download-folder')['href']).to eq("/files/#{share.name}/download")
      end

      it "says files are added over SMB when the share is empty" do
        get "/files/#{share.name}/browse"
        expect(response.body).to include("Add files over the network share (SMB)")
      end

      it "downloads the share, or a folder in it, as a zip" do
        FileUtils.mkdir_p(File.join(tmpdir, "album"))
        File.write(File.join(tmpdir, "album", "pic.jpg"), "jpg")
        get "/files/#{share.name}/download"
        expect(response.headers['Content-Type']).to eq('application/zip')
        get "/files/#{share.name}/download/album"
        expect(response.headers['Content-Disposition']).to include('album.zip')
      end
    end

    # A pooled share holds links to its files' copies on the Greyhole pool drives.
    describe "a pooled share" do
      let(:pool) { Dir.mktmpdir }
      after { FileUtils.remove_entry(pool, true) }

      before do
        share.update!(disk_pool_copies: 2)
        allow(DiskPoolPartition).to receive(:pluck).with(:path).and_return([pool]) # pool drives are under /mnt on a NAS
        FileUtils.mkdir_p(File.join(pool, share.name))
        File.write(File.join(pool, share.name, "movie.mp4"), "video")
        File.write(File.join(pool, "elsewhere.txt"), "no")
        File.symlink(File.join(pool, share.name, "movie.mp4"), File.join(tmpdir, "movie.mp4"))
        File.symlink(File.join(pool, "elsewhere.txt"), File.join(tmpdir, "elsewhere.txt"))
      end

      it "previews and downloads files from their copy on a pool drive" do
        get "/files/#{share.name}/raw/movie.mp4"
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("video")
        get "/files/#{share.name}/download/movie.mp4"
        expect(response.body).to eq("video")
      end

      it "refuses links anywhere else, and leaves them out of zips" do
        get "/files/#{share.name}/raw/elsewhere.txt"
        expect(response).not_to have_http_status(:ok)
        get "/files/#{share.name}/download"
        require 'zip'
        names = Zip::InputStream.open(StringIO.new(response.body)) { |z| [].tap { |n| while (e = z.get_next_entry) do n << e.name end } }
        expect(names).to eq(["movie.mp4"])
      end
    end

    describe "path traversal" do
      it "strips traversal sequences and stays within share" do
        get "/files/#{share.name}/browse/..%2F..%2Fetc%2Fpasswd"
        # Path traversal is stripped — resolved path stays under share root
        # Should NOT serve /etc/passwd content
        if response.status == 200
          expect(response.body).not_to include("root:")
        else
          expect(response.status).to be_in([302, 403, 404])
        end
      end
    end
  end
end
