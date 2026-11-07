# Apps of the owner's own (docs/plans/apps.md, custom apps): Add your own app on the Apps page.
# The form (or an app file pasted), then a review of what the app will be able to do, then the
# owner's password again, and the root helper keeps it (apps.custom_save) with the catalog's
# checks; Install then works as it does for the catalog's apps. An installed one's Edit saves
# the same way and updates it (apps.update: its data copied first, and back if it doesn't come
# up), unless the change is one its container doesn't see (its name, say, or its logo). Check for
# a newer version asks the image's registry, only when asked.
#
# Its logo is a picture given on the form (LOGO_MAX_BYTES at most), carried through the review
# as base64 (logo_data) and kept by the helper beside its file; the NAS serves it (#logo).
class CustomAppsController < ApplicationController
  before_action :admin_required
  before_action :find_custom, only: %i[edit update destroy check_version version]
  helper_method :logo_src, :current_logo_url

  LOGO_MAX_BYTES = 256 * 1024
  # The policy a logo is served under: no script runs and nothing loads, even in an SVG opened on
  # its own
  LOGO_POLICY = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox".freeze

  # The password again: a few tries a minute for each admin, so a stolen sign-in can't guess it.
  PASSWORD_TRIES = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 5, within: 1.minute, by: -> { current_user&.id }, store: PASSWORD_TRIES, name: 'custom-app-password',
             only: %i[create update], with: :too_many_tries

  FORM_FIELDS = [:name, :description, :category, :sign_in, :image, :run_as, :network, :memory, :web, :shares, :writes_shares,
                 { capabilities: [], ports: {}, folders: {}, settings: {}, secrets: {} }].freeze

  def new
    set_title 'Add your own app'
    @tab = params[:file] ? 'file' : 'form'
    @app = nil
  end

  def edit
    set_title "Edit #{@app.name}"
    @editing = @app.id
    @tab = @app.form ? 'form' : 'file'
    render :new
  end

  # What the app will be able to do, from the form or the file: its image pinned to the build its
  # tag names now, and the helper's checks passed (apps.custom_check). Nothing is saved yet.
  def review
    @editing = params[:editing].presence if AppCatalog.custom_file(params[:editing])
    @tab = params[:source] == 'file' ? 'file' : 'form'
    @app = @tab == 'file' ? CustomApp.from_file(params[:manifest], id: @editing) : CustomApp.from_form(form_fields, id: @editing)
    @logo, problem = chosen_logo
    set_title @editing ? "Edit #{@app.name}" : 'Add your own app'
    # Back, from the review: the form again, as it was described (the file, when the form can't show it)
    if params[:back]
      @tab = @app.form ? 'form' : 'file'
      return render(:new)
    end
    ok = checked(@app)
    @app.errors[:logo] = problem if problem
    return render(:new, status: :unprocessable_content) unless ok && !problem

    set_title "Review: #{@app.name}"
    render :review
  end

  def create
    @app = CustomApp.from_file(params[:manifest], id: params[:id])
    @logo, = chosen_logo
    return unless password_given(@app)
    return review_again(@app, taken_message(@app.id)) if AppCatalog.custom_file(@app.id)

    save(@app) or return
    redirect_to apps_index_path(install: @app.id, anchor: "docker_app_#{@app.id}"), notice: "#{@app.name} is added."
  end

  # Saves the changes, then the app page updates it to them when it's installed and they're ones
  # its container sees (the helper says: update).
  def update
    @editing = @app.id
    @app = CustomApp.from_file(params[:manifest], id: @app.id)
    @logo, = chosen_logo
    return unless password_given(@app)

    saved = save(@app) or return
    installed = DockerApp.find_by(identifier: @app.id)
    installed&.update(name: @app.name, description: @app.data['description'], category: @app.data['category'])
    # The helper doesn't go back a version (Undo update does, for a while)
    if installed&.version && AppCatalog.version_below?(AppCatalog.tag(@app.image), installed.version)
      redirect_to apps_app_path(@app.id), alert: "#{@app.name}'s changes are saved, but #{AppCatalog.tag(@app.image)} is older than " \
                                                 "the #{installed.version} it runs, and an app isn't updated to an older version."
    elsif installed && saved['update'] == false
      installed.relabel_ports(AppCatalog.find(@app.id)&.dig(:ports))
      redirect_to apps_app_path(@app.id), notice: "#{@app.name}'s changes are saved. They're only how it's listed, so it keeps running as it is."
    elsif installed && %w[running stopped].include?(installed.status)
      redirect_to apps_app_path(@app.id, apply: 1), notice: "#{@app.name}'s changes are saved: it updates to them now."
    else
      redirect_to apps_index_path(anchor: "docker_app_#{@app.id}"), notice: "#{@app.name}'s changes are saved."
    end
  end

  # Remove, on its card when it isn't installed (as the Apps page's buttons, JSON).
  def destroy
    Privileged.call('apps.custom_remove', app: @app.id)
    AppCatalog.reload!
    render json: { status: 'ok' }
  rescue Privileged::Error => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_content
  end

  # Its logo, from the NAS (AppCatalog.custom_logo), under LOGO_POLICY. Its address names the
  # picture (v), so that one is cached.
  def logo
    logo = AppCatalog.custom_logo(params[:id]) or return head(:not_found)
    response.headers['Content-Security-Policy'] = LOGO_POLICY
    params[:v] == logo[:version] ? expires_in(1.year) : expires_now
    send_file logo[:path], type: logo[:type], disposition: 'inline'
  end

  # Check for a newer version: a newer release of its image (a tag of the same shape), or a newer
  # build of its tag, from the image's registry. Only when asked; nothing changes.
  def check_version
    found = AppVersions.new.check_image(@app.image)
    flash[:custom_version] = if found.kind == :current
                               { 'kind' => 'current' }
                             else
                               { 'kind' => found.kind.to_s, 'tag' => found.latest, 'major' => found.major }
                             end
    redirect_to apps_app_path(@app.id, anchor: "app-version-#{@app.id}")
  rescue StandardError => e
    redirect_to apps_app_path(@app.id), alert: "Couldn't ask its registry for a newer version: #{e.message}"
  end

  # Update to the newer version Check found: asked for again (the tag must still be the newest),
  # saved as its image, then the app page updates it. The image's repository is the one the owner
  # chose, so this doesn't ask for the password again.
  def version
    found = AppVersions.new.check_image(@app.image)
    if found.kind == :current || found.latest != params[:tag].to_s
      return redirect_to apps_app_path(@app.id), alert: "#{params[:tag]} isn't the newest version any more: check again."
    end

    @app.pin(found.image)
    save(@app) or return
    redirect_to apps_app_path(@app.id, apply: 1)
  rescue StandardError => e
    redirect_to apps_app_path(@app.id), alert: "Couldn't update #{@app.name}: #{e.message}"
  end

  private

  def find_custom
    @app = CustomApp.find(params[:id])
    redirect_to(apps_index_path, alert: "There's no app of your own called #{params[:id]}") unless @app
  end

  def form_fields
    params.fetch(:app, {}).permit(*FORM_FIELDS).to_h
  end

  # Whether +app+ can go to review: a name, an image found and pinned, an id of its own, and the
  # helper's checks. What's wrong is in app.errors.
  def checked(app)
    app.errors[:name] = 'Give it a name, with letters' if app.id.blank? || !app.id.match?(CustomApp::ID)
    app.errors[:image] = 'Name its image, with its tag: mealie-recipes/mealie:v2.4.1' if app.image.blank?
    if app.id.present? && !@editing
      app.errors[:name] ||= taken_message(app.id) if AppCatalog.custom_file(app.id)
      app.errors[:name] ||= "The Amahi-kai catalog has an app called #{app.id}: give yours another name" if catalog_app?(app.id)
    end
    return false if app.errors.any?

    begin
      app.pin(AppVersions.new.pin(app.image))
    rescue StandardError => e
      app.errors[:image] = "Couldn't find that image: #{e.message}"
      return false
    end
    Privileged.call('apps.custom_check', app: app.id, manifest: app.text, **logo_argument)
    true
  rescue Privileged::Error => e
    if e.message.start_with?('the logo')
      app.errors[:logo] = e.message.upcase_first
      @logo = nil
    else
      app.errors[:file] = e.message
    end
    false
  end

  # The logo the request gives: [:remove, { data:, type: } for a picture (chosen now, or before the
  # review and carried in logo_data), or nil to keep the one it has; and what's wrong with a
  # picture chosen, or nil]. The helper checks the picture itself again.
  def chosen_logo
    return [:remove, nil] if params[:logo_remove] == '1'

    upload = params[:logo]
    if upload.respond_to?(:read)
      bytes = upload.read(LOGO_MAX_BYTES + 1).to_s.b
      return [nil, "That picture is over #{LOGO_MAX_BYTES / 1024} KB: give it a smaller one"] if bytes.bytesize > LOGO_MAX_BYTES

      type = CustomApp.logo_type(bytes) or return [nil, "That isn't a PNG, JPEG, WebP or SVG picture"]
      return [{ data: [bytes].pack('m0'), type: type }, nil]
    end

    data = params[:logo_data].to_s
    type = CustomApp.logo_type(data.unpack1('m0')) if data.match?(%r{\A[A-Za-z0-9+/]+={0,2}\z})
    [type && { data: data, type: type }, nil]
  rescue ArgumentError
    [nil, nil]
  end

  # The helper's logo argument for the logo chosen: the picture, empty to remove it, or none.
  def logo_argument
    case @logo
    when Hash then { logo: @logo[:data] }
    when :remove then { logo: '' }
    else {}
    end
  end

  # What the pages show as its logo: the picture chosen, none when it's to be removed, else the
  # one it has.
  def logo_src
    case @logo
    when Hash then "data:#{@logo[:type]};base64,#{@logo[:data]}"
    when :remove then nil
    else current_logo_url
    end
  end

  # The logo kept for the app being edited, or nil.
  def current_logo_url
    entry = @editing && AppCatalog.find(@editing)
    entry[:logo_url] if entry&.dig(:custom)
  end

  def catalog_app?(id)
    entry = AppCatalog.find(id)
    entry.present? && !entry[:custom]
  end

  def taken_message(id)
    "You have an app called #{id} already: edit that one, or give this one another name"
  end

  # The owner's password, asked again: else the review again, saying so.
  def password_given(app)
    return true if current_user.authenticate(params[:password].to_s)

    review_again(app, "That isn't your password", :password)
    false
  end

  def review_again(app, message, field = :file)
    app.errors[field] = message
    set_title "Review: #{app.name}"
    render :review, status: :unprocessable_content
  end

  # The helper's reply (update: whether its container needs the change), or false.
  def save(app)
    reply = Privileged.call('apps.custom_save', app: app.id, manifest: app.text, **logo_argument)
    AppCatalog.reload!
    reply
  rescue Privileged::Error => e
    review_again(app, e.message)
    false
  end

  def too_many_tries
    redirect_to apps_index_path, alert: 'Too many tries at your password: wait a minute, then add the app again.'
  end
end
