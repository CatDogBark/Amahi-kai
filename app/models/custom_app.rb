require 'etc'

# An app of the owner's own (docs/plans/apps.md, custom apps): its app file, written the way the
# catalog's are, made from the Add your own app form or pasted, and what the review page says
# about it. The root helper checks the file with the catalog's checks and keeps it (custom.rb);
# this only builds it, and puts it in words. Nothing here is trusted: the helper refuses what
# doesn't pass.
class CustomApp
  ID = AppCatalog::ID
  # The kernel capabilities an app may get back (the helper's APP_CAPABILITIES), as the form says
  # them, and the four linuxserver.io's images take, ticked first.
  CAPABILITIES = {
    'CHOWN' => 'Change who owns a file',
    'DAC_OVERRIDE' => 'Read and write past file permissions',
    'SETUID' => 'Switch to another user',
    'SETGID' => 'Switch to another group',
    'FOWNER' => "Change modes of files it doesn't own",
    'FSETID' => 'Keep setuid on files it changes',
    'KILL' => "Signal processes it doesn't own",
    'NET_BIND_SERVICE' => 'Listen on ports below 1024',
    'SETPCAP' => 'Change its own permissions',
    'SETFCAP' => 'Mark files with permissions',
    'SYS_CHROOT' => 'Change its root folder',
    'AUDIT_WRITE' => 'Write to the audit log'
  }.freeze
  LINUXSERVER_CAPABILITIES = %w[CHOWN DAC_OVERRIDE SETUID SETGID].freeze
  MEMORY = { '512m' => '512 MB', '1g' => '1 GB', '2g' => '2 GB', '4g' => '4 GB', '8g' => '8 GB' }.freeze
  CATEGORIES = %w[home media files downloads monitoring development security other].freeze
  # A setting's value: one typed, or what Amahi-kai fills in (the helper's APP_PLACEHOLDERS)
  SETTING_KINDS = { 'value' => 'A value', 'timezone' => "The NAS's time zone", 'uid' => "Its user's number",
                    'gid' => "Its group's number" }.freeze
  PLACEHOLDERS = { 'timezone' => '{{timezone}}', 'uid' => '{{uid}}', 'gid' => '{{gid}}' }.freeze
  # The fields the form writes; a file with others (access, web_tls, ping, a folder's kind, a
  # hashed secret...) is edited as a file. A logo link it has is no matter: the form leaves it
  # out, and an app of your own's logo is a picture kept on the NAS, never a link.
  FORM_FIELDS = %w[requires name description category sign_in image run_as capabilities network memory web_port ports folders
                   shares writes_shares environment secrets].freeze
  FORM_IGNORES = %w[logo].freeze
  # The order an app file made here has its fields in
  ORDER = %w[requires name description category sign_in logo releases image run_as capabilities network access memory web_port
             web_tls ports folders shares writes_shares environment secrets ping].freeze
  NEVER = "Another app, the NAS's own pages, files or SSH, or anything you didn't give it here".freeze

  attr_reader :id, :text, :data, :errors

  class << self
    # The id an app's name gives it: its letters and digits, lowercase, starting with a letter.
    def id_for(name)
      name.to_s.downcase.gsub(/[^a-z0-9]/, '').sub(/\A[0-9]+/, '')[0, 24]
    end

    # The form's fields (params[:app]) as an app file.
    def from_form(fields, id: nil)
      fields = fields.to_h.stringify_keys
      data = form_data(fields)
      new(id || id_for(fields['name']), dump(data), fields: fields)
    end

    # An app file as it was pasted, or saved.
    def from_file(text, id: nil)
      new(id, text.to_s.gsub("\r\n", "\n"))
    end

    def find(id)
      text = AppCatalog.custom_file(id) or return nil
      from_file(text, id: id)
    end

    # The fields in ORDER, then any others, as YAML.
    def dump(data)
      ordered = ORDER.filter_map { |key| [key, data[key]] if data.key?(key) }.to_h.merge(data.except(*ORDER))
      ordered.to_yaml.delete_prefix("---\n")
    end

    # A logo's type, as the pages show it (image/png...), by its first bytes, or nil. The helper
    # checks it again, fully (custom.rb).
    def logo_type(bytes)
      bytes = bytes.to_s.b
      if bytes.start_with?("\x89PNG\r\n\x1A\n".b) then 'image/png'
      elsif bytes.start_with?("\xFF\xD8\xFF".b) then 'image/jpeg'
      elsif bytes.bytesize > 12 && bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WEBP' then 'image/webp'
      elsif bytes.dup.force_encoding('UTF-8').then { |text| text.valid_encoding? && text.include?('<svg') } then 'image/svg+xml'
      end
    end

    # Processors an app may use, and the NAS's (the helper's app_cpus): all but one.
    def processors
      count = Etc.nprocessors
      count > 1 ? "#{count - 1} of the NAS's #{count} processors" : "the NAS's one processor"
    end

    private

    def form_data(fields)
      data = {}
      %w[name description category sign_in image].each do |key|
        value = fields[key].to_s.strip
        data[key] = value if value.present?
      end
      data['run_as'] = fields['run_as'] == 'image' ? 'image' : 'app'
      caps = Array(fields['capabilities']).map(&:to_s) & CAPABILITIES.keys
      data['capabilities'] = CAPABILITIES.keys & caps if data['run_as'] == 'image' && caps.any?
      data['network'] = fields['network'] if %w[lan none].include?(fields['network'])
      data['memory'] = fields['memory'].to_s if fields['memory'].to_s.match?(/\A[1-9][0-9]{0,4}[mg]\z/)
      ports, web = form_ports(fields)
      data['web_port'] = web if web
      data['ports'] = ports if ports.any?
      folders = rows(fields['folders']).filter_map do |row|
        { 'name' => row['name'].to_s.strip, 'path' => row['path'].to_s.strip } if row['name'].present? || row['path'].present?
      end
      data['folders'] = folders if folders.any?
      data['shares'] = true if fields['shares'] == '1' || fields['writes_shares'] == '1'
      data['writes_shares'] = true if fields['writes_shares'] == '1'
      environment = form_environment(fields)
      data['environment'] = environment if environment.any?
      secrets = rows(fields['secrets']).filter_map do |row|
        name = row['name'].to_s.strip
        { 'env' => name, 'label' => row['label'].to_s.strip.presence || name.tr('_', ' ').capitalize } if name.present?
      end
      data['secrets'] = secrets if secrets.any?
      # Names spelled as the app spells them (lowercase, dashes) need format 4
      data['requires'] = 4 if environment.keys.any? { |name| !name.match?(/\A[A-Z][A-Z0-9_]*\z/) }
      data
    end

    # [ports, web_port]: the rows given, numbers as numbers (what isn't one the helper refuses
    # by its own words), and the one marked as its web page.
    def form_ports(fields)
      web = nil
      ports = rows(fields['ports']).filter_map do |row|
        next if row['host'].blank? && row['container'].blank?

        port = { 'host' => number(row['host']), 'container' => number(row['container']) }
        port['protocol'] = 'udp' if row['protocol'] == 'udp'
        web ||= port['host'] if row['key'] == fields['web'].to_s && port['protocol'].nil?
        port
      end
      [ports, web]
    end

    def form_environment(fields)
      rows(fields['settings']).each_with_object({}) do |row, environment|
        name = row['name'].to_s.strip
        next if name.empty?

        environment[name] = PLACEHOLDERS.fetch(row['kind'].to_s) { row['value'].to_s }
      end
    end

    # A table's rows ({ key => { field => value } }, in order), each with its key.
    def rows(table)
      table = table.to_h if table.respond_to?(:to_h) && !table.is_a?(Array)
      return [] unless table.is_a?(Hash)

      table.map { |key, row| row.to_h.stringify_keys.merge('key' => key.to_s) if row.respond_to?(:to_h) }.compact
    end

    def number(value)
      value = value.to_s.strip
      value.match?(/\A[0-9]{1,5}\z/) ? value.to_i : value
    end
  end

  def initialize(id, text, fields: nil)
    @id = id.to_s
    @text = text
    @fields = fields
    @errors = {}
    begin
      @data = YAML.safe_load(text)
    rescue Psych::Exception => e
      @data = {}
      @errors[:file] = "It can't be read as YAML: #{e.message.lines.first.to_s.strip}"
    end
    @data = {} unless @data.is_a?(Hash)
    # A file pasted for a new app takes its id from its name, as the form does
    @id = self.class.id_for(@data['name']) if @id.empty?
    @errors[:file] ||= "It isn't an app file: that's a list of fields, as the catalog's are" if text.strip.present? && @data.empty?
    @errors[:file] ||= 'Paste the app file first' if text.strip.empty?
  end

  def name
    @data['name'].to_s.presence || @id
  end

  def image
    @data['image'].to_s
  end

  # The app file with +pinned+ as its image (name:tag@sha256:digest): only the image line
  # changes in a file as it was pasted.
  def pin(pinned)
    line = /^image:[ \t]*["']?#{Regexp.escape(image)}["']?[ \t]*$/
    @text = @text.match?(line) ? @text.sub(line, "image: #{pinned}") : self.class.dump(@data.merge('image' => pinned))
    @data['image'] = pinned
    self
  end

  # The form's fields for this file (posted, or read back from it), or nil when the file says
  # more than the form shows: it's edited as a file then.
  def form
    return @fields if @fields
    return nil unless (@data.keys - FORM_FIELDS - FORM_IGNORES).empty?
    return nil if Array(@data['folders']).any? { |folder| !folder.is_a?(Hash) || (folder.keys - %w[name path]).any? }
    return nil if Array(@data['secrets']).any? { |secret| !secret.is_a?(Hash) || (secret.keys - %w[env label]).any? }
    return nil unless @data['environment'].nil? || @data['environment'].is_a?(Hash)

    form_fields
  end

  # [[label, words]] for the review page: what it will be able to do.
  def facts
    [['Runs', runs_words], ['Image', image], ['Reaches', AppCatalog.network_words(@data['network'])],
     ['Reached at', reached_words], ['Keeps', folder_words], ['Your shares', share_words],
     ['Settings', setting_words], ['Limits', "Up to #{memory_words} of memory, and #{self.class.processors}"],
     ['Never', NEVER]]
  end

  # name:tag, and the digest it's pinned to, shortened
  def image_parts
    repo_tag, digest = image.split('@', 2)
    [repo_tag, digest && "#{digest.delete_prefix('sha256:')[0, 4]}…#{digest[-4, 4]}"]
  end

  def capabilities
    Array(@data['capabilities']).map(&:to_s)
  end

  private

  def form_fields
    environment = Hash(@data['environment'])
    { 'name' => @data['name'], 'description' => @data['description'], 'category' => @data['category'],
      'sign_in' => @data['sign_in'], 'image' => image.sub(/@.*/, ''), 'run_as' => @data['run_as'] == 'image' ? 'image' : 'app',
      'capabilities' => capabilities, 'network' => @data['network'] || 'internet', 'memory' => (@data['memory'] || '1g').to_s,
      'web' => Array(@data['ports']).index { |port| port.is_a?(Hash) && port['host'] == @data['web_port'] }.to_s,
      'ports' => Array(@data['ports']).each_with_index.to_h do |port, index|
        [index.to_s, { 'host' => port['host'], 'container' => port['container'], 'protocol' => port['protocol'] || 'tcp' }]
      end,
      'folders' => Array(@data['folders']).each_with_index.to_h { |folder, index| [index.to_s, folder.slice('name', 'path')] },
      'settings' => environment.each_with_index.to_h do |(name, value), index|
        kind = PLACEHOLDERS.key(value.to_s) || 'value'
        [index.to_s, { 'name' => name, 'kind' => kind, 'value' => kind == 'value' ? value : '' }]
      end,
      'secrets' => Array(@data['secrets']).each_with_index.to_h { |secret, index| [index.to_s, { 'name' => secret['env'], 'label' => secret['label'] }] },
      'shares' => @data['shares'] == true || @data['writes_shares'] == true ? '1' : nil,
      'writes_shares' => @data['writes_shares'] == true ? '1' : nil }
  end

  def runs_words
    given = capabilities.empty? ? 'with no kernel permissions' : "with these kernel permissions: #{capabilities.join(', ')}"
    if @data['run_as'] == 'image'
      "As the image says (often root, switching to its own user), #{given}"
    else
      "As its own user, #{given}"
    end
  end

  def reached_words
    ports = Array(@data['ports']).select { |port| port.is_a?(Hash) }
    return 'Nothing: it has no ports' if ports.empty?

    list = ports.map do |port|
      words = "#{port['host']}#{'/udp' if port['protocol'] == 'udp'}"
      port['host'] == @data['web_port'] ? "#{words} (its web page)" : words
    end
    who = @data['access'] == 'tailscale' ? 'from devices on your tailnet only' : 'from your network and Tailscale only'
    "#{ports.one? ? 'Port' : 'Ports'} #{list.to_sentence}, #{who}"
  end

  def folder_words
    folders = Array(@data['folders']).select { |folder| folder.is_a?(Hash) }
    return 'No folders: what it writes is lost when its container is made again' if folders.empty?

    list = folders.map { |folder| "#{folder['name']} (in the app at #{folder['path']})" }
    where = folders.any? { |folder| folder['kind'] == 'dataset' } ? 'on the system disk, or a ZFS pool' : 'on the system disk'
    "#{folders.one? ? 'One folder' : "#{folders.size} folders"}, #{list.to_sentence}, #{where}"
  end

  def share_words
    if @data['writes_shares'] == true
      'The ones you choose at install, read only unless you let it write in them'
    elsif @data['shares'] == true
      'The ones you choose at install, read only'
    else
      "None: it doesn't work with files in shares"
    end
  end

  def setting_words
    settings = Hash(@data['environment']).size
    secrets = Array(@data['secrets']).size
    return 'None' if settings.zero? && secrets.zero?

    parts = []
    parts << "#{settings} #{settings == 1 ? 'setting' : 'settings'}" if settings.positive?
    parts << "#{secrets} #{secrets == 1 ? 'secret' : 'secrets'} Amahi-kai makes and shows you on its page" if secrets.positive?
    parts.join(', and ')
  end

  def memory_words
    memory = (@data['memory'] || '1g').to_s
    MEMORY[memory] || memory.sub(/m\z/, ' MB').sub(/g\z/, ' GB')
  end
end
