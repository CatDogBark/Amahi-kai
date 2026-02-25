require 'rails_helper'

RSpec.describe "AppProxy", type: :request do
  describe "GET /app/:app_id" do
    context 'when app does not exist' do
      it 'returns 404 for admin' do
        login_as_admin
        get '/app/nonexistent'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when app exists but is not running' do
      it 'returns 503 service unavailable' do
        login_as_admin
        create(:docker_app, identifier: 'testapp', status: 'stopped')
        get '/app/testapp'
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when not logged in' do
      it 'redirects to login' do
        get '/app/testapp'
        expect(response).to redirect_to(new_user_session_url)
      end
    end
  end
end
