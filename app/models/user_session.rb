# Plain Ruby session wrapper replacing Authlogic::Session::Base.
# Uses Rails session store + bcrypt (has_secure_password) for authentication.

class UserSession
  # A login unused for this long ends, checked here rather than left to the cookie: with
  # Remember me, IDLE_TIMEOUT (its cookie outlasts the browser that long too); without it,
  # BROWSER_IDLE_TIMEOUT (and its cookie ends with the browser). Either way a login ends
  # MAX_AGE after it was made, however busy, so a copied cookie can't last for good.
  IDLE_TIMEOUT = 7.days
  BROWSER_IDLE_TIMEOUT = 12.hours
  MAX_AGE = 30.days

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
      self.class.controller.session[:signed_in_at] = Time.current.to_i
      self.class.controller.session[:remember] = true if @remember_me.present?

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

  # Find the current session from the Rails session store. With touch: false it reads the
  # session without counting as use (a page's own check of its sign-in, user_sessions#status):
  # an open page would otherwise keep itself signed in.
  def self.find(touch: true)
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

    # A login from before these were kept had a cookie that outlasted the browser: it's taken
    # as remembered, and as made now.
    unless store[:signed_in_at]
      store[:signed_in_at] = Time.current.to_i
      store[:remember] = true
    end
    return expire(store) if Time.at(store[:signed_in_at].to_i) < MAX_AGE.ago

    seen = store[:seen_at].to_i
    return expire(store) if seen.positive? && Time.at(seen) < idle_timeout(store).ago
    if touch
      store[:seen_at] = Time.current.to_i if seen.zero? || Time.at(seen) < 5.minutes.ago

      # Update last_request_at for activity tracking
      user.update_column(:last_request_at, Time.current) if user.last_request_at.nil? || user.last_request_at < 5.minutes.ago
    end

    session = new
    session.instance_variable_set(:@record, user)
    session
  end

  # When the current login ends if nothing uses it before then: its idle limit after it was last
  # seen, and never later than MAX_AGE after the sign-in. The page asks it to go to the sign-in
  # page then (session_watch.js).
  def self.ends_at
    store = controller.session
    seen = store[:seen_at].to_i.positive? ? Time.at(store[:seen_at].to_i) : Time.current
    [seen + idle_timeout(store), Time.at(store[:signed_in_at].to_i) + MAX_AGE].min
  end

  def self.idle_timeout(store)
    store[:remember] ? IDLE_TIMEOUT : BROWSER_IDLE_TIMEOUT
  end
  private_class_method :idle_timeout

  def self.expire(_store)
    controller.reset_session
    nil
  end
  private_class_method :expire

  # Signing out ends every login of the user, in every browser: the session lives in the
  # cookie, so a copy of this one would otherwise go on working. A new session token does it,
  # as a password change does.
  def destroy
    @record&.end_sessions!
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
