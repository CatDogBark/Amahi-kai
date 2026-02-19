class SetupController < ApplicationController
  layout 'setup'

  # Skip the setup redirect for this controller (avoid infinite loop)
  skip_before_action :check_setup_completed
  before_action :login_required
  before_action :admin_required

  def welcome
  end

  def admin
  end

  def update_admin
    user = current_user
    if params[:password].blank?
      flash[:error] = "Password cannot be blank."
      render :admin and return
    end
    if params[:password] != params[:password_confirmation]
      flash[:error] = "Passwords do not match."
      render :admin and return
    end
    if params[:password].length < 8
      flash[:error] = "Password must be at least 8 characters."
      render :admin and return
    end
    user.password = params[:password]
    user.password_confirmation = params[:password_confirmation]
    if user.save
      session[:admin_password_changed] = true
      redirect_to setup_network_path
    else
      flash[:error] = user.errors.full_messages.join(", ")
      render :admin
    end
  end

  def network
    @hostname = `hostname`.strip rescue "amahi"
    @ip = `hostname -I`.strip.split.first rescue "unknown"
    @server_name = Setting.get('server-name') || @hostname
  end

  def update_network
    name = params[:server_name].to_s.strip
    Setting.set('server-name', name) unless name.blank?
    redirect_to setup_storage_path
  end

  def storage
    @partitions = begin
      require 'partition_utils'
      PartitionUtils.new.info
    rescue => e
      Rails.logger.error("SetupController#storage: #{e.message}")
      []
    end
    @pool_partitions = DiskPoolPartition.all.map(&:path) rescue []
  end

  def update_storage
    # Remove all existing pool partitions first
    DiskPoolPartition.destroy_all

    if params[:partitions].present?
      params[:partitions].each do |path|
        min_free = path == '/' ? 20 : 10
        DiskPoolPartition.create(path: path, minimum_free: min_free)
      end
    end
    redirect_to setup_share_path
  end

  def share
  end

  def create_share
    name = params[:share_name].to_s.strip
    if name.blank?
      redirect_to setup_complete_path and return
    end

    path = File.join(Share::DEFAULT_SHARES_ROOT, name.downcase.gsub(/\s+/, '-'))
    share = Share.new(
      name: name,
      path: path,
      visible: true,
      rdonly: false,
      everyone: true,
      tags: name.downcase,
      extras: "",
      disk_pool_copies: 0
    )

    if share.save
      session[:first_share_created] = name
    else
      flash[:error] = share.errors.full_messages.join(", ")
      render :share and return
    end

    redirect_to setup_complete_path
  end

  def complete
    @admin_password_changed = session[:admin_password_changed]
    @server_name = Setting.get('server-name')
    @pool_partitions = DiskPoolPartition.all rescue []
    @first_share = session[:first_share_created]
  end

  def finish
    Setting.set('setup_completed', 'true')
    session.delete(:admin_password_changed)
    session.delete(:first_share_created)
    redirect_to root_path, notice: "Setup complete! Welcome to Amahi-kai."
  end
end
