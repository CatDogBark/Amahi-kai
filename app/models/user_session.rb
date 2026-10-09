# Plain Ruby session wrapper replacing Authlogic::Session::Base.
# Uses Rails session store + bcrypt (has_secure_password) for authentication.

class UserSession
  # A login unused for this long ends, checked here rather than left to the cookie.
  IDLE_TIMEOUT = 7.days

  include ActiveModel::Model
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_reader :record
  attr_accessor :login, :password, :remember_me

  # A guest account uses the network shares (SMB) only: right password or not, it doesn't sign
  # in to the web UI (guest? says so after a refused save, for the page's message).
  def guest?
    @guest == true
  end

  def persisted?
    false
  end

  def initialize(attrs = {})
    @login = attrs[:login]
    @password = attrs[:password]
    @remember_me = attrs[:remember_me]
    @record = nil
    super()
  end

  # Authenticate and store user_id in the Rails session.
  # Returns true on success, false on failure.
  def save
    user = User.find_by("LOWER(login) = ?", @login.to_s.downcase)
    if user&.authenticate(@password) && user.guest?
      @guest = true
      errors.add(:base, "Guest accounts use the network shares only")
      false
    elsif user&.authenticate(@password)
      @record = user
      # Start a fresh session, so a session id issued before login can't be reused after it.
      self.class.controller.reset_session
      self.class.controller.session[:user_id] = user.id
      self.class.controller.session[:session_token] = user.session_token
      self.class.controller.session[:seen_at] = Time.current.to_i

      # Update login tracking columns
      now = Time.current
      ip = self.class.controller.request.remote_ip
      user.update_columns(
        last_login_at: user.current_login_at,
        last_login_ip: user.current_login_ip,
        current_login_at: now,
        current_login_ip: ip,
        login_count: (user.login_count || 0) + 1,
        last_request_at: now
      )
      true
    else
      errors.add(:base, "Invalid username or password")
      false
    end
  end

  # Find the current session from the Rails session store.
  def self.find
    store = controller&.session
    return nil unless store&.[](:user_id)
    user = User.find_by(id: store[:user_id])
    return nil unless user
    # A guest has no web UI: a session from before it became one (or before guests were
    # refused) ends.
    return expire(store) if user.guest?

    # A password change gives the user a new token; sessions holding the old one end.
    # (Sessions from before tokens existed carry none and match a user who has none.)
    return expire(store) if user.session_token.present? && store[:session_token] != user.session_token

    seen = store[:seen_at].to_i
    return expire(store) if seen.positive? && Time.at(seen) < IDLE_TIMEOUT.ago
    store[:seen_at] = Time.current.to_i if seen.zero? || Time.at(seen) < 5.minutes.ago

    # Update last_request_at for activity tracking
    user.update_column(:last_request_at, Time.current) if user.last_request_at.nil? || user.last_request_at < 5.minutes.ago

    session = new
    session.instance_variable_set(:@record, user)
    session
  end

  def self.expire(_store)
    controller.reset_session
    nil
  end
  private_class_method :expire

  # Destroy the current session.
  def destroy
    self.class.controller.session.delete(:user_id)
    self.class.controller.reset_session
  end

  # The controller handling this request, set by an ApplicationController before_action.
  # It lives in Current rather than a class variable: Puma serves requests on several
  # threads, and one shared variable let a request read or write another request's session.
  class << self
    def controller
      Current.controller
    end

    def controller=(controller)
      Current.controller = controller
    end
  end
end
