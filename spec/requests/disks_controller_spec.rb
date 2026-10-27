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
      expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
    end
  end

  describe "admin" do
    before { login_as_admin }

    describe "GET /disks" do
      it "shows the disks page" do
        get "/disks/"
        expect(response).to have_http_status(:ok)
      end

      it "shows each drive's temperature in °F, coloured once it's warm" do
        allow(DiskManager).to receive(:stats).and_return([
          { device: '/dev/sda', model: 'QEMU HARDDISK', size: '1T', temp_f: 113, tempcolor: 'warm' },
          { device: '/dev/sdb', model: 'QEMU HARDDISK', size: '1T', temp_f: nil, tempcolor: 'cool' },
          { device: '/dev/sdc', model: 'WDC WD40EFZX', size: '4T', temp_f: nil, tempcolor: 'cool', asleep: true } # not woken for it
        ])
        get "/disks/"
        temps = Nokogiri::HTML(response.body).css('#disks-table td.disk-temp')
        expect(temps.map { |td| td.text.strip }).to eq(['113 °F', '–', 'Asleep'])
        expect(temps.first['class']).to include('warm')
        expect(response.body).not_to include('°C')
      end
    end

    describe "GET /disks/devices" do
      it "says why when the drives can't be listed, rather than offering drives that aren't there" do
        allow(DiskManager).to receive(:devices).and_raise(DiskManager::DiskError, "Couldn't list the drives (lsblk gave no answer)")
        get "/disks/devices"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("list the drives (lsblk gave no answer)")
      end

      # A drive that came back unmounted went to the next free slot, and Format said nothing.
      it "names each drive by its ref, and says where a drive that came back unmounted belongs" do
        DiskPoolPartition.create!(path: '/mnt/storage-2', minimum_free: 10)
        allow(DiskManager).to receive(:devices).and_return([
          { name: 'sdb', path: '/dev/sdb', ref: '/dev/disk/by-id/ata-SSD_S1', model: 'SSD', size: '1T', os_disk: false, zfs_pool: nil,
            partitions: [{ path: '/dev/sdb1', ref: '/dev/disk/by-id/ata-SSD_S1-part1', size: '1T', fstype: 'ext4', status: :unmounted,
                           mountpoint: nil, home: '/mnt/storage-2' }] }
        ])
        get "/disks/devices"
        page = Nokogiri::HTML(response.body)
        expect(page.css('form input[name="device"]').map { |i| i['value'] }.uniq).to eq(['/dev/disk/by-id/ata-SSD_S1-part1'])
        expect(page.at_css('#home-sdb1').text.squish).to eq("Belongs at /mnt/storage-2, one of the Greyhole pool's drives: Mount puts it back there")
        format = page.css('form').find { |f| f['action'] == '/disks/format_disk' }
        expect(format.at_css('button')['data-confirm'])
          .to end_with("It's the drive that belongs at /mnt/storage-2, one of the Greyhole pool's drives: Greyhole's copies on it go too.")
      end
    end

    # Unmount was offered on Greyhole's drives and on drives with a share on them, asked to be
    # confirmed, then refused, the reason in a toast gone in 5 seconds.
    it "says what comes before unmounting a Greyhole drive or a drive with a share, instead of offering Unmount" do
      DiskPoolPartition.create!(path: '/mnt/storage-1', minimum_free: 10)
      create(:share, name: 'USB', path: '/mnt/storage-3')
      mounted = lambda do |name, mountpoint|
        { name: name, path: "/dev/#{name}", ref: "/dev/#{name}", model: 'SSD', size: '8G', os_disk: false, zfs_pool: nil,
          partitions: [{ path: "/dev/#{name}", ref: "/dev/#{name}", size: '8G', fstype: 'ext4', status: :mounted, mountpoint: mountpoint }] }
      end
      allow(DiskManager).to receive(:devices).and_return([mounted.call('sdb', '/mnt/storage-1'), mounted.call('sdc', '/mnt/storage-2'),
                                                          mounted.call('sdd', '/mnt/storage-3')])
      get "/disks/devices"
      page = Nokogiri::HTML(response.body)
      unmounts = page.css('form').select { |f| f['action'] == '/disks/unmount_disk' }.map { |f| f.at_css('input[name="device"]')['value'] }
      expect(unmounts).to eq(['/dev/sdc'])
      expect(page.at_css('#unmount-why-sdb').text.squish).to eq('In the Greyhole pool: remove it on Greyhole Pool to unmount it')
      expect(page.at_css('#unmount-why-sdb a')['href']).to eq('/disks/storage_pool')
      expect(page.at_css('#unmount-why-sdd').text.squish).to eq('USB is on it: delete that share on Shares to unmount it')
    end

    describe "drive actions" do
      it "take the drive by its ref, and name it by its kernel name" do
        allow(DiskManager).to receive(:resolve).and_call_original
        allow(DiskManager).to receive(:resolve).with('/dev/disk/by-id/ata-SSD_S1-part1').and_return('/dev/sdc1')
        allow(DiskManager).to receive(:format_disk!)
        post "/disks/format_disk", params: { device: '/dev/disk/by-id/ata-SSD_S1-part1' }
        expect(DiskManager).to have_received(:format_disk!).with('/dev/sdc1')
        expect(flash[:notice]).to eq("Formatted /dev/sdc1 as ext4. Mount it to use it for shares or Greyhole's pool.")
        post "/disks/format_disk", params: { device: '/dev/disk/by-id/ata-Gone_1' } # unplugged since the page was loaded
        expect(flash[:error]).to eq("Format failed: ata-Gone_1 isn't connected any more: reload the page")
      end

      # Mount as Share gave a 500 when the share wasn't saved, and said nothing of Samba refusing it.
      it "Mount as Share says when Samba didn't take the share, and why a share wasn't made" do
        allow(DiskService).to receive(:create_share_from_mount).with('/dev/sdc1')
          .and_return(mount_point: '/mnt/storage-3', share_name: 'storage-3', refused: 'smb.conf refused: [storage-3] path')
        post "/disks/mount_as_share", params: { device: '/dev/sdc1' }
        expect(flash[:notice]).to eq("Mounted /dev/sdc1 at /mnt/storage-3 and created share 'storage-3'")
        expect(flash[:error]).to eq("Samba didn't take the new settings, so the share isn't on the network yet: smb.conf refused: [storage-3] path")

        share = Share.new(name: 'storage-3')
        share.errors.add(:path, "couldn't be created")
        allow(DiskService).to receive(:create_share_from_mount).and_raise(ActiveRecord::RecordNotSaved.new('Failed to save the record', share))
        post "/disks/mount_as_share", params: { device: '/dev/sdc1' }
        expect(response).to redirect_to('/disks/devices')
        expect(flash[:error]).to eq("/dev/sdc1 is mounted, but its share wasn't made: Path couldn't be created")
      end
    end

    describe "GET /disks/mounts" do
      it "shows the mounts page" do
        get "/disks/mounts"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /disks/preview_disk" do
      it "shows what's on the drive" do
        allow(DiskManager).to receive(:preview).with('/dev/sdb1').and_return(
          entries: [{ name: 'Movies', type: :directory, size: 5000, file_count: 1 }, { name: 'notes.txt', type: :file, size: 1000, file_count: 0 }],
          total_used: 6000, file_count: 2
        )
        post "/disks/preview_disk", params: { device: '/dev/sdb1' }
        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#disk-preview code').text).to eq('/dev/sdb1')
        expect(page.css('#disk-preview tbody td strong').map(&:text)).to eq(['Movies'])
        expect(response.body).to include('notes.txt')
      end

      it "says when it stopped counting before the end" do
        allow(DiskManager).to receive(:preview).and_return(entries: [], total_used: 6000, file_count: 2, partial: true)
        post "/disks/preview_disk", params: { device: '/dev/sdb1' }
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#disk-preview .card-header').text.squish).to start_with('Summary: At least 5.86 KB used across 2 files')
        expect(page.at_css('#preview-partial').text).to include('counting stopped before the end')
      end

      it "notices a pool removal Greyhole has finished first, so the apps let go of the drive" do
        allow(Greyhole).to receive(:sync_removals!)
        allow(DiskManager).to receive(:preview).and_return(entries: [], total_used: 0, file_count: 0)
        allow(DiskManager).to receive(:unmount!)
        allow(DiskManager).to receive(:devices).and_return([])
        post "/disks/preview_disk", params: { device: '/dev/sdb1' }
        post "/disks/unmount_disk", params: { device: '/dev/sdb1' }
        get "/disks/devices"
        expect(Greyhole).to have_received(:sync_removals!).exactly(3).times
      end

      it "has the apps given pooled shares follow when a pool drive is mounted again, not another drive" do
        allow(Greyhole).to receive(:sync_removals!)
        allow(DockerApp).to receive(:follow_pool!)
        DiskPoolPartition.create!(path: '/mnt/storage-2', minimum_free: 10)
        allow(DiskManager).to receive(:mount!).and_return('/mnt/storage-2', '/mnt/storage-3')
        post "/disks/mount_disk", params: { device: '/dev/sdb' }
        expect(DockerApp).to have_received(:follow_pool!).once
        post "/disks/mount_disk", params: { device: '/dev/sdc' }
        expect(DockerApp).to have_received(:follow_pool!).once
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

      # Firefox puts a checkbox back the way it was when a page reloads; these show the pool.
      it "shows each drive's In pool as the pool has it, whatever the browser remembers" do
        DiskPoolPartition.create!(path: '/mnt/storage-1', minimum_free: 10, removing: true)
        allow(DiskService).to receive(:partition_list).and_return(
          [{ device: '/dev/sda', path: '/mnt/storage-1', bytes_total: 1, bytes_free: 1 },
           { device: '/dev/sdb', path: '/mnt/storage-2', bytes_total: 1, bytes_free: 1 }]
        )
        allow(Greyhole).to receive(:pool_drives).and_return([{ path: '/mnt/storage-1', removing: true, state: :ok, total: 1, free: 1, used: 0, minimum_free: 10 }])
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        boxes = page.css('.disk-pool-partition input[type=checkbox]')
        expect(boxes.size).to eq(2)
        expect(boxes.map { |b| b['autocomplete'] }).to all(eq('off'))
      end

      it "opens Install Greyhole on Greyhole's own stream, not System Update's" do
        allow(Greyhole).to receive(:status).and_return({ installed: false, running: false })
        allow(Greyhole).to receive(:pool_drives).and_return([])
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#greyhole-install-modal')['data-stream-url']).to eq(disks_install_greyhole_stream_path)
        expect(page.at_css('#system-update-install-modal')['data-stream-url']).to eq(settings_update_system_stream_path)
        # The shared opener (install_terminal.js) reads the window's own address; the page carries
        # no script of its own.
        opener = Rails.application.assets['install_terminal.js'].to_s
        expect(opener).to include('function openInstallTerminal', 'dataset.streamUrl')
        expect(page.css('script:not([type="application/json"])').map { |s| s['src'].to_s }).to all(include('/assets/'))
        expect(page.at_css('#greyhole-install-modal').to_html).not_to include(settings_update_system_stream_path)
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

      it "flags a drive Greyhole won't use, offers Use this drive, and passes it to Greyhole" do
        allow(Greyhole).to receive(:removal_blocker).and_return('Take its drives out of the storage pool first.')
        drive = ->(path, state) { { path: path, minimum_free: 10, total: 20 * 1024**3, free: 19 * 1024**3, used: 1024**3, state: state } }
        allow(Greyhole).to receive(:pool_drives).and_return([drive.call('/mnt/storage-1', :changed), drive.call('/mnt/storage-2', :not_mounted),
                                                             drive.call('/mnt/storage-3', :ok)])
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        changed = page.at_css('#pool-drive-mnt-storage-1')
        expect(changed.text).to include("Greyhole isn't using this drive", 'swapped or formatted')
        use = changed.css('form').find { |f| f.at_css('button').text == 'Use this drive' }
        expect(use['action']).to eq(disks_accept_pool_drive_path)
        expect(use.at_css('button')['data-confirm']).to include('Use the drive now mounted at /mnt/storage-1')
        expect(page.at_css('#pool-drive-mnt-storage-2').text).to include('Nothing is mounted here')
        expect(page.at_css('#pool-drive-mnt-storage-3').text).not_to include('Use this drive')

        allow(Greyhole).to receive(:accept_drive!).and_return(true)
        post "/disks/accept_pool_drive", params: { path: '/mnt/storage-1' }
        expect(response).to redirect_to(disks_storage_pool_path)
        expect(Greyhole).to have_received(:accept_drive!).with('/mnt/storage-1')
        expect(flash[:notice]).to eq('Greyhole uses the drive at /mnt/storage-1 now.')
        allow(Greyhole).to receive(:accept_drive!).and_raise(Greyhole::GreyholeError, 'nothing is mounted at /mnt/storage-1')
        post "/disks/accept_pool_drive", params: { path: '/mnt/storage-1' }
        expect(flash[:error]).to include("didn't take the drive at /mnt/storage-1: nothing is mounted")
      end

      it "shows a drive Greyhole is removing, and says why a drive stays when it can't be removed" do
        allow(Greyhole).to receive(:removal_blocker).and_return('Take its drives out of the storage pool first.')
        allow(Greyhole).to receive(:pool_drives).and_return([{ path: '/mnt/storage-1', minimum_free: 10, total: 20 * 1024**3, free: 18 * 1024**3,
                                                               used: 2 * 1024**3, state: :ok, removing: true }])
        get "/disks/storage_pool"
        page = Nokogiri::HTML(response.body)
        row = page.at_css('#pool-drive-mnt-storage-1')
        expect(row.text).to include('Removing: Greyhole is moving the files kept only on it')
        expect(row.at_css('[data-reload-after="10"]')).not_to be_nil
        expect(row.css('form')).to be_empty

        allow(DiskService).to receive(:toggle_pool_partition).and_raise(Greyhole::GreyholeError, "It's the pool's only drive")
        put "/disks/toggle_disk_pool_partition", params: { path: '/mnt/storage-1' }
        expect(response).to redirect_to(disks_storage_pool_path)
        expect(flash[:error]).to eq("/mnt/storage-1 stays in the pool: It's the pool's only drive")
        put "/disks/toggle_disk_pool_partition", params: { path: '/mnt/storage-1' }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['message']).to eq("It's the pool's only drive")
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
      it "switches greyhole off when running" do
        allow(Greyhole).to receive(:running?).and_return(true)
        allow(Greyhole).to receive(:switch!)
        post "/disks/toggle_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(Greyhole).to have_received(:switch!).with(false)
      end

      it "switches greyhole on when stopped, saying why it couldn't" do
        allow(Greyhole).to receive(:running?).and_return(false)
        allow(Greyhole).to receive(:switch!).and_raise(Greyhole::GreyholeError, 'Greyhole needs a drive in its pool to run: add one first')
        post "/disks/toggle_greyhole"
        expect(response).to redirect_to("/disks/storage_pool")
        expect(Greyhole).to have_received(:switch!).with(true)
        expect(flash[:error]).to eq("Greyhole didn't start: Greyhole needs a drive in its pool to run: add one first")
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
