require 'spec_helper'

describe "Disks tab", type: :request do
  before { login_as_admin }

  describe "GET /tab/disks" do
    it "renders the disks page" do
      get disks_engine_path
      expect(response).to have_http_status(:ok)
    end

    it "shows disk information headers" do
      get disks_engine_path
      expect(response.body).to include(I18n.t('model'))
      expect(response.body).to include(I18n.t('device'))
    end
  end
end
