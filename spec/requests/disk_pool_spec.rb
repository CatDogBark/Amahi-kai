require 'spec_helper'

describe "Disk Pool Actions", type: :request do
  describe "admin" do
    before { login_as_admin }

    let(:share) { create(:share) }

    describe "PUT /shares/:id/toggle_disk_pool_enabled" do
      it "enables disk pooling" do
        allow_any_instance_of(Share).to receive(:push_shares)
        expect(share.disk_pool_copies).to eq(0)
        put toggle_disk_pool_enabled_share_path(share)
        expect(response).to have_http_status(:ok)
        expect(share.reload.disk_pool_copies).to eq(1)
      end

      it "disables disk pooling when already enabled" do
        allow_any_instance_of(Share).to receive(:push_shares)
        share.update!(disk_pool_copies: 2)
        put toggle_disk_pool_enabled_share_path(share)
        expect(response).to have_http_status(:ok)
        expect(share.reload.disk_pool_copies).to eq(0)
      end
    end

    describe "PUT /shares/:id/update_disk_pool_copies" do
      it "updates the number of copies" do
        allow_any_instance_of(Share).to receive(:push_shares)
        put update_disk_pool_copies_share_path(share), params: { value: 3 }
        expect(response).to have_http_status(:ok)
        expect(share.reload.disk_pool_copies).to eq(3)
      end
    end

    describe "PUT /shares/toggle_disk_pool_partition" do
      it "creates a partition when it doesn't exist" do
        allow(Pathname).to receive(:new).and_return(double(mountpoint?: true))
        allow_any_instance_of(PartitionUtils).to receive(:info).and_return([{ path: '/mnt/data' }])

        put toggle_disk_pool_partition_shares_path, params: { path: '/mnt/data' }
        expect(response).to have_http_status(:ok)
        expect(DiskPoolPartition.where(path: '/mnt/data').count).to eq(1)
      end

      it "removes a partition when it already exists" do
        DiskPoolPartition.create!(path: '/mnt/data', minimum_free: 10)
        put toggle_disk_pool_partition_shares_path, params: { path: '/mnt/data' }
        expect(response).to have_http_status(:ok)
        expect(DiskPoolPartition.where(path: '/mnt/data').count).to eq(0)
      end
    end
  end

  describe "non-admin" do
    before { login_as_user }

    let(:share) { create(:share) }

    it "rejects toggle_disk_pool_enabled" do
      put toggle_disk_pool_enabled_share_path(share)
      expect(response).to redirect_to(root_path)
    end
  end
end
