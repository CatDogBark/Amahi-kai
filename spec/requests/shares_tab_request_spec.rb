require 'spec_helper'

describe "Shares tab", type: :request do
  before do
    login_as_admin
    allow_any_instance_of(Share).to receive(:push_shares)
    allow(Share).to receive(:push_shares)
  end

  describe "GET /tab/shares" do
    it "renders the shares page" do
      get shares_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing shares" do
      share = create(:share, name: "TestShare")
      get shares_path
      expect(response.body).to include("TestShare")
    end
  end

  describe "POST /tab/shares (create)" do
    it "creates a new share" do
      post shares_path, params: { share: { name: "NewShare" } }
      expect(Share.find_by(name: "NewShare")).to be_present
    end

    it "rejects blank name" do
      post shares_path, params: { share: { name: "" } }
      expect(response.body).to include("blank")
    end

    it "rejects duplicate name" do
      create(:share, name: "Existing")
      post shares_path, params: { share: { name: "Existing" } }
      expect(response.body).to include("taken")
    end
  end

  describe "DELETE /tab/shares/:id" do
    it "deletes a share" do
      share = create(:share)
      delete share_path(share)
      expect(Share.find_by(id: share.id)).to be_nil
    end
  end
end
