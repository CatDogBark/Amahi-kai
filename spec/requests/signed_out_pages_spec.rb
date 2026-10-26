require 'rails_helper'

# A page whose sign-in ended is told so on the requests it makes itself (session_watch.js then
# reloads it, which leads to the sign-in page), instead of getting the sign-in page's HTML, which
# its handlers read as "no answer from Amahi-kai". A signed-in page can ask when its sign-in ends
# without that counting as use.
RSpec.describe 'Pages whose sign-in ended', type: :request do
  let(:json) { { 'Accept' => 'application/json', 'X-Requested-With' => 'XMLHttpRequest' } }

  # The test environment turns CSRF protection off, so it's turned on after the sign-in
  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "says how long the sign-in has left, and asking doesn't count as using it" do
    login_as_admin
    get session_status_path, headers: json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'ok', 'ends_in' => be_within(60).of(12.hours.to_i))

    travel(11.hours + 50.minutes) do
      get session_status_path, headers: json
      expect(response.parsed_body['ends_in']).to be_within(60).of(10.minutes.to_i) # the first ask didn't move it
    end
    travel(12.hours + 1.minute) do
      get session_status_path, headers: json
      expect(response).to have_http_status(:ok) # the answer is the state, not a failure
      expect(response.headers['X-Amahi-Session']).to eq('signed-out')
      get settings_system_status_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  it "tells a page's own request that the sign-in ended, and sends a page load to the sign-in page" do
    ensure_setup_completed!
    get settings_update_dialog_path, headers: json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['X-Amahi-Session']).to eq('signed-out')
    expect(response.parsed_body).to eq('status' => 'error', 'error' => I18n.t('signed_out'))

    get settings_system_status_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'comes back to the page it was sent from after the sign-in, never to another site' do
    admin = create(:admin)
    ensure_setup_completed!
    get settings_system_status_path
    login_as(admin)
    expect(response).to redirect_to(settings_system_status_path)

    delete logout_path
    get settings_system_status_path
    post user_sessions_path, params: { username: admin.login, password: 'wrong' }
    login_as(admin)
    expect(response).to redirect_to(settings_system_status_path) # a wrong password first changes nothing
  end

  describe 'a page from an earlier sign-in (its token is stale)' do
    it "tells the page's own request it's out of date, and does nothing" do
      login_as_admin
      with_forgery_protection do
        post settings_check_updates_path, headers: json.merge('X-CSRF-Token' => 'from-an-earlier-sign-in')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.headers['X-Amahi-Session']).to eq('out-of-date')
        expect(response.parsed_body['error']).to eq(I18n.t('page_out_of_date'))
      end
      expect(Privileged.calls).to be_empty
    end

    it 'sends a form back to its page, saying why nothing was done' do
      login_as_admin
      with_forgery_protection do
        post settings_check_updates_path, headers: { 'Referer' => "http://www.example.com#{settings_system_status_path}" }
        expect(response).to redirect_to("http://www.example.com#{settings_system_status_path}")
        expect(flash[:info]).to eq(I18n.t('page_out_of_date'))
      end
    end

    it 'sends a page that was signed out to the sign-in page' do
      ensure_setup_completed!
      with_forgery_protection do
        post settings_check_updates_path, headers: json
        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['X-Amahi-Session']).to eq('signed-out')
        post settings_check_updates_path
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:info]).to eq(I18n.t('signed_out'))
      end
    end

    it 'sends a stale sign-in form back to the sign-in page, to sign in again' do
      ensure_setup_completed!
      with_forgery_protection do
        post user_sessions_path, params: { username: 'admin', password: 'x' }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:info]).to eq(I18n.t('page_out_of_date'))
      end
    end
  end
end
