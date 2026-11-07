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
module AmahiHelper
  # Root's, read by the web app's group (APP_USER), to list them.
  APP_CUSTOM = '/var/lib/amahi-kai/custom-apps'

  add_operations(
    # Reads +manifest+ (YAML, an app file as the catalog's are written) as apps.custom_save would,
    # changing nothing: the web app's review page, before it asks for the owner's password.
    'apps.custom_check' => {
      params: %w[app manifest],
      validate: ->(a) { custom_app_request(a) },
      plan: ->(v) { [[:custom_app_checked, v[:id]]] }
    },
    # Keeps +manifest+ as the custom app +app+, new or changed. A change reaches its container at
    # its next install or update, which the web app runs right after. Refused while a job changes
    # the app.
    'apps.custom_save' => {
      params: %w[app manifest],
      validate: ->(a) { custom_app_request(a).tap { |v| not_in_a_job!(v[:id]) } },
      plan: ->(v) { [[:custom_app_save, v[:id], v[:content]]] }
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

    # { id:, content:, manifest: } for an app file that passes every check, else Refused with why
    # not (the owner's own file: what's wrong is theirs to fix, not a bug).
    def custom_app_request(args)
      id = app_id(args['app'])
      content = args['manifest']
      raise Refused, 'the app file must be text' unless content.is_a?(String) && content.valid_encoding? && !content.include?("\0")
      raise Refused, "the app file is over #{CATALOG_MAX_BYTES / 1024} KB" if content.bytesize > CATALOG_MAX_BYTES
      custom_id_free!(id)
      { id: id, content: content, manifest: custom_manifest(id, content) }
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

    def do_custom_app_save(id, content)
      unless File.directory?(APP_CUSTOM)
        Dir.mkdir(APP_CUSTOM, 0o750)
        File.chown(0, group_id(APP_USER), APP_CUSTOM)
      end
      content = "#{content}\n" unless content.end_with?("\n")
      do_install(custom_app_path(id), content, nil, '0640', APP_USER)
      { 'app' => id, 'saved' => true }
    end

    def do_custom_app_remove(id)
      FileUtils.rm_f(custom_app_path(id))
      { 'app' => id, 'removed' => true }
    end
  end
end
