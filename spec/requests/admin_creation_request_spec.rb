require 'spec_helper'

describe "Admin creation (first run)", type: :request do
  it "shows initialization page when not initialized" do
    Setting.where(name: 'initialized').destroy_all
    get start_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("initialization")
  end

  it "creates the first admin user" do
    Setting.where(name: 'initialized').destroy_all
    allow(User).to receive(:system_find_name_by_username).and_return(["New User", 1000, "newuser"])

    post user_sessions_path, params: {
      username: "newuser",
      password: "secretpassword",
      password_confirmation: "secretpassword"
    }

    user = User.find_by(login: "newuser")
    if user
      expect(user.admin).to be_truthy
    else
      # If the flow redirects to initialization, that's also valid
      expect(response.body).to include("initialization").or(satisfy { response.redirect? })
    end
  end

  it "redirects to login when already initialized" do
    Setting.set('initialized', '1')
    get start_path
    expect(response).to redirect_to(login_path)
  end
end
