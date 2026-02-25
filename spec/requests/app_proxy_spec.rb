require 'rails_helper'

RSpec.describe "AppProxy", type: :request do
  let!(:admin) { create(:user, login: 'proxyadmin', admin: true) }

  before do
    post user_sessions_path, params: { username: 'proxyadmin', password: 'secretpassword' }
  end

  describe "GET /app/:app_id" do
    context 'when app does not exist' do
      it 'returns 404' do
        get '/app/nonexistent'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when app exists but is not running' do
      let!(:app) { create(:docker_app, identifier: 'testapp', status: 'stopped') }

      it 'returns 503 service unavailable' do
        get '/app/testapp'
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when not logged in' do
      it 'redirects to login' do
        delete user_session_path(0) rescue nil
        get '/app/testapp'
        expect(response).to redirect_to(new_user_session_url)
      end
    end
  end
end
