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

class UserSessionsController < ApplicationController
  # Sign-in attempts are counted at the action, however its path is spelt (/user_sessions.json
  # reaches it too): 5 in 20 seconds from one address, 10 a minute for one login name. An
  # address that fails BAN_AFTER times within an hour is turned away for the rest of that hour;
  # successful sign-ins don't count. The counts are this process's (Puma runs one).
  ATTEMPTS = ActiveSupport::Cache::MemoryStore.new
  BAN_AFTER = 20
  BAN_FOR = 1.hour

  before_action :login_required, :except => ['new', 'create', 'status']
  skip_before_action :check_setup_completed, only: :status
  before_action :turned_away, only: :create
  rate_limit to: 5, within: 20.seconds, by: -> { Rack::Attack.client_ip(request) }, with: :too_many_attempts,
             store: ATTEMPTS, name: 'address', only: :create
  rate_limit to: 10, within: 1.minute, by: -> { params[:username].to_s.downcase.strip }, with: :too_many_attempts,
             store: ATTEMPTS, name: 'login', only: :create
  layout 'login'

  # The first admin comes from db/seeds.rb and the setup wizard (SetupController).
  # The legacy unauthenticated first-run flow (/start, initialize_system) was removed:
  # it never checked whether the system was already initialized.
  def new
    @user_session = UserSession.new
  end

  # A signed-in page's own check of its sign-in (session_watch.js), which doesn't count as using
  # it, so an open page can't keep itself signed in: how long it has left, or that it ended
  # (200 either way: the answer is the state, not a failure). The cookie is left as it was.
  def status
    request.session_options[:skip] = true
    return tell_page('signed-out', t('signed_out'), :ok) unless UserSession.find(touch: false)

    render json: { status: 'ok', ends_in: session_ends_in }
  end

  def create
    username = params[:username]
    password = params[:password]
    remember_me = params[:remember_me]
    @user_session = UserSession.new(:login => username, :password => password, :remember_me => remember_me)
    # The page that sent here (login_required kept it), read before the sign-in's fresh session
    back_to = local_path(session[:return_to])
    if @user_session.save
      # This response's cookie already follows the box (session_cookie_options read the old session).
      request.session_options[:expire_after] = remember_me.present? ? UserSession::IDLE_TIMEOUT : nil
      flash[:success] = t 'logged_in_successfully'
      redirect_to back_to || root_url
    else
      count_failure unless @user_session.guest?
      flash.now[:danger] = @user_session.guest? ? t('guests_use_shares') : t('not_a_valid_user_or_password')
      # The form keeps the name and the Remember me box, so only the password is typed again
      @login = username
      @remember_me = remember_me.present?
      render :action => 'new', formats: [:html]
    end
  end

  # logout - destroy the user session
  def destroy
    @user_session = UserSession.find
    @user_session&.destroy
    flash[:info] = t('you_have_been_logged_out')
    redirect_to root_path
  end

  private

  # A path on this server, never another site's address: //host and /\host are one to a browser.
  def local_path(path)
    path if path.is_a?(String) && path.start_with?('/') && !path.start_with?('//') && !path.include?('\\')
  end

  def client_ip
    Rack::Attack.client_ip(request)
  end

  def count_failure
    failures = ATTEMPTS.increment("failed:#{client_ip}", 1, expires_in: BAN_FOR)
    ATTEMPTS.write("banned:#{client_ip}", true, expires_in: BAN_FOR) if failures.to_i >= BAN_AFTER
  end

  def turned_away
    return unless ATTEMPTS.exist?("banned:#{client_ip}")

    refuse_attempt(t('sign_in_turned_away'), :forbidden)
  end

  def too_many_attempts
    refuse_attempt(t('too_many_sign_in_attempts'), :too_many_requests)
  end

  # The sign-in page again, with why, the name kept.
  def refuse_attempt(message, status)
    @user_session = UserSession.new
    @login = params[:username]
    @remember_me = params[:remember_me].present?
    flash.now[:danger] = message
    render :new, status: status, formats: [:html]
  end
end
