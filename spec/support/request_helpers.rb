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
    Setting.set('setup_completed', 'true')
  rescue => e
    # If Setting table doesn't exist yet, silently continue
    Rails.logger.debug "ensure_setup_completed! skipped: #{e.message}"
  end

  # Engine path helpers — work around a Rails 8.0 RoutesProxy bug where
  # merge_script_names blows up when script_name is "" (empty string) in
  # integration test sessions (slice(0, negative) returns nil, then .join fails).
  def users_engine
    @_users_engine_proxy ||= UsersEngineProxy.new
  end

  def network_engine
    @_network_engine_proxy ||= NetworkEngineProxy.new
  end

  class UsersEngineProxy
    def root_path
      "/users"
    end

    def users_path
      "/users"
    end

    def user_path(user_or_id)
      id = user_or_id.respond_to?(:id) ? user_or_id.id : user_or_id
      "/users/#{id}"
    end

    def update_name_user_path(user_or_id)
      "#{user_path(user_or_id)}/update_name"
    end

    def update_password_user_path(user_or_id)
      "#{user_path(user_or_id)}/update_password"
    end

    def toggle_admin_user_path(user_or_id)
      "#{user_path(user_or_id)}/toggle_admin"
    end
  end

  class NetworkEngineProxy
    PREFIX = "/tab/network"

    def hosts_path
      "#{PREFIX}/hosts"
    end

    def dns_aliases_path
      "#{PREFIX}/dns_aliases"
    end
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
