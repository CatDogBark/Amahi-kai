# Private images: the tokens the NAS keeps for images their owners keep private
# (RegistryTokens, the root helper's registry.rb). Two pages show them: Private images, under
# Apps (index), and Setup → Settings → Tokens (settings), which also lists the Cloudflare Tunnel's
# token. A token is listed, never shown; adding or replacing one asks for the owner's password
# again, and the helper tries it with its registry before keeping it.
class PrivateImagesController < ApplicationController
  before_action :admin_required
  before_action :under_settings, only: :settings

  PASSWORD_TRIES = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 5, within: 1.minute, by: -> { current_user&.id }, store: PASSWORD_TRIES, name: 'registry-token-password',
             only: :save, with: :too_many_tries

  REGISTRIES = %w[ghcr.io docker.io].freeze

  def index
    set_title 'Private images'
    show_tokens
  end

  def settings
    set_title t('tokens')
    show_tokens
  end

  # Adds a token, or replaces a place's: the registry chosen (or typed, for another), whose
  # images, who it signs in as, the token and a note.
  def save
    @fields = token_fields
    return show_again('That isn\'t your password', :password) unless current_user.authenticate(params[:password].to_s)

    reply = RegistryTokens.save(host: @fields[:host], owner: @fields[:owner], username: @fields[:username], token: params[:token].to_s,
                                note: @fields[:note].presence)
    registry = RegistryTokens::NAMES[@fields[:host]] || @fields[:host]
    redirect_to back_path, notice: "The token for #{reply['place']} is #{reply['replaced'] ? 'replaced' : 'saved'}: #{registry} took it."
  rescue Privileged::Error => e
    show_again("Not saved: #{e.message.sub(/[^.)]\z/, '\\0.')}")
  end

  def check
    reply = RegistryTokens.check(params[:place].to_s)
    if reply['worked']
      redirect_to back_path, notice: "#{host_of(params[:place])} still takes the token for #{params[:place]}."
    else
      redirect_to back_path, alert: "The token for #{params[:place]} didn't work: #{reply['error']}. It may have expired or been deleted: replace it with a new one."
    end
  rescue Privileged::Error => e
    redirect_to back_path, alert: "Couldn't check it: #{e.message}"
  end

  def remove
    RegistryTokens.remove(params[:place].to_s)
    redirect_to back_path, notice: "The token for #{params[:place]} is off the NAS. Its registry still has it: delete it there too if you're done with it."
  rescue Privileged::Error => e
    redirect_to back_path, alert: "Couldn't remove it: #{e.message}"
  end

  private

  # Setup → Settings → Tokens: the Setup section, with Settings' tabs
  def under_settings
    @page_section = :setup
    @setup_tab = 'settings'
  end

  def show_tokens
    @tokens = RegistryTokens.all
    @apps = DockerApp.all.to_a
    @fields ||= prefilled_fields
    @tunnel = CloudflareService.token_configured? if action_name == 'settings' || @from == 'settings'
  end

  # The form, filled in from a link (Review's "Add a token for", a token's Replace)
  def prefilled_fields
    replacing = RegistryTokens.find(params[:replace].to_s)
    return { host: replacing.host, owner: replacing.owner, username: replacing.username, note: replacing.note, replacing: replacing.place } if replacing

    host = params[:registry].to_s.strip.downcase.presence || 'ghcr.io'
    { host: host, owner: params[:owner].to_s.strip.downcase, username: '', note: '' }
  end

  def token_fields
    host = params[:registry] == 'other' ? params[:host].to_s.strip.downcase : params[:registry].to_s
    { host: host, owner: params[:owner].to_s.strip.downcase.delete_prefix("#{host}/").delete_suffix('/'), username: params[:username].to_s.strip,
      note: params[:note].to_s.strip, replacing: params[:replacing].presence }
  end

  # The page the form was on again, with what's wrong and the fields as given (never the token)
  def show_again(message, field = :form)
    @from = params[:from] == 'settings' ? 'settings' : nil
    @problem = { field => message }
    under_settings if @from
    if @from
      set_title t('tokens')
      show_tokens
      render :settings, status: :unprocessable_content
    else
      set_title 'Private images'
      show_tokens
      render :index, status: :unprocessable_content
    end
  end

  def back_path
    params[:from] == 'settings' ? settings_tokens_path : private_images_index_path
  end

  def host_of(place)
    host = place.to_s.split('/').first
    RegistryTokens::NAMES[host] || host
  end

  def too_many_tries
    redirect_to back_path, alert: 'Too many tries at your password: wait a minute, then try again.'
  end
end
