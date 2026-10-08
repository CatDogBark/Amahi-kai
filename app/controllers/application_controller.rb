# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :set_user_session_controller
  before_action :before_action_hook
  before_action :check_setup_completed

  helper_method :current_user

  private

  def before_action_hook
    adv = Setting.where(:name=>'advanced').first
    @advanced = adv && adv.value == '1'
  end

  # The values of +params+ with Windows line endings (\r\n, a ^M at each line's end) made \n.
  def sanitize_text(params)
    params.to_h.transform_values { |value| value.lines.map(&:chomp).join("\n") }
  end

  def check_setup_completed
    return if setup_completed?
    return if self.is_a?(SetupController)
    # Allow session/login routes so user can authenticate first
    return if controller_name == 'user_sessions'
    # Allow API and health check routes
    return if request.path.start_with?('/api/', '/health')
    return unless current_user # Must be logged in first
    redirect_to setup_welcome_path
  end

  def setup_completed?
    val = Setting.get('setup_completed')
    val == 'true' || val == '1'
  end
  helper_method :setup_completed?

  # The page came through the Cloudflare Tunnel: cloudflared connects from the NAS itself and
  # adds CF-Connecting-IP (as in config/initializers/rack_attack.rb). Apps' own ports aren't on
  # the tunnel, so their Open links only work on the LAN and Tailscale.
  def via_tunnel?
    %w[127.0.0.1 ::1].include?(request.remote_addr) && request.headers['CF-Connecting-IP'].present?
  end
  helper_method :via_tunnel?

  def set_user_session_controller
    UserSession.controller = self
  end

  def current_user_session
    return @current_user_session if defined?(@current_user_session)
    @current_user_session = UserSession.find
  end

  def current_user
    return @current_user if @current_user.present?
    @current_user = current_user_session && current_user_session.record
  end

  # After a user changes their own password, keep this browser signed in. Their other
  # sessions end: they still hold the old session token.
  def keep_signed_in_after_password_change(user)
    session[:session_token] = user.session_token if user == current_user
  end

  def login_required
    unless current_user
      store_location
      flash[:info] = I18n.t('must_be_logged_in')
      redirect_to new_user_session_path
      return false
    end
  end

  def admin_required
    return false if login_required == false
    unless current_user.admin?
      store_location
      flash[:info] = t('must_be_admin')
      redirect_to new_user_session_url
      return false
    end
  end

  # Requires a user who can browse files (admin or user role, not guest)
  def browse_required
    return false if login_required == false
    unless current_user.can_browse?
      flash[:info] = t('must_be_admin')
      redirect_to root_url
      return false
    end
  end

  def store_location
    session[:return_to] = request.fullpath
  end

  def set_title(title)
    @page_title = title
  end


  def development?
    Rails.env == 'development'
  end

  def test?
    Rails.env == 'test'
  end


end
