# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.

class UsersController < ApplicationController
  before_action :admin_required
  before_action :set_user, only: %i[update update_pubkey destroy toggle_admin update_role update_password update_name update_pin]

  helper_method :can_i_toggle_admin?

  def index
    @page_title = t('users')
    @users = User.all_users
  end

  def create
    @user = User.new(params_user_create)
    if @user.save
      respond_to do |format|
        format.html { redirect_to users_path }
        format.json { render json: { status: :ok, content: render_to_string(template: 'users/index', layout: false) } }
      end
    else
      @users = User.all_users
      respond_to do |format|
        format.html { render :index, status: :unprocessable_entity }
        format.json { render json: { errors: true, content: render_to_string(partial: 'form', locals: { object: @user }), status: :ok } }
      end
    end
  end

  def update
    if can_i_edit_details?(@user)
      name = params[:name].to_s.strip
      if name.blank?
        render json: { status: :not_acceptable, message: t('the_name_cannot_be_blank'), name: @user.name, id: @user.id }
      else
        @user.name = name
        if @user.save
          render json: { status: :ok, message: t('name_changed_successfully'), name: @user.name, id: @user.id }
        else
          render json: { status: :not_acceptable, message: @user.errors.full_messages.join(', '), name: @user.name, id: @user.id }
        end
      end
    else
      render json: { status: :not_acceptable, message: t('dont_have_permissions'), name: @user.name, id: @user.id }
    end
  end

  def update_pubkey
    key = params["public_key_#{@user.id}"]
    key = nil if key.blank?
    @user.public_key = key
    @user.save
    render json: { status: @user.errors.empty? ? :ok : { messages: @user.errors.full_messages } }
  end

  def destroy
    if @user != current_user && !@user.admin?
      @user.destroy
      if @user.errors.any?
        render json: { status: t('error_occured'), id: nil }
      else
        render json: { status: :ok, id: @user.id }
      end
    else
      render json: { status: 'not_acceptable', id: nil }
    end
  end

  def toggle_admin
    if can_i_toggle_admin?(@user)
      @user.admin = !@user.admin
      @user.save!
      render json: { status: :ok }
    else
      render json: { status: :not_acceptable }
    end
  end

  def update_role
    if can_i_toggle_admin?(@user) && User::ROLES.include?(params[:role])
      @user.role = params[:role]
      @user.save!
      render json: { status: :ok, role: @user.role }
    else
      render json: { status: :not_acceptable }, status: :not_acceptable
    end
  end

  def update_password
    if params[:user][:password].blank? || params[:user][:password_confirmation].blank?
      render json: { status: :not_acceptable, message: t('password_cannot_be_blank') }
    else
      @user.update(params_password_update)
      if @user.errors.any?
        render json: { status: :not_acceptable, message: @user.errors.full_messages.join(', ') }
      else
        render json: { status: :ok, message: t('password_changed_successfully') }
      end
    end
  end

  def update_name
    @user.update(params_name_update)
    render json: { status: @user.errors.any? ? :not_acceptable : :ok }
  end

  def update_pin
    if params[:user][:pin].blank? || params[:user][:pin_confirmation].blank?
      render json: { status: :not_acceptable, message: t('pin_cannot_be_blank') }
    elsif params[:user][:pin] != params[:user][:pin_confirmation]
      render json: { status: :not_acceptable, message: t('pins_do_not_match') }
    else
      @user.update(params_pin_update)
      if @user.errors.any?
        render json: { status: :not_acceptable, message: @user.errors.full_messages.join(', ') }
      else
        render json: { status: :ok, message: t('pin_changed_successfully') }
      end
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def can_i_toggle_admin?(user)
    current_user != user && !user.needs_auth?
  end

  def can_i_edit_details?(user)
    current_user == user || current_user.admin?
  end

  def params_user_create
    params.require(:user).permit(:login, :name, :password, :password_confirmation, :pin, :role)
  end

  def params_password_update
    params.require(:user).permit(:password, :password_confirmation)
  end

  def params_name_update
    params.require(:user).permit(:name)
  end

  def params_pin_update
    params.require(:user).permit(:pin, :pin_confirmation)
  end
end
