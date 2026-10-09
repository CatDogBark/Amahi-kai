require 'spec_helper'

describe "Setup Controller", type: :request do
  before(:each) do
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    create(:setting, name: "domain", value: "home.lan")
  end

  def mark_setup_completed
    Setting.set('setup_completed', 'true')
  end

  def mark_setup_incomplete
    Setting.set('setup_completed', 'false')
  end

  # spec_helper loads db/seeds.rb before each example, so the seeded admin exists with
  # the seeded password, as on a fresh install.
  def change_seeded_admin_password
    User.find_by(login: User::SEED_ADMIN_LOGIN).update!(password: "a-new-passphrase")
  end

  describe "redirect guard (check_setup_completed)" do
    it "redirects authenticated admin to wizard when setup not completed" do
      login_as_admin
      mark_setup_incomplete
      get root_path
      expect(response).to redirect_to(setup_welcome_path)
    end

    it "does not redirect when setup is completed" do
      login_as_admin
      mark_setup_completed
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "does not redirect unauthenticated users (login wall comes first)" do
      mark_setup_incomplete
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "does not redirect setup controller routes (no infinite loop)" do
      login_as_admin
      mark_setup_incomplete
      get setup_welcome_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "wizard flow (admin required)" do
    before do
      login_as_admin
      mark_setup_incomplete
      allow(SambaService).to receive(:push_config)
    end

    describe "GET /setup/welcome" do
      it "renders welcome step" do
        get setup_welcome_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /setup/admin" do
      it "renders admin password step" do
        get setup_admin_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/admin" do
      it "rejects blank password" do
        post setup_update_admin_path, params: { password: "", password_confirmation: "" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Password cannot be blank")
      end

      it "rejects mismatched passwords" do
        post setup_update_admin_path, params: { password: "newpassword1", password_confirmation: "different" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("do not match")
      end

      it "rejects passwords shorter than 8 chars" do
        post setup_update_admin_path, params: { password: "short", password_confirmation: "short" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("at least 8 characters")
      end

      it "accepts valid password and redirects to network step" do
        post setup_update_admin_path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
        expect(response).to redirect_to(setup_network_path)
      end
    end

    describe "GET /setup/network" do
      it "renders network step" do
        get setup_network_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/network" do
      it "saves server name and redirects to storage step" do
        post setup_update_network_path, params: { server_name: "myhda" }
        expect(response).to redirect_to(setup_storage_path)
        expect(Setting.get('server-name')).to eq("myhda")
      end

      it "redirects to storage step even with blank server name" do
        post setup_update_network_path, params: { server_name: "" }
        expect(response).to redirect_to(setup_storage_path)
        expect(Privileged.calls).to be_empty
      end

      it "makes the name one hostname-shaped word, saves that and sets the system hostname through the root helper" do
        post setup_update_network_path, params: { server_name: "My NAS" }
        expect(Setting.get('server-name')).to eq('my-nas')
        expect(Privileged.calls).to eq([['network.set_hostname', { hostname: 'my-nas' }]])
      end

      it "refuses a name that isn't one, and nothing of it reaches Samba's config" do
        ["nas\nhosts allow = 0.0.0.0/0", "nas;x", "-nas", "a" * 64].each do |name|
          post setup_update_network_path, params: { server_name: name }
          expect(response).to redirect_to(setup_network_path), name
          expect(flash[:error]).to include('letters, digits and hyphens'), name
        end
        expect(Setting.get('server-name')).to be_nil
        expect(Privileged.calls).to be_empty
        expect(Share.server_name).to eq('amahi-kai')
      end

      it "keeps the server name and warns when the hostname can't be changed" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('network.set_hostname', 'refused'))
        post setup_update_network_path, params: { server_name: "myhda" }
        expect(Setting.get('server-name')).to eq("myhda")
        expect(flash[:warning]).to include("hostname couldn't be changed")
      end
    end

    describe "GET /setup/storage" do
      it "renders storage step" do
        allow(DiskManager).to receive(:devices).and_return([])
        get setup_storage_path
        expect(response).to have_http_status(:ok)
      end

      it "doesn't offer drives that hold a ZFS pool" do
        allow(DiskManager).to receive(:devices).and_return([
          { name: "sdc", path: "/dev/sdc", model: "SSD", size: "1T", os_disk: false, zfs_pool: "tank",
            partitions: [{ path: "/dev/sdc1", status: :unmounted, fstype: "zfs_member", size: "1T" }] },
          { name: "sdd", path: "/dev/sdd", model: "SSD", size: "1T", os_disk: false, zfs_pool: nil,
            partitions: [{ path: "/dev/sdd", status: :unformatted, size: "1T" }] }
        ])
        get setup_storage_path
        values = Nokogiri::HTML(response.body).css('input[name="drives[]"]').map { |i| i['value'] }
        expect(values).to eq(["/dev/sdd"])
      end
    end

    describe "POST /setup/storage" do
      it "redirects to greyhole step" do
        post setup_update_storage_path
        expect(response).to redirect_to(setup_greyhole_path)
      end
    end

    describe "GET /setup/prepare_drives_stream" do
      before do
        allow(DiskManager).to receive(:devices).and_return([
          { name: "sdb", path: "/dev/sdb", model: "Test", size: "100G", os_disk: false,
            partitions: [{ path: "/dev/sdb1", status: :mounted, mountpoint: "/mnt/data", fstype: "ext4", size: "100G" }] }
        ])
        allow(DiskManager).to receive(:format_disk!)
        allow(DiskManager).to receive(:mount!).and_return("/mnt/data")
      end

      it "returns SSE content type" do
        get setup_prepare_drives_stream_path, params: { drives: "/dev/sdb1" }, headers: same_origin
        expect(response.headers['Content-Type']).to include('text/event-stream')
      end

      it "creates pool partitions from selected drives" do
        get setup_prepare_drives_stream_path, params: { drives: "/dev/sdb1" }, headers: same_origin
        expect(DiskPoolPartition.pluck(:path)).to include("/mnt/data")
      end

      # Re-running the step used to empty the pool list first.
      it "keeps the drives already in the pool and doesn't add one twice" do
        DiskPoolPartition.create!(path: "/mnt/old", minimum_free: 10)
        2.times { get setup_prepare_drives_stream_path, params: { drives: "/dev/sdb1" }, headers: same_origin }
        expect(DiskPoolPartition.order(:path).pluck(:path)).to eq(["/mnt/data", "/mnt/old"])
      end
    end

    describe "GET /setup/greyhole" do
      it "renders greyhole step" do
        get setup_greyhole_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /setup/share" do
      it "renders share creation step" do
        get setup_share_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/share" do
      it "creates a share and redirects to complete step" do
        allow(SambaService).to receive(:push_config)
        post setup_create_share_path, params: { share_name: "Media" }
        expect(response).to redirect_to(setup_complete_path)
        expect(Share.where(name: "Media").count).to eq(1)
      end

      it "skips share creation if name is blank and redirects to complete" do
        post setup_create_share_path, params: { share_name: "" }
        expect(response).to redirect_to(setup_complete_path)
        expect(Share.count).to eq(0)
      end
    end

    describe "GET /setup/complete" do
      it "renders the completion summary" do
        get setup_complete_path
        expect(response).to have_http_status(:ok)
      end

      it "asks for a new admin password instead of offering to finish while the seeded one works" do
        get setup_complete_path
        expect(response.body).to include("still the default")
        expect(response.body).not_to include(setup_finish_path)
      end
    end

    describe "POST /setup/finish" do
      it "marks setup completed and redirects to root" do
        change_seeded_admin_password
        post setup_finish_path
        expect(response).to redirect_to(root_path)
        expect(Setting.get('setup_completed')).to eq('true')
      end

      it "refuses to finish while the seeded admin password still works" do
        post setup_finish_path
        expect(response).to redirect_to(setup_admin_path)
        expect(flash[:error]).to include("Change the admin password")
        expect(Setting.get('setup_completed')).to eq('false')
      end

      it "offers to finish once the seeded admin has a new password" do
        change_seeded_admin_password
        get setup_complete_path
        expect(response.body).to include(setup_finish_path)
        expect(response.body).not_to include("still the default")
      end
    end
  end

  describe "access control" do
    it "requires authentication" do
      get setup_welcome_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "requires admin" do
      user = create(:user)
      login_as(user)
      mark_setup_incomplete
      get setup_welcome_path
      expect(response).to redirect_to(root_url) # signed in, not an admin: to the dashboard
    end
  end
end
