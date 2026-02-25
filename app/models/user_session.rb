# Plain Ruby session wrapper replacing Authlogic::Session::Base.
# Uses Rails session store + bcrypt (has_secure_password) for authentication.

class UserSession
  include ActiveModel::Model
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_reader :record
  attr_accessor :login, :password, :remember_me

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
    if user&.authenticate(@password)
      @record = user
      self.class.controller.session[:user_id] = user.id

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
      @errors.add(:base, "Invalid username or password")
      false
    end
  end

  # Find the current session from the Rails session store.
  def self.find
    return nil unless controller&.session&.[](:user_id)
    user = User.find_by(id: controller.session[:user_id])
    return nil unless user

    # Update last_request_at for activity tracking
    user.update_column(:last_request_at, Time.current) if user.last_request_at.nil? || user.last_request_at < 5.minutes.ago

    session = new
    session.instance_variable_set(:@record, user)
    session
  end

  # Destroy the current session.
  def destroy
    self.class.controller.session.delete(:user_id)
    self.class.controller.reset_session
  end

  # Controller accessor — set by ApplicationController before_action.
  class << self
    attr_accessor :controller
  end
end
