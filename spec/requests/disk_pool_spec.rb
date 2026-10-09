require 'spec_helper'

# A share's pool copies, from the Shares page (shares.js updatePoolCopies).
describe "Disk Pool Actions", type: :request do
  describe "admin" do
    before { login_as_admin }

    let(:share) { create(:share) }

    describe "PUT /shares/:id/update_disk_pool_copies" do
      it "updates the number of copies" do
        allow(SambaService).to receive(:push_config)
        put update_disk_pool_copies_share_path(share), params: { value: 3 }
        expect(response).to have_http_status(:ok)
        expect(share.reload.disk_pool_copies).to eq(3)
      end

      it "has Greyhole check the pool when copies go up, not when they go down" do
        allow(SambaService).to receive(:push_config)
        allow(Greyhole).to receive(:configure!)
        allow(Greyhole).to receive(:check_pool!)
        put update_disk_pool_copies_share_path(share), params: { copies: 2 }
        expect(Greyhole).to have_received(:check_pool!).once
        put update_disk_pool_copies_share_path(share), params: { copies: 1 }
        expect(Greyhole).to have_received(:check_pool!).once
        expect(share.reload.disk_pool_copies).to eq(1)
      end

      it "has the apps given the share follow it into the pool, and out of it once it's Off" do
        allow(SambaService).to receive(:push_config)
        allow(Greyhole).to receive(:configure!)
        allow(Greyhole).to receive(:check_pool!)
        allow(DockerApp).to receive(:follow_pool!)
        put update_disk_pool_copies_share_path(share), params: { copies: 2 }
        expect(DockerApp).to have_received(:follow_pool!).with(no_args).once
        put update_disk_pool_copies_share_path(share), params: { copies: 1 } # still pooled
        expect(DockerApp).to have_received(:follow_pool!).once

        allow(Greyhole).to receive(:remove_share!).and_return(:removing) # files to move back first
        put update_disk_pool_copies_share_path(share), params: { copies: 0 }
        expect(DockerApp).to have_received(:follow_pool!).once
        allow(Greyhole).to receive(:remove_share!) { |s| s.update!(disk_pool_copies: 0) && :removed }
        put update_disk_pool_copies_share_path(share), params: { copies: 0 }
        expect(DockerApp).to have_received(:follow_pool!).with(no_args).twice
      end
    end
  end

  describe "non-admin" do
    before { login_as_user }

    let(:share) { create(:share) }

    it "can't change a share's copies" do
      put update_disk_pool_copies_share_path(share), params: { copies: 2 }
      expect(response).to redirect_to(new_user_session_path)
      expect(share.reload.disk_pool_copies).to eq(0)
    end
  end
end
