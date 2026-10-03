require 'rails_helper'

# Share indexing runs as a job after the share is committed (it was a bare
# Thread.new in after_create, before the row was visible to other connections).
RSpec.describe ShareIndexJob do
  it "is queued when a share is created" do
    expect {
      Share.create!(name: "IndexMe", path: "/var/lib/amahi-kai/files/indexme")
    }.to have_enqueued_job(ShareIndexJob)
  end

  it "indexes the share" do
    share = create(:share)
    allow(ShareIndexer).to receive(:index_share)
    ShareIndexJob.perform_now(share.id)
    expect(ShareIndexer).to have_received(:index_share).with(share)
  end

  it "does nothing for a share that's gone" do
    allow(ShareIndexer).to receive(:index_share)
    ShareIndexJob.perform_now(-1)
    expect(ShareIndexer).not_to have_received(:index_share)
  end
end
