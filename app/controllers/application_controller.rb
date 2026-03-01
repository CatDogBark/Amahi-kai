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

require 'set_theme'

class ApplicationController < ActionController::Base
  require 'ipaddr'
  protect_from_forgery with: :exception

  before_action :set_user_session_controller
  before_action :before_action_hook
  before_action :check_setup_completed
  before_action :initialize_validators
  before_action :accessed_from_ip

  helper_method :current_user

  def accessed_from_ip
    # Legacy DNS nag removed — users access via IP and that's fine
  end

  def initialize_validators
    @validators_string = ''
  end

  def before_action_hook
    set_locale
    set_direction
    check_for_amahi_app
    prepare_theme
    adv = Setting.where(:name=>'advanced').first
    @advanced = adv && adv.value == '1'
  end

  def check_for_amahi_app
    server = request.env['SERVER_NAME']
    dom = Setting.get_by_name('domain')
    hostname = Setting.get('server-name') || 'amahi-kai'
    if server && server != hostname && server =~ /\A(.*)\.#{dom}\z/
      server = $1
    end
    if server && server != hostname && DnsAlias.where(:name=>server).first
      redirect_to "http://#{hostname}/apps/#{server}"
    end
  end

  def prepare_theme
    @theme = SetTheme.find
    prepend_view_path("public/themes/#{@theme.path}/views")
  end

  class Helper
    include Singleton
    include ActionView::Helpers::NumberHelper
  end

  def number_helpers
    Helper.instance
  end

  def setup_router
    @router = nil
    r = Setting.get_kind('network', 'router_model')
    return @router unless r
    begin
      rd = RouterDriver.current_router = (r ? r.value : "")
      # return the class proper if valid
      @router = Kernel.const_get(rd) unless rd.blank?
      u = Setting.network.where(:name=>'router_username').first
      p = Setting.network.where(:name=>'router_password').first
      RouterDriver.set_auth(unobfuscate(u.value), unobfuscate(p.value)) if p and u and p.value and u.value
    rescue NameError, ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid => e
      Rails.logger.debug("Router driver not available: #{e.message}")
    end
    @router
  end

  def locales_implemented
    Yetting.locales_implemented
  end

  # Sanitizes the String or a Hash by removing the
  # escape characters like ^M which is originated from
  # end-of-line on Windows platform.
  # Expects either a Hash or a String,
  # and returns the same
  def sanitize_text(arg)
    arg = arg.to_h
    if arg.is_a? Hash
      Hash[arg.to_a.map do |x, y|
        [x, y.lines.map(&:chomp).join("\n")]
      end]
    else
      #arg is a String
      arg.lines.map(&:chomp).join("\n")
    end
  end

  private

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

  def set_locale

    preferred_locales = request.headers['HTTP_ACCEPT_LANGUAGE'].split(',').map { |locale| locale.split(';').first } rescue nil
    available_locales = I18n.available_locales
    default_locale = I18n.default_locale
    locale_from_params = params[:locale]

    I18n.locale = begin
      locale = preferred_locales.select { |locale| available_locales.include?(locale.to_sym) }
      default_locale = locale.empty? ? default_locale : locale.first

      # Allow a URL param to override everything else, for devel
      if locale_from_params
        if available_locales.include?(locale_from_params.to_sym)
          cookies['locale'] = { :value => locale_from_params, :expires => 1.year.from_now }
          locale_from_params.to_sym
        else
          cookies.delete 'locale'
          default_locale
        end
      elsif cookies['locale'] && available_locales.include?(cookies['locale'].to_sym)
        cookies['locale'].to_sym
      else
        cookies['locale'] = { :value => default_locale, :expires => 1.year.from_now }
        default_locale
      end
    rescue I18n::InvalidLocale, NoMethodError, ArgumentError => e
      # if something happens (like a locale file renamed!?) go back to the default
      default_locale
    end
  end

  def set_direction
    # right to left language support
    @locale_direction = Yetting.rtl_locales.include?(I18n.locale) ? 'rtl' : 'ltr'
  end

  # Credential encryption using Rails' MessageEncryptor.
  # Falls back to legacy ROT13 decoding for pre-existing values.
  CREDENTIAL_ENCRYPT_PREFIX = "enc:".freeze

  def obfuscate(s)
    return s if s.blank?
    CREDENTIAL_ENCRYPT_PREFIX + credential_encryptor.encrypt_and_sign(s)
  end

  def unobfuscate(s)
    return s if s.blank?
    if s.start_with?(CREDENTIAL_ENCRYPT_PREFIX)
      credential_encryptor.decrypt_and_verify(s.delete_prefix(CREDENTIAL_ENCRYPT_PREFIX))
    else
      # Legacy ROT13 fallback for pre-existing values
      s.tr("N-Zn-zA-Ma-m", "A-Ma-mN-Zn-z")
    end
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    # If decryption fails, return empty string rather than crash
    ""
  end

  def credential_encryptor
    key = Rails.application.secret_key_base[0..31]
    ActiveSupport::MessageEncryptor.new(key)
  end

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

  def no_subtabs
    @no_subtabs = true
  end


  def development?
    Rails.env == 'development'
  end

  def test?
    Rails.env == 'test'
  end


end
