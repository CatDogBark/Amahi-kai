require 'spec_helper'

describe "Setup Controller", type: :request do
  before(:each) do
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    create(:setting, name: "domain", value: "home.lan")
  end

  # Helper: mark setup as completed so the guard doesn't interfere with other specs
  def mark_setup_completed
    Setting.set('setup_completed', 'true')
  end

  def mark_setup_incomplete
    s = Setting.find_by(name: 'setup_completed')
    s&.destroy
  end

  describe "redirect guard (check_setup_completed)" do
    it "redirects authenticated admin to wizard when setup not completed" do
      mark_setup_incomplete
      login_as_admin
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
      allow_any_instance_of(Share).to receive(:push_shares)
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
      end
    end

    describe "GET /setup/storage" do
      it "renders storage step" do
        allow_any_instance_of(PartitionUtils).to receive(:info).and_return([])
        get setup_storage_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/storage" do
      it "creates pool partitions from selected paths and redirects to share step" do
        post setup_update_storage_path, params: { partitions: ["/mnt/data"] }
        expect(response).to redirect_to(setup_share_path)
        expect(DiskPoolPartition.pluck(:path)).to include("/mnt/data")
      end

      it "replaces existing pool partitions on resubmit" do
        DiskPoolPartition.create!(path: "/mnt/old", minimum_free: 10)
        post setup_update_storage_path, params: { partitions: ["/mnt/new"] }
        expect(DiskPoolPartition.pluck(:path)).to eq(["/mnt/new"])
      end

      it "clears all pool partitions when none selected" do
        DiskPoolPartition.create!(path: "/mnt/data", minimum_free: 10)
        post setup_update_storage_path, params: {}
        expect(DiskPoolPartition.count).to eq(0)
        expect(response).to redirect_to(setup_share_path)
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
        allow_any_instance_of(Share).to receive(:push_shares)
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
    end

    describe "POST /setup/finish" do
      it "marks setup completed and redirects to root" do
        post setup_finish_path
        expect(response).to redirect_to(root_path)
        expect(Setting.get('setup_completed')).to eq('true')
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
      get setup_welcome_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end
end
