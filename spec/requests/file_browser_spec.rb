require 'spec_helper'

describe "FileBrowser Controller", type: :request do
  let(:tmpdir) { Dir.mktmpdir }
  let(:share) { create(:share, path: tmpdir, name: "testshare", everyone: true) }

  after { FileUtils.remove_entry(tmpdir, true) }

  # A downloaded zip's entries, { name => content }, read from its central directory.
  def zip_entries(body)
    require 'zip'
    Tempfile.create(['download', '.zip']) do |file|
      file.binmode
      file.write(body)
      file.flush
      Zip::File.open(file.path) { |zip| zip.entries.to_h { |e| [e.name, e.get_input_stream.read] } }
    end
  end

  describe "unauthenticated" do
    it "redirects to login" do
      get "/files/#{share.name}/browse"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "the Shares page" do
    let!(:open_share) { create(:share, name: "Photos", path: Dir.mktmpdir, everyone: true) }
    let!(:private_share) { create(:share, name: "Finance", path: Dir.mktmpdir, everyone: false) }

    after { FileUtils.remove_entry(open_share.path, true) && FileUtils.remove_entry(private_share.path, true) }

    it "lists the shares a user can open, linked to the file browser, from the header's Shares link" do
      login_as(create(:user))
      get "/files"
      page = Nokogiri::HTML(response.body)
      expect(page.css("#share-list a.fb-card").map { |a| [a.at_css(".fb-card-name").text, a["href"]] }).to eq([["Photos", "/files/Photos/browse"]])
      expect(page.at_css("#share-list .fb-card-address").text).to eq("\\\\amahi-kai\\Photos")
      expect(page.at_css("#files-link")["href"]).to eq("/files")
    end

    it "lists every share for an admin" do
      login_as_admin
      get "/files"
      expect(Nokogiri::HTML(response.body).css("#share-list .fb-card-name").map(&:text)).to eq(%w[Finance Photos])
    end

    it "shows each share's item count, and badges a pooled or read-only one" do
      File.write(File.join(open_share.path, "a.jpg"), "x")
      File.write(File.join(open_share.path, ".hidden"), "x")
      open_share.update_column(:disk_pool_copies, 2)
      private_share.update_column(:rdonly, true)
      login_as_admin
      get "/files"
      cards = Nokogiri::HTML(response.body).css("#share-list .fb-card").to_h { |c| [c.at_css(".fb-card-name").text, c] }
      expect(cards["Photos"].at_css(".fb-card-meta").text.squish).to eq("1 item")
      expect(cards["Photos"].at_css(".fb-chip").text).to eq("Greyhole · 2 copies")
      expect(cards["Finance"].at_css(".fb-chip").text).to eq("Read only")
    end
  end

  describe "admin" do
    before { @admin = login_as_admin }

    describe "GET /files/:share_id/browse" do
      it "opens a folder from its row and its breadcrumb, nested ones too" do
        FileUtils.mkdir_p(File.join(tmpdir, "album", "2026"))
        File.write(File.join(tmpdir, "album", "2026", "beach.jpg"), "x")
        get "/files/#{share.name}/browse"
        expect(Nokogiri::HTML(response.body).at_css(".fb-item[data-name='album'] a.fb-item-main")["href"]).to eq("/files/#{share.name}/browse/album")
        get "/files/#{share.name}/browse/album/2026"
        page = Nokogiri::HTML(response.body)
        expect(page.css(".fb-breadcrumbs a").map { |a| a["href"] }).to eq(["/files", "/files/#{share.name}/browse", "/files/#{share.name}/browse/album"])
        expect(page.at_css(".fb-item-parent a")["href"]).to eq("/files/#{share.name}/browse/album")
      end

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
        expect(response).to redirect_to("/files/#{share.name}/browse")
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
        downloads = page.css('.fb-item-download').map { |a| a['aria-label'] }
        expect(downloads).to eq(['Download album as a zip', 'Download hello.txt'])
        expect(page.at_css('#fb-download-folder')['href']).to eq("/files/#{share.name}/download")
      end

      it "says files are added over SMB when the share is empty" do
        get "/files/#{share.name}/browse"
        expect(response.body).to include("Add files over the network share (SMB)")
      end

      it "downloads the share, or a folder in it, as a zip made as it's sent" do
        FileUtils.mkdir_p(File.join(tmpdir, "album"))
        File.write(File.join(tmpdir, "album", "pic.jpg"), "jpg")
        File.write(File.join(tmpdir, "notes.txt"), "n" * 50_000)
        get "/files/#{share.name}/download"
        expect(response.headers['Content-Type']).to eq('application/zip')
        # Streamed: headers that keep Rack::ETag, Rack::Deflater and proxies from buffering it
        expect(response.headers).to include('X-Accel-Buffering' => 'no', 'Content-Encoding' => 'identity')
        expect(response.headers['ETag']).to be_nil
        expect(zip_entries(response.body)).to eq("album/pic.jpg" => "jpg", "notes.txt" => "n" * 50_000)
        get "/files/#{share.name}/download/album"
        expect(response.headers['Content-Disposition']).to include('album.zip')
        expect(zip_entries(response.body)).to eq("pic.jpg" => "jpg")
      end

      it "returns the page's token in a cookie when the zip starts, so it can say the download began" do
        File.write(File.join(tmpdir, "a.txt"), "a")
        get "/files/#{share.name}/download", params: { token: "abc123def456" }
        expect(response.cookies["fb_download"]).to eq("abc123def456")
        expect(Array(response.headers['Set-Cookie']).find { |c| c.start_with?('fb_download=') }).not_to match(/httponly/i)
        get "/files/#{share.name}/download", params: { token: "<script>" }
        expect(response.cookies["fb_download"]).to be_nil
      end

      it "makes each row one link: a folder opens, a file is shown in the panel with its kind and size" do
        FileUtils.mkdir_p(File.join(tmpdir, "album"))
        %w[pic.jpg notes.txt doc.odt].each { |name| File.write(File.join(tmpdir, name), "x" * 2048) }
        get "/files/#{share.name}/browse"
        page = Nokogiri::HTML(response.body)
        link = ->(name) { page.at_css(".fb-item[data-name='#{name}'] a.fb-item-main") }
        expect(link.call("album")["href"]).to eq("/files/#{share.name}/browse/album")
        expect(link.call("album")["data-action"]).to be_nil
        expect(link.call("pic.jpg")["data-action"]).to eq("click->file-browser#select")
        expect(%w[pic.jpg notes.txt doc.odt].map { |n| link.call(n)["data-kind"] }).to eq(%w[image text document])
        expect(link.call("doc.odt")["data-kind-name"]).to eq("Document")
        expect(link.call("doc.odt")["data-size"]).to eq("2 KB")
        expect(link.call("doc.odt")["data-download-url"]).to eq("/files/#{share.name}/download/doc.odt")
        expect(link.call("pic.jpg")["href"]).to eq("/files/#{share.name}/raw/pic.jpg") # without the script, the file opens
        expect(page.at_css("[data-file-browser-target=details]").text).to include("Click a file to see it here")
        expect(page.css(".fb-viewbtn").map { |b| b["data-view"] }).to eq(%w[list grid])
        expect(page.at_css("#fb-download-folder")["data-action"]).to eq("click->file-browser#downloadZip")
        expect(page.at_css("#fb-download-status")).to be_present
        expect(page.at_css("#fb-shares-crumb")["href"]).to eq("/files")
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
        expect(zip_entries(response.body).keys).to eq(["movie.mp4"])
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
