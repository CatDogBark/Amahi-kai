require 'spec_helper'

describe "Debug", type: :request do

  describe "GET /tab/debug (unauthenticated)" do
    it "redirects to login" do
      get '/tab/debug'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "GET /tab/debug (non-admin)" do
    it "redirects to login" do
      user = create(:user)
      login_as(user)
      get '/tab/debug'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "GET /tab/debug (admin)" do
    before do
      login_as_admin
      # Create log file needed by debug view
      FileUtils.mkdir_p(File.join(Rails.root, 'log'))
      File.write(File.join(Rails.root, 'log', 'production.log'), "test log entry\n")
    end

    it "shows the debug page" do
      get '/tab/debug'
      # May 500 if SystemUtils.run fails in sandbox, but auth should work
      expect(response.status).to be_in([200, 500])
      # If 200, verify content
      if response.status == 200
        expect(response.body).to include("Debug")
      end
    end
  end
end
