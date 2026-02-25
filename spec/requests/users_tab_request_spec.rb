require 'spec_helper'

describe "Users tab (admin)", type: :request do
  before { login_as_admin }

  describe "GET /tab/users" do
    it "renders the users list" do
      get users_engine.users_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Username")
      expect(response.body).to include("Full Name")
    end

    it "lists existing users" do
      user = create(:user, login: "testuser", name: "Test User")
      get users_engine.users_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("testuser")
      expect(response.body).to include("Test User")
    end
  end

  describe "POST /tab/users (create)" do
    it "creates a new user with valid params" do
      post users_engine.users_path, params: {
        user: { login: "newuser", name: "Full Name", password: "secretpassword", password_confirmation: "secretpassword" }
      }
      expect(User.find_by(login: "newuser")).to be_present
    end

    it "rejects blank username" do
      post users_engine.users_path, params: {
        user: { login: "", name: "Full Name", password: "secretpassword", password_confirmation: "secretpassword" }
      }
      expect(response.body).to include("blank")
    end

    it "rejects blank name" do
      post users_engine.users_path, params: {
        user: { login: "newuser", name: "", password: "secretpassword", password_confirmation: "secretpassword" }
      }
      expect(response.body).to include("blank")
    end

    it "rejects short password" do
      post users_engine.users_path, params: {
        user: { login: "newuser", name: "Full Name", password: "short", password_confirmation: "short" }
      }
      expect(response.body).to include("too short")
    end

    it "rejects mismatched password confirmation" do
      post users_engine.users_path, params: {
        user: { login: "newuser", name: "Full Name", password: "secretpassword", password_confirmation: "different" }
      }
      expect(response.body).to include("match")
    end
  end

  describe "DELETE /tab/users/:id" do
    it "deletes a regular user" do
      user = create(:user)
      delete users_engine.user_path(user)
      expect(User.find_by(id: user.id)).to be_nil
    end

    it "does not allow admin to delete themselves" do
      admin = User.find_by(admin: true)
      delete users_engine.user_path(admin)
      expect(User.find_by(id: admin.id)).to be_present
    end
  end

  describe "PUT /tab/users/:id (update)" do
    it "updates user name" do
      user = create(:user)
      put users_engine.update_name_user_path(user), params: { user: { name: "Changed Name" } }
      expect(user.reload.name).to eq("Changed Name")
    end

    it "updates user password" do
      user = create(:user)
      old_digest = user.password_digest
      put users_engine.update_password_user_path(user), params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }
      expect(user.reload.password_digest).not_to eq(old_digest)
    end

    it "toggles admin status" do
      user = create(:user)
      put users_engine.toggle_admin_user_path(user)
      expect(user.reload.admin?).to be true
    end
  end
end

describe "Users tab (non-admin)", type: :request do
  before { login_as_user }

  it "denies access to users page" do
    get users_engine.users_path
    expect(response.body).to include("admin privileges").or(
      satisfy { response.redirect? }
    )
  end
end
