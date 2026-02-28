require 'spec_helper'

describe "Security Controller", type: :request do

  describe "unauthenticated" do
    it "redirects to login" do
      get '/network/security'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "non-admin" do
    it "redirects non-admin users" do
      login_as_user
      get '/network/security'
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "admin" do
    let(:mock_check) do
      double("SecurityCheck",
        name: "ufw",
        description: "UFW firewall enabled",
        status: :pass,
        severity: :warning,
        fix_command: nil
      )
    end

    before do
      @admin = login_as_admin
      allow(SecurityAudit).to receive(:run_all).and_return([mock_check])
      allow(SecurityAudit).to receive(:has_blockers?).and_return(false)
      allow(SecurityAudit).to receive(:fix!).and_return(true)
      allow(SecurityAudit).to receive(:fix_all!).and_return([{ name: "ufw", fixed: true }])
    end

    describe "GET /network/security" do
      it "shows the security page" do
        get '/network/security'
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /network/security/audit_stream" do
      it "returns an SSE stream" do
        get '/network/security/audit_stream'
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/event-stream')
      end
    end

    describe "GET /network/security/fix_stream" do
      it "returns an SSE stream" do
        get '/network/security/fix_stream'
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/event-stream')
      end
    end

    describe "POST /network/security/fix" do
      it "fixes a specific check" do
        post '/network/security/fix', params: { check_name: "ufw" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['status']).to eq('ok')
      end
    end
  end
end
