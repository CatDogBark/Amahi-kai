require 'spec_helper'

describe CapWriter do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
  end

  def create_share_via_sql
    ActiveRecord::Base.connection.execute(
      "INSERT INTO shares (name, path, rdonly, visible, everyone, tags, disk_pool_copies, guest_access, guest_writeable) " \
      "VALUES ('testshare#{rand(99999)}', '/tmp/test#{rand(99999)}', 0, 1, 1, 'test', 0, 0, 0)"
    )
    Share.last
  end

  it "should belong to a user" do
    user = create(:user)
    share = create_share_via_sql
    cap = CapWriter.create!(user_id: user.id, share_id: share.id)
    expect(cap.user).to eq(user)
  end

  it "should belong to a share" do
    user = create(:user)
    share = create_share_via_sql
    cap = CapWriter.create!(user_id: user.id, share_id: share.id)
    expect(cap.share).to eq(share)
  end
end
