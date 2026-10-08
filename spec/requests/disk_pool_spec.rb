require 'spec_helper'

# A share's pool copies, from the Shares page (shares.js updatePoolCopies).
describe "Disk Pool Actions", type: :request, integration: true do
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
