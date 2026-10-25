require 'spec_helper'

describe "User Sessions", type: :request do

  describe "GET /login" do
    it "shows the login page" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end

  describe "POST /user_sessions (login)" do
    it "logs in with valid credentials" do
      ensure_setup_completed!
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      expect(response).to redirect_to(root_url)
      follow_redirect!
      expect(response.body).to include("Dashboard")
    end

    # A guest has the network shares only: no web UI, right password or not.
    it "refuses a guest, saying guests use the network shares, and only with the right password" do
      ensure_setup_completed!
      guest = create(:user, role: 'guest')
      post user_sessions_path, params: { username: guest.login, password: "secretpassword" }
      expect(response.body).to include("Guest accounts use the network shares (SMB) only")
      expect(session[:user_id]).to be_nil
      expect(guest.reload.login_count.to_i).to eq(0)
      get '/'
      expect(response).to redirect_to(new_user_session_path)

      post user_sessions_path, params: { username: guest.login, password: "wrong-password" }
      expect(response.body).to include("Incorrect username or password")
      expect(response.body).not_to include("Guest accounts")
    end

    it "ends the session of someone who became a guest since signing in" do
      ensure_setup_completed!
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      get '/'
      expect(response).to have_http_status(:ok)
      user.update_column(:role, 'guest')
      get '/'
      expect(response).to redirect_to(new_user_session_path)
    end

    it "turns a signed-in user away from an admin page to the dashboard, saying why" do
      ensure_setup_completed!
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      get '/disks/storage_pool'
      expect(response).to redirect_to(root_url)
      follow_redirect!
      expect(response.body).to include("That page is for admins.")
    end

    it "starts a fresh session at login" do
      ensure_setup_completed!
      user = create(:user)
      get "/users"  # protected page: stores the return location in the session
      expect(session[:return_to]).to eq("/users")
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      expect(session[:return_to]).to be_nil
      expect(session[:user_id]).to eq(user.id)
    end

    it "signs out other browsers when the password changes, but not this one" do
      ensure_setup_completed!
      user = create(:admin)
      other_browser = open_session
      other_browser.post user_sessions_path, params: { username: user.login, password: "secretpassword" }

      login_as(user)
      put "/users/#{user.id}/update_password",
        params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }
      expect(response.parsed_body["status"]).to eq("ok")

      get root_path
      expect(response).to have_http_status(:ok)
      other_browser.get root_path
      expect(other_browser.response).to have_http_status(:redirect)
      expect(other_browser.response.location).to include(new_user_session_path)
    end

    it "rejects invalid credentials" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "wrongpassword" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end

    it "keeps the name and Remember me after a wrong password, never the password" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "wrongpassword", remember_me: "1" }
      form = Nokogiri::HTML(response.body)
      expect(form.at_css('#username')['value']).to eq(user.login)
      expect(form.at_css('#remember_me')['checked']).to be_present
      expect(form.at_css('#password')['value']).to be_nil
    end

    it "rejects nonexistent users" do
      post user_sessions_path, params: { username: "nobody", password: "password" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end

  describe "DELETE /user_sessions (logout)" do
    it "logs out and redirects to root" do
      user = create(:user)
      login_as(user)
      delete user_session_path(0)
      expect(response).to redirect_to(root_path)
    end

    # The session lives in the cookie: a copy of it would go on working after a sign-out.
    it "signs the user out in every browser, a copy of the cookie included" do
      ensure_setup_completed!
      user = create(:user)
      other_browser = open_session
      other_browser.post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      login_as(user)
      copy = cookies['_amahi_kai_session']
      delete user_session_path(0)
      other_browser.get root_path
      expect(other_browser.response.location).to include(new_user_session_path)
      cookies['_amahi_kai_session'] = copy
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  # Counted at the action, however its path is spelt: the old throttles matched the exact path.
  describe "sign-in attempts" do
    let(:user) { create(:user) }

    before { ensure_setup_completed! }

    it "are limited to 5 in 20 seconds from one address, /user_sessions.json included" do
      5.times { |n| post "/user_sessions#{'.json' if n.odd?}", params: { username: "nobody#{n}", password: 'x' } }
      post '/user_sessions.json', params: { username: user.login, password: 'secretpassword' }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include('Too many sign-in attempts. Wait a minute, then try again.')
      expect(session[:user_id]).to be_nil
      travel 21.seconds do
        post user_sessions_path, params: { username: user.login, password: 'secretpassword' }
        expect(session[:user_id]).to eq(user.id)
      end
    end

    it "are limited to 10 a minute for one login name, however it's spelt" do
      10.times do |n|
        travel_to(Time.current + (n * 5).seconds) { post user_sessions_path, params: { username: n.even? ? user.login : " #{user.login.upcase}", password: 'x' } }
      end
      travel_to(Time.current + 52.seconds) { post user_sessions_path, params: { username: user.login, password: 'secretpassword' } }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "close sign-in to an address for an hour after 20 wrong passwords, and only wrong ones count" do
      start = Time.current
      # Five every 31 seconds: neither limit stands in the way (5 in 20 seconds, 10 a minute)
      sign_in = lambda do |n, password|
        travel_to(start + ((n / 5) * 31).seconds) { post user_sessions_path, params: { username: user.login, password: password } }
      end
      25.times { |n| sign_in.call(n, 'secretpassword') } # successful ones
      expect(response).to redirect_to(root_url)
      20.times { |n| sign_in.call(25 + n, 'wrong') }
      sign_in.call(45, 'secretpassword')
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('sign-in is closed to it for an hour')
      travel_to(start + 2.hours) { post user_sessions_path, params: { username: user.login, password: 'secretpassword' } }
      expect(response).to redirect_to(root_url)
    end
  end

  describe "Remember me" do
    let(:user) { create(:user) }

    before { ensure_setup_completed! }

    def session_cookie = Array(response.headers['Set-Cookie']).flat_map { |h| h.split("\n") }.find { |c| c.start_with?('_amahi_kai_session=') }

    it "keeps the sign-in past the browser's closing only when ticked" do
      post user_sessions_path, params: { username: user.login, password: 'secretpassword' }
      expect(session_cookie).not_to match(/expires=/i) # ends with the browser
      get root_path
      expect(session_cookie.to_s).not_to match(/expires=/i)

      post user_sessions_path, params: { username: user.login, password: 'secretpassword', remember_me: '1' }
      expect(session_cookie).to match(/expires=/i)
      get root_path
      expect(session_cookie).to match(/expires=/i) # seven days from each request
    end

    it "marks the cookie Secure when the browser came over HTTPS (the Cloudflare Tunnel), and not on the LAN" do
      post user_sessions_path, params: { username: user.login, password: 'secretpassword' }
      expect(session_cookie).not_to match(/secure/i)
      post user_sessions_path, params: { username: user.login, password: 'secretpassword' },
                               headers: { 'X-Forwarded-Proto' => 'https', 'CF-Connecting-IP' => '203.0.113.7' }
      expect(session_cookie).to match(/secure/i)
    end
  end

  # The legacy first-run flow created an admin without logging in and never
  # checked whether the system was already initialized. It must stay removed.
  describe "legacy first-run endpoints" do
    it "has no route for the legacy endpoints" do
      [["/user_sessions/initialize_system", :post],
       ["/user_sessions/initialize_system", :get],
       ["/start", :get]].each do |path, verb|
        expect { Rails.application.routes.recognize_path(path, method: verb) }
          .to raise_error(ActionController::RoutingError), "#{verb.upcase} #{path} is still routed"
      end
    end

    it "returns 404 and creates no user for POST /user_sessions/initialize_system" do
      allow(User).to receive(:system_find_name_by_username).and_return(["nobody", 65534, "nobody"])
      post "/user_sessions/initialize_system",
        params: { username: "nobody", password: "longenough1", password_confirmation: "longenough1" }
      expect(response).to have_http_status(:not_found)
      expect(User.where(login: "nobody")).to be_empty
    end

    it "still serves the login page" do
      Setting.where(name: 'initialized').destroy_all
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log In")
    end
  end
end
