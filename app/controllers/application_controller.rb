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
  rescue_from ActionController::InvalidAuthenticityToken, with: :page_out_of_date

  before_action :session_cookie_options
  before_action :set_user_session_controller
  before_action :check_setup_completed

  helper_method :current_user, :advanced?, :session_ends_in

  private

  # A red flag for something that went wrong. One that broke (:failed) offers Report a problem
  # (toast.js); one that only needs a change, like a refusal, keeps the page's own red flag
  # (+refusal+).
  def flash_failure(message, error = nil, now: false, refusal: :error)
    (now ? flash.now : flash)[broke?(error) ? :failed : refusal] = message
  end

  # Whether an error means something broke: it says so itself (ReportableError#failed?, or a
  # root helper's refusal, Privileged::Error#refused?); any other, or none given, broke.
  def broke?(error)
    return error.failed? if error.respond_to?(:failed?)
    return !error.refused? if error.respond_to?(:refused?)

    true
  end

  # A request the page makes by itself (fetch, asking for JSON), not the page loading.
  def background_request?
    request.xhr? || request.format.json?
  end

  # Tells a page that its sign-in ended ('signed-out') or that it's from an earlier one
  # ('out-of-date'), in the header its script acts on (session_watch.js: it reloads, which
  # leads to the sign-in page when signed out) and in the error its handlers show.
  def tell_page(state, message, status)
    response.set_header('X-Amahi-Session', state)
    render json: { status: 'error', error: message }, status: status
  end

  # A form or a page's request with a token this session never gave it: the page is from
  # before its sign-in ended or changed (the idle limit, a sign-out elsewhere, a reinstall).
  # Nothing is done, and the page is told so, instead of getting Rails' bare 422.
  def page_out_of_date
    set_user_session_controller # the token's check runs before the filter that does it
    signed_in = current_user.present?
    if background_request?
      return tell_page('out-of-date', t('page_out_of_date'), :unprocessable_entity) if signed_in

      tell_page('signed-out', t('signed_out'), :unauthorized)
    elsif signed_in || controller_name == 'user_sessions'
      flash[:info] = t('page_out_of_date')
      redirect_back_or_to(signed_in ? root_path : new_user_session_path)
    else
      flash[:info] = t('signed_out')
      redirect_to new_user_session_path
    end
  end

  # Seconds until this login ends unless it's used (UserSession.ends_at), for the page's
  # amahi-session meta tag.
  def session_ends_in
    (UserSession.ends_at - Time.current).ceil
  end

  # Advanced mode (the header's toggle), read once per request, and only when a page asks.
  def advanced?
    return @advanced if defined?(@advanced)
    @advanced = Setting.get('advanced') == '1'
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
    return @setup_completed if defined?(@setup_completed)
    val = Setting.get('setup_completed')
    @setup_completed = (val == 'true' || val == '1')
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

  # A login with Remember me keeps its cookie past the browser's closing, for UserSession's
  # IDLE_TIMEOUT from this request; without it the cookie ends with the browser. Through the
  # Cloudflare Tunnel the browser talks HTTPS (cloudflared says so, X-Forwarded-Proto), so the
  # cookie is sent over HTTPS only; on the LAN it's plain HTTP, where a Secure cookie would
  # never come back (Rack doesn't even save a Secure session on a plain request).
  def session_cookie_options
    request.session_options[:expire_after] = UserSession::IDLE_TIMEOUT if session[:remember]
    request.session_options[:secure] = true if request.ssl?
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

  # A page load goes to the sign-in page and comes back after it; a page's own request is told
  # the sign-in ended (it was redirected to the sign-in page, which no handler could read).
  def login_required
    return if current_user

    if background_request?
      tell_page('signed-out', t('signed_out'), :unauthorized)
    else
      store_location
      flash[:info] = I18n.t('must_be_logged_in')
      redirect_to new_user_session_path
    end
    false
  end

  # Someone signed in who isn't an admin is turned away to the dashboard (they're signed in
  # already: the sign-in page made no sense), with a word on why.
  def admin_required
    return false if login_required == false
    unless current_user.admin?
      flash[:info] = t('must_be_admin')
      redirect_to root_url
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
