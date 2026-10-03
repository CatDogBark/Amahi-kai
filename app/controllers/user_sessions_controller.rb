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
  before_action :login_required, :except => ['new', 'create']
  layout 'login'

  # The first admin comes from db/seeds.rb and the setup wizard (SetupController).
  # The legacy unauthenticated first-run flow (/start, initialize_system) was removed:
  # it never checked whether the system was already initialized.
  def new
    @user_session = UserSession.new
  end

  def create
    username = params[:username]
    password = params[:password]
    remember_me = params[:remember_me]
    @user_session = UserSession.new(:login => username, :password => password, :remember_me => remember_me)
    if @user_session.save
      flash[:success] = t 'logged_in_successfully'
      redirect_to root_url
    else
      flash[:danger] = t 'not_a_valid_user_or_password'
      render :action => 'new'
    end
  end

  # logout - destroy the user session
  def destroy
    @user_session = UserSession.find
    @user_session&.destroy
    flash[:info] = t('you_have_been_logged_out')
    redirect_to root_path
  end

end
