# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.

require 'partition_utils'
require 'open3'

class SharesController < ApplicationController
  before_action :admin_required
  before_action :find_share, only: %i[
    destroy toggle_visible toggle_everyone toggle_readonly toggle_access
    toggle_write toggle_guest_access toggle_guest_writeable
    update_path update_extras clear_permissions
    update_disk_pool_copies update_size update_name
  ]

  VALID_NAME = /\A\w[\w ]+\z/

  # --- CRUD ---

  def index
    @page_title = t('shares')
    Greyhole.sync_removals! # shares Greyhole has finished moving off the pool turn Off
    @shares = Share.by_name
  end

  def create
    @share = Share.new(params_create_share)
    if @share.save
      respond_to do |format|
        format.html { redirect_to shares_path, notice: "Share '#{@share.name}' created successfully" }
        format.json
      end
    else
      @shares = Share.by_name
      respond_to do |format|
        format.html { render :index, status: :unprocessable_entity }
        format.json
      end
    end
  end

  def destroy
    @share.destroy
    render json: { status: :ok, id: @share.id }
  end

  # --- Settings ---

  def settings
    unless @advanced
      redirect_to shares_path
    else
      @page_title = t('shares')
      @workgroup = Setting.find_or_create_by(Setting::GENERAL, 'workgroup', 'WORKGROUP')
    end
  end

  # --- Toggles ---

  def toggle_visible
    @share.visible = !@share.visible
    @share.save
    render json: { status: :ok }
  end

  def toggle_everyone
    if @share.everyone
      allu = User.all
      @share.users_with_share_access = allu
      @share.users_with_write_access = allu
      @share.everyone = false
      @share.rdonly = true
    else
      @share.users_with_share_access = []
      @share.users_with_write_access = []
      @share.guest_access = false
      @share.guest_writeable = false
      @share.everyone = true
    end
    @share.save
    render json: { status: :ok }
  end

  def toggle_readonly
    @share.rdonly = !@share.rdonly
    @share.save
    render json: { status: :ok }
  end

  def toggle_access
    unless @share.everyone
      user = User.find(params[:user_id])
      if @share.users_with_share_access.include?(user)
        @share.users_with_share_access -= [user]
      else
        @share.users_with_share_access += [user]
      end
      @share.save
    end
    render json: { status: :ok }
  end

  def toggle_write
    unless @share.everyone
      user = User.find(params[:user_id])
      if @share.users_with_write_access.include?(user)
        @share.users_with_write_access -= [user]
      else
        @share.users_with_write_access += [user]
      end
      @share.save
    end
    render json: { status: :ok }
  end

  def toggle_guest_access
    if @share.guest_access
      @share.guest_access = false
    else
      @share.guest_access = true
      @share.guest_writeable = false
    end
    @share.save
    render json: { status: :ok }
  end

  def toggle_guest_writeable
    @share.guest_writeable = !@share.guest_writeable
    @share.save
    render json: { status: :ok }
  end

  # --- Field Updates ---

  def update_name
    @share.name = params[:value]
    if @share.save
      @share.reload
      render plain: @share.name
    else
      render plain: @share.errors.full_messages.join(", "), status: :unprocessable_entity
    end
  end

  def update_path
    if params[:value].present?
      @share.path = params[:value]
      if @share.save
        @share.reload
        render plain: @share.path
      else
        render plain: @share.errors.full_messages.join(", "), status: :unprocessable_entity
      end
    else
      @saved = @share.update(params_update_path)
      Share.push_shares if @saved
      render json: { status: @saved ? :ok : :not_acceptable }
    end
  end

  def update_extras
    if params[:value].present?
      @share.extras = params[:value]
      if @share.save
        @share.reload
        extras = @share.extras.blank? ? t('add_extra_parameters') : @share.extras
        render plain: extras
      else
        render plain: @share.errors.full_messages.join(", "), status: :unprocessable_entity
      end
    else
      params[:share] = sanitize_text(params_update_extras)
      @saved = @share.update_extras!(params_update_extras)
      render json: { status: @saved ? :ok : :not_acceptable }
    end
  end

  def update_workgroup
    @workgroup = Setting.find(params[:id]) if params[:id]
    if @workgroup && @workgroup.name.eql?("workgroup")
      params[:share][:value].strip!
      @saved = @workgroup.update(params_update_workgroup)
      @errors = @workgroup.errors.full_messages.join(', ') unless @saved
      name = @workgroup.value
      Share.push_shares
    end
    render json: { status: @saved ? :ok : :not_acceptable, message: @saved ? t('workgroup_changed_successfully') : t('error_occured'), name: name }
  end

  def clear_permissions
    @share.users_with_share_access = []
    @share.users_with_write_access = []
    @share.save
    render json: { status: :ok }
  end

  # --- Disk Pool ---

  # The shares page sends `copies` and expects JSON back (shares.js updatePoolCopies).
  def update_disk_pool_copies
    set_disk_pool_copies([(params[:copies] || params[:value]).to_i, 0].max)
  end

  # --- Size ---

  def update_size
    std_out, status = Open3.capture2e("du -sbL #{Shellwords.escape(@share.path)}")
    size = std_out.split(' ').first
    is_integer = Integer(size) rescue false
    if is_integer && status
      helper = Object.new.extend(ActionView::Helpers::NumberHelper)
      size = helper.number_to_human_size(size)
    else
      size = std_out
    end
    render json: { status: :ok, size: size, id: @share.id }
  rescue Errno::ENOENT, Errno::EACCES, IOError => e
    render json: { status: :ok, size: e.to_s, id: @share&.id }
  end

  private

  # Off for a share with files in the pool waits for Greyhole to move them back into the
  # share's folder (removing: true); nothing changes while it does.
  def set_disk_pool_copies(copies)
    if @share.pool_removing?
      return render json: { status: :error, message: "Greyhole is still moving this share's files back into its folder.",
                            disk_pool_copies: @share.disk_pool_copies, removing: true }
    end
    if copies.zero? && @share.disk_pool_copies.positive?
      removing = Greyhole.remove_share!(@share) == :removing
      return render json: { status: :ok, disk_pool_copies: @share.reload.disk_pool_copies, removing: removing }
    end
    @share.disk_pool_copies = copies
    save_disk_pool_copies
  rescue Greyhole::GreyholeError, Shell::CommandError => e
    render json: { status: :error, message: e.message, disk_pool_copies: @share.reload.disk_pool_copies }
  end

  def save_disk_pool_copies
    @share.save
    begin
      # Stopped or not, Greyhole reads this config when it next starts: a share left out of it
      # gets no copies, and Greyhole uses no drive for it.
      Greyhole.configure! if Greyhole.installed?
    rescue Greyhole::GreyholeError, Shell::CommandError => e
      Rails.logger.error("Greyhole configure failed: #{e.message}")
    end
    render json: { status: :ok, disk_pool_copies: @share.reload.disk_pool_copies }
  end

  def find_share
    return unless params[:id]
    @share = if params[:id].to_s =~ /\A\d+\z/
      Share.find(params[:id])
    else
      Share.find_by!(name: params[:id])
    end
  end

  def params_create_share
    params.require(:share).permit(:name, :visible, :rdonly).merge(path: Share.default_full_path(params[:share][:name]))
  end

  def params_update_path
    params.require(:share).permit(:path)
  end

  def params_update_workgroup
    params.require(:share).permit(:value)
  end

  def params_update_extras
    params.require(:share).permit(:extras)
  end
end
