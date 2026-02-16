module RequestHelpers
  def login_as(user)
    post user_sessions_path, params: { username: user.login, password: "secretpassword" }
  end

  def login_as_admin
    admin = create(:admin)
    login_as(admin)
    admin
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
