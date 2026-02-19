module RequestHelpers
  def login_as(user)
    ensure_setup_completed!
    post user_sessions_path, params: { username: user.login, password: "secretpassword" }
  end

  def login_as_admin
    admin = create(:admin)
    login_as(admin)
    admin
  end

  def login_as_user
    user = create(:user)
    login_as(user)
    user
  end

  def ensure_setup_completed!
    Setting.find_or_create_by(name: 'setup_completed') do |s|
      s.value = 'true'
      s.kind = 'general'
    end
  rescue => e
    # If Setting table doesn't exist yet, silently continue
    Rails.logger.debug "ensure_setup_completed! skipped: #{e.message}"
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
