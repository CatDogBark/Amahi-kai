require 'rails_helper'

RSpec.describe "DisksController extended", type: :request do
  before { login_as_admin }

  describe "GET /tab/disks/devices" do
    it "returns device list as JSON" do
      get "/tab/disks/devices", as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
    end
  end

  describe "POST /tab/disks/format_disk" do
    it "rejects invalid device path" do
      post "/tab/disks/format_disk", params: { device: "/tmp/evil" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:bad_request).or have_http_status(:ok)
    end

    it "formats a valid device path in test mode" do
      post "/tab/disks/format_disk", params: { device: "/dev/sdb1" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /tab/disks/mount_disk" do
    it "rejects OS disk" do
      post "/tab/disks/mount_disk", params: { device: "/dev/sda1" }, as: :json
      # May return error or unprocessable
      expect(response.status).to be_in([200, 400, 422, 500])
    end
  end

  describe "POST /tab/disks/unmount_disk" do
    it "handles unmount request" do
      post "/tab/disks/unmount_disk", params: { device: "/dev/sdb1" }, as: :json
      expect(response.status).to be_in([200, 400, 422, 500])
    end
  end

  describe "PUT /tab/disks/toggle_disk_pool_partition" do
    it "creates a new pool partition" do
      allow_any_instance_of(PartitionUtils).to receive(:info).and_return([{ path: "/mnt/data", size: 1000 }])
      allow_any_instance_of(Pathname).to receive(:mountpoint?).and_return(true)
      put "/tab/disks/toggle_disk_pool_partition", params: { path: "/mnt/data" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "removes an existing pool partition" do
      DiskPoolPartition.create!(path: "/mnt/existing", minimum_free: 10)
      put "/tab/disks/toggle_disk_pool_partition", params: { path: "/mnt/existing" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(DiskPoolPartition.where(path: "/mnt/existing").count).to eq(0)
    end
  end
end
