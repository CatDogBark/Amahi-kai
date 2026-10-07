require 'spec_helper'

describe "Disks Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get "/disks"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get "/disks"
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /disks" do
      it "shows the disks page" do
        get "/disks/"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /disks/mounts" do
      it "shows the mounts page" do
        get "/disks/mounts"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /disks/storage_pool" do
      it "shows the storage pool page" do
        get "/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end

      it "displays greyhole status" do
        allow(Greyhole).to receive(:status).and_return({ installed: true, running: true })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end

      it "displays when greyhole is not installed" do
        allow(Greyhole).to receive(:status).and_return({ installed: false, running: false })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/disks/storage_pool"
        expect(response).to have_http_status(:ok)
      end

      it "opens Install Greyhole on Greyhole's own stream, not System Update's" do
        allow(Greyhole).to receive(:status).and_return({ installed: false, running: false })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#greyhole-install-modal')['data-stream-url']).to eq(disks_install_greyhole_stream_path)
        expect(page.at_css('#system-update-install-modal')['data-stream-url']).to eq(settings_update_system_stream_path)
        # The shared opener reads the window's own address; no window's address is baked into it.
        opener = page.css('script').map(&:text).find { |js| js.include?('function openInstallTerminal') }
        expect(opener).to include("dataset.streamUrl")
        expect(opener).not_to include(disks_install_greyhole_stream_path)
        expect(opener).not_to include(settings_update_system_stream_path)
      end
    end

    describe "Greyhole's controls" do
      before do
        allow(Greyhole).to receive(:status).and_return({ installed: true, running: false, queue: { pending: 0 } })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        allow(DiskService).to receive(:partition_list).and_return([])
      end

      it "offers Start and Uninstall in one row, says why it's stopped, and points to Devices for drives" do
        allow(Greyhole).to receive(:removal_blocker).and_return(nil)
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        row = page.at_css('#uninstall-greyhole-btn').parent
        expect(row.at_css('form button').text.strip).to eq('Start')
        expect(row.at_css('form button')['disabled']).not_to be_nil # nothing to do without drives
        expect(row.text).to include('it has nothing to do until drives are in its pool')
        expect(page.at_css('#uninstall-greyhole-btn')['disabled']).to be_nil
        expect(page.at_css('#greyhole-uninstall-install-modal')['data-stream-url']).to eq(disks_uninstall_greyhole_stream_path)
        expect(page.at_css('#no-share-drives a')['href']).to eq(disks_devices_path)
      end

      it "shows the copies each share keeps, and the room left for files at each" do
        allow(Greyhole).to receive(:installed?).and_return(true)
        allow(Greyhole).to receive(:configure!).and_return(true)
        allow(Greyhole).to receive(:removal_blocker).and_return('Take its drives out of the storage pool first.')
        create(:disk_pool_partition, path: '/mnt/storage-1', minimum_free: 10)
        drive = ->(path) { { path: path, minimum_free: 10, total: 8 * 1024**3, free: 7 * 1024**3, used: 1024**3 } }
        allow(Greyhole).to receive(:pool_drives).and_return([drive.call('/mnt/storage-1'), drive.call('/mnt/storage-2')])
        create(:share, name: 'Test', disk_pool_copies: 1)
        create(:share, name: 'Photos', disk_pool_copies: 99)
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#pool-copies').text.squish)
          .to include('2 drives · Photos: 2 copies, Test: 1 copy', 'Room for about 16 GB of files at 1 copy, or 8 GB of files at 2 copies')
        expect(page.at_css('#uninstall-greyhole-btn').parent.at_css('form button')['disabled']).to be_nil
      end

      it 'says what keeps it from being uninstalled' do
        allow(Greyhole).to receive(:removal_blocker).and_return('Take its drives out of the storage pool first.')
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#uninstall-greyhole-btn')['disabled']).not_to be_nil
        expect(page.at_css('#greyhole-removal-blocker').text).to include('Take its drives out of the storage pool first.')
      end

      it 'streams the uninstall, or the reason it stopped' do
        allow(Greyhole).to receive(:uninstall!) { |&progress| progress.call('Stopping Greyhole and removing it...') }
        get "/disks/uninstall_greyhole_stream", headers: same_origin
        expect(response.body).to include('data: Stopping Greyhole and removing it...', 'data: ✓ Greyhole is uninstalled', "event: done\ndata: success")
        allow(Greyhole).to receive(:uninstall!).and_raise(Greyhole::GreyholeError, 'Take its drives out of the storage pool first.')
        get "/disks/uninstall_greyhole_stream", headers: same_origin
        expect(response.body).to include('data: ✗ Take its drives out of the storage pool first.', "event: done\ndata: error")
      end
    end

    describe "POST /disks/toggle_greyhole" do
      it "stops greyhole when running" do
        allow(Greyhole).to receive(:running?).and_return(true)
        allow(Greyhole).to receive(:stop!)
        post "/disks/toggle_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(Greyhole).to have_received(:stop!)
      end

      it "starts greyhole when stopped" do
        allow(Greyhole).to receive(:running?).and_return(false)
        allow(Greyhole).to receive(:start!)
        post "/disks/toggle_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(Greyhole).to have_received(:start!)
      end
    end

    describe "POST /disks/install_greyhole" do
      it "installs greyhole and redirects with notice" do
        allow(Greyhole).to receive(:install!)
        post "/disks/install_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(flash[:notice]).to include("successfully")
      end

      it "handles GreyholeError during install" do
        allow(Greyhole).to receive(:install!).and_raise(Greyhole::GreyholeError, "apt failed")
        post "/disks/install_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(flash[:error]).to include("apt failed")
      end

      it "handles generic errors during install" do
        allow(Greyhole).to receive(:install!).and_raise(Shell::CommandError.new("greyhole", "unexpected", 1))
        post "/disks/install_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(flash[:error]).to include("unexpected")
      end
    end

    describe "GET /disks/install_greyhole_stream" do
      it "returns SSE content type" do
        get "/disks/install_greyhole_stream", headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end
    end
  end
end
