# frozen_string_literal: true

# Custom apps: apps of the owner's own, on this NAS only (docs/plans/apps.md, custom apps). The
# catalog (CATALOG_REPO) is the official set every NAS gets; a custom app is an app file written
# the same way, which the owner adds on the Apps page, and which nothing fetches or changes but
# the owner. Each is kept as APP_CUSTOM/<id>.yml, which only this helper writes, once it passes
# the checks a catalog manifest gets (check_listing, check_manifest), and from there it installs,
# updates and runs exactly as the catalog's apps do (apps.rb): its own user, network and
# folders, no kernel capabilities but those it lists, its image pinned by digest. There's no way
# to ask in one for what no app gets (privileged mode, the NAS's network, devices, other
# folders): a manifest has no field for them.
#
# A custom app's id is its own. One the catalog has, or one any app has used on this NAS (a
# container, data or settings kept, a user), is refused, so a custom app never takes over
# another app's data, secrets or user. One the catalog adds later stays the owner's: its file
# comes first (app_manifest_path), and the Apps page doesn't list the catalog's.
#
# The web app asks for the owner's password again before it saves one (CustomAppsController):
# a page left open, or a stolen sign-in, can't add an app.
#
# Its logo is a picture the owner gives with it (PNG, JPEG, WebP or SVG), kept beside its file as
# APP_CUSTOM/<id>.<type> and served by the NAS itself (an SVG under a sandbox policy, so a script in
# one can't run), never a link: a logo in the file is ignored, so the Apps page loads nothing
# from elsewhere for an app of the owner's.
module AmahiHelper
  # Root's, read by the web app's group (APP_USER), to list them.
  APP_CUSTOM = '/var/lib/amahi-kai/custom-apps'
  APP_LOGO_TYPES = %w[png jpg webp svg].freeze
  APP_LOGO_MAX_BYTES = 256 * 1024

  add_operations(
    # Reads +manifest+ (YAML, an app file as the catalog's are written) and +logo+ as
    # apps.custom_save would, changing nothing: the web app's review page, before it asks for the
    # owner's password.
    'apps.custom_check' => {
      params: %w[app manifest logo],
      validate: ->(a) { custom_app_request(a) },
      plan: ->(v) { [[:custom_app_checked, v[:id]]] }
    },
    # Keeps +manifest+ as the custom app +app+, new or changed. A change reaches its container at
    # its next install or update, which the web app runs right after when the reply says
    # update: true. One its container doesn't see (its name, description, category, how to sign
    # in) needs none: it's recorded as what the container was made from too. Refused while a job
    # changes the app. +logo+ is its picture, base64 (an empty one removes it; left out, it's kept).
    'apps.custom_save' => {
      params: %w[app manifest logo],
      validate: ->(a) { custom_app_request(a).tap { |v| not_in_a_job!(v[:id]) } },
      plan: ->(v) { [[:custom_app_save, v[:id], v[:content], v[:logo_type], v[:logo]]] }
    },
    # Forgets a custom app that isn't installed and has no data kept: uninstall it, and delete
    # its data, first.
    'apps.custom_remove' => {
      params: %w[app],
      validate: ->(a) { custom_remove_request(a['app']) },
      plan: ->(v) { [[:custom_app_remove, v[:id]]] }
    },
  )

  class << self
    def custom_app_path(id)
      File.join(APP_CUSTOM, "#{id}.yml")
    end

    def custom_app?(id)
      File.file?(custom_app_path(id))
    end

    # { id:, content:, manifest:, logo_type:, logo: } for an app file (and logo) that passes every
    # check, else Refused with why not (the owner's own file: what's wrong is theirs to fix, not a
    # bug). logo_type is nil to keep the logo, 'none' to remove it.
    def custom_app_request(args)
      id = app_id(args['app'])
      content = args['manifest']
      raise Refused, 'the app file must be text' unless content.is_a?(String) && content.valid_encoding? && !content.include?("\0")
      raise Refused, "the app file is over #{CATALOG_MAX_BYTES / 1024} KB" if content.bytesize > CATALOG_MAX_BYTES
      logo_type = custom_logo_type(args['logo'])
      custom_id_free!(id)
      { id: id, content: content, manifest: custom_manifest(id, content), logo_type: logo_type, logo: args['logo'] }
    end

    # nil (keep it) when +value+ is left out, 'none' (remove it) when it's empty, else the type of
    # the picture it holds, in base64: a PNG, JPEG, WebP or SVG, up to APP_LOGO_MAX_BYTES.
    def custom_logo_type(value)
      return nil if value.nil?
      return 'none' if value == ''
      raise Refused, 'the logo must be a picture, in base64' unless value.is_a?(String) && value.match?(%r{\A[A-Za-z0-9+/]+={0,2}\z})

      bytes = value.unpack1('m0')
      raise Refused, "the logo is over #{APP_LOGO_MAX_BYTES / 1024} KB" if bytes.bytesize > APP_LOGO_MAX_BYTES

      logo_type(bytes) or raise Refused, "the logo isn't a PNG, JPEG, WebP or SVG picture"
    rescue ArgumentError
      raise Refused, 'the logo must be a picture, in base64'
    end

    # What a picture is, by its first bytes ('png', 'jpg', 'webp' or 'svg'), or nil.
    def logo_type(bytes)
      bytes = bytes.b
      return 'png' if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
      return 'jpg' if bytes.start_with?("\xFF\xD8\xFF".b)
      return 'webp' if bytes.bytesize > 12 && bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WEBP'

      'svg' if svg_picture?(bytes)
    end

    # An SVG: UTF-8 text whose first element is <svg>, after an XML declaration, comments and a
    # doctype at most, with no entities of its own (a doctype with a [ ] part). Whatever is in it,
    # it's served under a sandbox, and shown as a picture, where a browser runs no script.
    def svg_picture?(bytes)
      text = bytes.dup.force_encoding('UTF-8')
      return false unless text.valid_encoding? && !text.include?("\0")

      rest = text.delete_prefix("\uFEFF")
      loop do
        rest = rest.lstrip
        ending = { '<?xml' => '?>', '<!--' => '-->', '<!DOCTYPE' => '>' }.find { |start, _| rest.start_with?(start) }&.last
        break unless ending

        cut = rest.index(ending) or return false
        return false if rest.start_with?('<!DOCTYPE') && rest[0, cut].include?('[')

        rest = rest[(cut + ending.length)..]
      end
      rest.match?(%r{\A<svg[\s>/]})
    end

    def custom_logo_paths(id)
      APP_LOGO_TYPES.map { |type| File.join(APP_CUSTOM, "#{id}.#{type}") }
    end

    # The checks a catalog manifest gets, and one more: a custom app has to be installable now.
    def custom_manifest(id, content)
      data = YAML.safe_load(content)
      raise Refused, "it isn't an app file: that's a list of fields, as the catalog's are" unless data.is_a?(Hash)
      needs = manifest_requires(id, data)
      raise Refused, "it needs a newer Amahi-kai (requires: #{needs}): run System Update first" if needs > CATALOG_FORMAT
      check_listing(id, data)
      manifest = check_manifest(id, data)
      # The catalog takes no image that starts as root with folders on a pool (a setuid file it made
      # runs as root from the pool's snapshots: docs/security, Known gaps); nobody reviews these
      if manifest[:run_as] == 'image' && manifest[:folders].any? { |folder| folder[:kind] == :dataset }
        raise Refused, 'an app that starts as root (run_as: image) keeps its folders on the system disk, not a ZFS pool (kind: dataset)'
      end
      manifest
    rescue Failed => e
      raise Refused, e.message.delete_prefix("#{id}'s manifest: ")
    rescue Psych::Exception => e
      raise Refused, "it can't be read as YAML: #{e.message.lines.first.to_s.strip}"
    end

    # An id is the custom app's own when it's one already (a change), or nothing on this NAS has
    # had it: not the catalog, nor an app with a container, data, settings or a user kept.
    def custom_id_free!(id)
      return if custom_app?(id)
      raise Refused, "the Amahi-kai catalog has an app called #{id}: give yours another name" if catalog_has?(id)
      return unless app_id_used?(id)

      raise Refused, "an app called #{id} was installed on this NAS, and its data or settings are kept: give yours another name, " \
                     'or delete that app\'s data first'
    end

    def catalog_has?(id)
      [File.join(APP_CATALOG, 'apps', "#{id}.yml"), File.join(APP_MANIFESTS, "#{id}.yml")].any? { |path| File.file?(path) }
    end

    def app_id_used?(id)
      (engine_installed? && engine_container?(app_container(id))) ||
        ["#{APPS_ROOT}/#{id}", "#{APP_DEFINITIONS}/#{id}.json", "#{APP_SECRETS}/#{id}.json"].any? { |path| File.exist?(path) || File.symlink?(path) } ||
        !app_storage_pool(id).nil? || !passwd("app-#{id}").nil?
    end

    def custom_remove_request(value)
      id = app_id(value)
      raise Refused, "#{id} isn't an app of your own" unless custom_app?(id)
      not_in_a_job!(id)
      raise Refused, "#{id} is installed: uninstall it first" if engine_installed? && engine_container?(app_container(id))
      raise Refused, "#{id}'s data from an earlier install is kept: delete it first" if File.exist?("#{APPS_ROOT}/#{id}") || app_storage_pool(id)
      { id: id }
    end

    # Nothing to do once it's read: the review page goes on to ask for the owner's password.
    def do_custom_app_checked(id)
      { 'app' => id, 'checked' => true }
    end

    def do_custom_app_save(id, content, logo_type = nil, logo = nil)
      unless File.directory?(APP_CUSTOM)
        Dir.mkdir(APP_CUSTOM, 0o750)
        File.chown(0, group_id(APP_USER), APP_CUSTOM)
      end
      content = "#{content}\n" unless content.end_with?("\n")
      do_install(custom_app_path(id), content, nil, '0640', APP_USER)
      # Installed, and its container would be made the same: what it was made from is this file now
      definition = app_definition(id)
      manifest = custom_manifest(id, content).merge(source: YAML.safe_load(content))
      same = definition && app_container_fields(definition) == app_container_fields(manifest)
      app_record_definition(id, manifest) if same
      if logo_type
        keep = File.join(APP_CUSTOM, "#{id}.#{logo_type}")
        do_install(keep, logo.unpack1('m0'), nil, '0640', APP_USER) unless logo_type == 'none'
        FileUtils.rm_f(custom_logo_paths(id) - [keep])
      end
      { 'app' => id, 'saved' => true, 'update' => !definition.nil? && !same }
    end

    def do_custom_app_remove(id)
      FileUtils.rm_f([custom_app_path(id), *custom_logo_paths(id)])
      { 'app' => id, 'removed' => true }
    end
  end
end
