# frozen_string_literal: true

# Part of amahi-helper (libexec/amahi-helper): tokens for private images.
#
# An image its owner keeps private downloads only with a token from its registry. The owner adds
# one on Private images (PrivateImagesController) for a place: a registry and whose images there
# (ghcr.io/catdogbark). The token is kept in REGISTRY_TOKENS, which only root can read, and is
# never handed back; what the pages show (who it signs in as, when it last worked) is in
# REGISTRY_STATUS, which the app reads. Only this helper uses it, only for images under its
# place, and only with that registry: Docker gets it in a config of its own for one pull
# (engine_pull, registry_signed_in), and the lookups the web app needs for those images (a tag's
# digest, the tags) are made here (registry.digest, registry.tags), so the web app never holds
# it. Apps never see it.

module AmahiHelper
  REGISTRY_TOKENS = '/etc/amahi-kai/registry-tokens.json'
  REGISTRY_STATUS = '/var/lib/amahi-kai/registry-tokens.json'
  REGISTRY_MAX = 20
  # A registry, by its host name: lowercase, with a dot, and no port (an image's name has none:
  # APP_IMAGE)
  REGISTRY_HOST = /\A(?=.{4,253}\z)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/
  # Whose images: the first parts of an image's name there, spelled as APP_IMAGE spells them
  REGISTRY_OWNER = %r{\A(?=.{1,200}\z)[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*\z}
  # An image's name without its tag (AppVersions' IMAGE repo), and a tag
  REGISTRY_REPO = %r{\A(?=.{1,255}\z)[a-z0-9]+(?:[._/-][a-z0-9]+)*\z}
  REGISTRY_TAG = /\A[A-Za-z0-9_][A-Za-z0-9._-]{0,127}\z/
  # Who it signs in as: printable, no space, and no colon (the sign-in is user:token)
  REGISTRY_USERNAME = /\A[\x21-\x39\x3b-\x7e]{1,100}\z/
  REGISTRY_TOKEN = /\A[\x21-\x7e]{8,1024}\z/
  # Docker Hub's other names; where its registry API answers; and Docker's name for it in a config
  REGISTRY_ALIASES = { 'index.docker.io' => 'docker.io', 'registry-1.docker.io' => 'docker.io', 'registry.hub.docker.com' => 'docker.io' }.freeze
  REGISTRY_API = { 'docker.io' => 'registry-1.docker.io' }.freeze
  REGISTRY_DOCKER_KEY = { 'docker.io' => 'https://index.docker.io/v1/' }.freeze
  REGISTRY_INDEX_TYPES = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json
                            application/vnd.oci.image.manifest.v1+json application/vnd.docker.distribution.manifest.v2+json].join(',')
  REGISTRY_TAG_PAGES = 10

  # The registry wouldn't take the token (401 or 403): it's wrong, expired, deleted, or can't
  # read that image.
  class RegistryRefused < Failed; end

  add_operations(
    # Adds a token for a place, or replaces the one it has, once the registry takes it.
    'registry.save' => {
      params: %w[host owner username token note],
      validate: lambda { |a|
        host = registry_host(a['host'])
        { place: "#{host}/#{registry_owner(a['owner'])}", username: registry_username(a['username']),
          token: registry_token(a['token']), note: registry_note(a['note']) }
      },
      plan: ->(v) { [[:registry_save, v[:place], v[:username], v[:token], v[:note]]] }
    },
    # Signs in with a place's token again, and says whether the registry took it.
    'registry.check' => {
      params: %w[place],
      validate: ->(a) { { place: registry_place(a['place']) } },
      plan: ->(v) { [[:registry_check, v[:place]]] }
    },
    'registry.remove' => {
      params: %w[place],
      validate: ->(a) { { place: registry_place(a['place']) } },
      plan: ->(v) { [[:registry_remove, v[:place]]] }
    },
    # A tag's digest, and an image's tags, for an image under a place with a token (AppVersions:
    # Review's pin, Check for a newer version).
    'registry.digest' => {
      params: %w[repo tag],
      validate: ->(a) { { repo: registry_repo(a['repo']), tag: registry_tag(a['tag']) } },
      plan: ->(v) { [[:registry_digest, v[:repo], v[:tag]]] }
    },
    'registry.tags' => {
      params: %w[repo],
      validate: ->(a) { { repo: registry_repo(a['repo']) } },
      plan: ->(v) { [[:registry_tags, v[:repo]]] }
    }
  )

  class << self
    def registry_host(value)
      host = string(value, 'the registry', max: 253)
      host = REGISTRY_ALIASES.fetch(host, host)
      raise Refused, "the registry #{host.inspect} must be a host name, like ghcr.io" unless host.match?(REGISTRY_HOST)
      raise Refused, "#{host} is the NAS itself" if host == 'localhost' || host.end_with?('.localhost')

      host
    end

    def registry_owner(value)
      owner = string(value, 'whose images', max: 200)
      raise Refused, "whose images #{owner.inspect} must be lowercase names, like catdogbark" unless owner.match?(REGISTRY_OWNER)

      owner
    end

    def registry_username(value)
      name = string(value, 'who it signs in as', max: 100)
      raise Refused, 'who it signs in as must be one word, with no colon' unless name.match?(REGISTRY_USERNAME)

      name
    end

    def registry_token(value)
      token = string(value, 'the token', max: 1024)
      raise Refused, 'the token must be 8 to 1024 characters, with no spaces' unless token.match?(REGISTRY_TOKEN)

      token
    end

    # A note to tell a token apart, or nil
    def registry_note(value)
      return nil if value.nil? || value == ''

      note = string(value, 'the note', max: 120)
      raise Refused, 'the note must be one line' if note.match?(/[[:cntrl:]  ]/)

      note
    end

    # A place with a token
    def registry_place(value)
      place = string(value, 'the place', max: 460)
      raise Refused, "there's no token for #{place}" unless registry_tokens.key?(place)

      place
    end

    # An image's name, under a place with a token
    def registry_repo(value)
      repo = string(value, 'the image', max: 255)
      raise Refused, "the image #{repo.inspect} must be its name without its tag" unless repo.match?(REGISTRY_REPO) && !repo.include?('..')
      raise Refused, "there's no token for #{repo}" unless registry_place_for(repo)

      repo
    end

    def registry_tag(value)
      tag = string(value, 'the tag', max: 128)
      raise Refused, "the tag #{tag.inspect} must be letters, digits, . _ or -" unless tag.match?(REGISTRY_TAG)

      tag
    end

    # [registry, name there] for an image's name as an app file gives it: Docker Hub's when its
    # first part isn't a host (with library/ for its own images)
    def registry_split(repo)
      first, rest = repo.split('/', 2)
      host, path = rest && first.include?('.') ? [REGISTRY_ALIASES.fetch(first, first), rest] : ['docker.io', repo]
      path = "library/#{path}" if host == 'docker.io' && !path.include?('/')
      [host, path]
    end

    # The place whose token is for +repo+ (the longest that holds it), or nil
    def registry_place_for(repo)
      host, path = registry_split(repo)
      full = "#{host}/#{path}"
      registry_tokens.keys.select { |place| full.start_with?("#{place}/") }.max_by(&:length)
    end

    # { place => { 'username', 'token' } }
    def registry_tokens
      data = read_json(REGISTRY_TOKENS)
      data.is_a?(Hash) && data['tokens'].is_a?(Hash) ? data['tokens'] : {}
    end

    # [{ 'place', 'username', 'note', 'added_at', 'checked_at', 'worked', 'error' }], in the order added
    def registry_status
      data = read_json(REGISTRY_STATUS)
      data.is_a?(Hash) && data['tokens'].is_a?(Array) ? data['tokens'].grep(Hash) : []
    end

    # The token file and the status, read, changed by the block (given both) and written back,
    # one change at a time
    def registry_change
      File.open("#{REGISTRY_TOKENS}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        tokens = registry_tokens
        status = registry_status
        yield tokens, status
        do_install(REGISTRY_TOKENS, "#{JSON.pretty_generate('tokens' => tokens)}\n", nil, '0600')
        do_install(REGISTRY_STATUS, "#{JSON.pretty_generate('tokens' => status)}\n", nil, '0640', APP_USER)
      end
    end

    # What a sign-in, a lookup or a pull with a place's token found: it worked, or was refused
    # (+error+). Other failures (the registry unreachable, an image that isn't there) say nothing
    # about the token, and aren't recorded.
    def registry_record(place, worked, error = nil)
      registry_change do |tokens, status|
        entry = status.find { |row| row['place'] == place }
        next unless entry && tokens.key?(place)

        entry.merge!('checked_at' => Time.now.utc.iso8601, 'worked' => worked, 'error' => error)
      end
    end

    def do_registry_save(place, username, token, note)
      host = place.split('/').first
      exists = registry_tokens.key?(place)
      raise Failed, "the NAS has #{REGISTRY_MAX} tokens already: remove one first" if !exists && registry_tokens.size >= REGISTRY_MAX

      registry_sign_in(host, username, token)
      Dir.mkdir(File.dirname(REGISTRY_TOKENS), 0o755) unless File.directory?(File.dirname(REGISTRY_TOKENS))
      now = Time.now.utc.iso8601
      registry_change do |tokens, status|
        tokens[place] = { 'username' => username, 'token' => token }
        status.reject! { |row| row['place'] == place }
        status << { 'place' => place, 'username' => username, 'note' => note, 'added_at' => now, 'checked_at' => now, 'worked' => true,
                    'error' => nil }
      end
      { 'place' => place, 'saved' => true, 'replaced' => exists }
    end

    def do_registry_check(place)
      entry = registry_tokens.fetch(place)
      registry_sign_in(place.split('/').first, entry['username'], entry['token'])
      registry_record(place, true)
      { 'place' => place, 'worked' => true }
    rescue RegistryRefused => e
      registry_record(place, false, e.message)
      { 'place' => place, 'worked' => false, 'error' => e.message }
    end

    def do_registry_remove(place)
      registry_change do |tokens, status|
        tokens.delete(place)
        status.reject! { |row| row['place'] == place }
      end
      { 'place' => place, 'removed' => true }
    end

    def do_registry_digest(repo, tag)
      registry_with_token(repo) do |host, path, authorization|
        response = registry_answer(registry_uri(host, "/v2/#{path}/manifests/#{tag}"), method: :head,
                                                                                        headers: { 'Authorization' => authorization, 'Accept' => REGISTRY_INDEX_TYPES })
        registry_refused!(host, path, response)
        raise Failed, "#{host} has no #{path}:#{tag}" if response.is_a?(Net::HTTPNotFound)
        raise Failed, "#{host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        digest = response['Docker-Content-Digest'].to_s
        raise Failed, "#{host} gave no digest for #{path}:#{tag}" unless digest.match?(/\Asha256:\h{64}\z/)

        { 'digest' => digest }
      end
    end

    def do_registry_tags(repo)
      registry_with_token(repo) do |host, path, authorization|
        uri = registry_uri(host, "/v2/#{path}/tags/list", 'n=1000')
        names = []
        REGISTRY_TAG_PAGES.times do
          break unless uri

          response = registry_answer(uri, headers: { 'Authorization' => authorization })
          registry_refused!(host, path, response)
          raise Failed, "#{host} has no #{path}" if response.is_a?(Net::HTTPNotFound)
          raise Failed, "#{host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          names.concat(Array(JSON.parse(response.body)['tags']).grep(String).grep(REGISTRY_TAG))
          uri = registry_next_page(uri, response['Link'])
        end
        { 'tags' => names }
      rescue JSON::ParserError
        raise Failed, "#{host} gave tags that aren't JSON"
      end
    end

    # Runs the block with [host, name there, Authorization] for +repo+ signed in with its place's
    # token, and records whether the registry took it.
    def registry_with_token(repo)
      place = registry_place_for(repo) or raise Refused, "there's no token for #{repo}"
      entry = registry_tokens.fetch(place)
      host, path = registry_split(repo)
      authorization = registry_authorization(host, entry['username'], entry['token'], "repository:#{path}:pull")
      result = yield host, path, authorization
      registry_record(place, true)
      result
    rescue RegistryRefused => e
      registry_record(place, false, e.message) if place
      raise
    end

    # Docker signed in for one pull of +image+, when a place's token is for it: the block gets a
    # config folder (root's alone, made for this pull and removed after) holding only that sign-in;
    # nil for any other image, which downloads without signing in.
    def registry_signed_in(image)
      repo = image.sub(/@.*\z/, '').sub(/:[^:\/]+\z/, '')
      place = registry_place_for(repo)
      return yield(nil) unless place

      entry = registry_tokens.fetch(place)
      host = place.split('/').first
      Dir.mktmpdir('amahi-registry-') do |dir|
        auth = { REGISTRY_DOCKER_KEY.fetch(host, host) => { 'auth' => ["#{entry['username']}:#{entry['token']}"].pack('m0') } }
        File.open(File.join(dir, 'config.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.generate('auths' => auth)) }
        result = yield dir
        registry_record(place, true)
        result
      end
    rescue Failed => e
      registry_record(place, false, "#{host} refused the token when #{repo} was downloaded") if place && e.message.match?(/unauthorized|denied|authentication required/i)
      raise
    end

    # The registry takes the token: a sign-in with no image named, as `docker login` makes.
    def registry_sign_in(host, username, token)
      authorization = registry_authorization(host, username, token, nil)
      return if authorization.start_with?('Bearer ')

      response = registry_answer(registry_uri(host, '/v2/'), headers: { 'Authorization' => authorization })
      raise RegistryRefused, "#{host} refused the token" if response.is_a?(Net::HTTPUnauthorized) || response.is_a?(Net::HTTPForbidden)
      raise Failed, "#{host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    end

    # The Authorization header for a request to +host+'s registry API, signed in with the token:
    # a bearer token from the realm its challenge names (WWW-Authenticate), for +scope+ (nil: none),
    # or the sign-in itself (Basic) when that's what it asks for. The realm must be https and the
    # registry itself or in its domain (auth.docker.io for Docker Hub), so the token goes only there.
    def registry_authorization(host, username, token, scope)
      basic = "Basic #{["#{username}:#{token}"].pack('m0')}"
      probe = registry_answer(registry_uri(host, '/v2/'))
      challenge = probe['WWW-Authenticate'].to_s
      return basic if probe.is_a?(Net::HTTPSuccess) || challenge.match?(/\ABasic\b/i)
      raise Failed, "#{host} answered #{probe.code} for its registry" unless probe.is_a?(Net::HTTPUnauthorized) && challenge.match?(/\ABearer\s/i)

      fields = challenge.sub(/\ABearer\s+/i, '').scan(/(\w+)="([^"]*)"/).to_h
      realm = URI(fields['realm'].to_s)
      api = REGISTRY_API.fetch(host, host)
      raise Failed, "#{host} sends sign-ins to #{fields['realm'].inspect}, which isn't https" unless realm.is_a?(URI::HTTPS) && realm.host
      raise Failed, "#{host} sends sign-ins to #{realm.host}, outside its own domain" unless registry_same_domain?(api, realm.host)

      query = { 'service' => fields['service'], 'scope' => scope }.compact
      realm.query = [realm.query, URI.encode_www_form(query)].compact.reject(&:empty?).join('&')
      response = registry_answer(realm, headers: { 'Authorization' => basic })
      raise RegistryRefused, "#{host} refused the token" if response.is_a?(Net::HTTPUnauthorized) || response.is_a?(Net::HTTPForbidden)
      raise Failed, "#{realm.host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      bearer = body['token'] || body['access_token'] if body.is_a?(Hash)
      raise Failed, "#{realm.host} gave no token" unless bearer.is_a?(String) && !bearer.empty?

      "Bearer #{bearer}"
    rescue JSON::ParserError
      raise Failed, "#{realm&.host || host} gave a token that isn't JSON"
    rescue URI::InvalidURIError
      raise Failed, "#{host} sends sign-ins to an address that isn't one"
    end

    # The image's registry refused the token for it
    def registry_refused!(host, path, response)
      return unless response.is_a?(Net::HTTPUnauthorized) || response.is_a?(Net::HTTPForbidden)

      raise RegistryRefused, "#{host} refused the token for #{path}: it can't read that image"
    end

    # +realm+ is +api+ or in its domain: the same name, or one under what +api+ is under (its name
    # without its first part, when it has three or more)
    def registry_same_domain?(api, realm)
      parts = api.split('.')
      parent = parts.size > 2 ? parts.drop(1).join('.') : api
      realm == api || realm == parent || realm.end_with?(".#{parent}")
    end

    def registry_uri(host, path, query = nil)
      URI::HTTPS.build(host: REGISTRY_API.fetch(host, host), path: path, query: query)
    end

    # The next page of tags, from the Link header, on the same registry
    def registry_next_page(uri, link)
      target = link.to_s[/<([^>]+)>;\s*rel="?next"?/, 1] or return nil
      following = URI.join(uri, target)
      following.is_a?(URI::HTTPS) && following.host == uri.host ? following : nil
    rescue URI::InvalidURIError
      nil
    end

    # An https request to a registry, which mustn't be the NAS itself or a link-local address
    def registry_answer(uri, method: :get, headers: {})
      registry_reachable!(uri.host)
      request = (method == :head ? Net::HTTP::Head : Net::HTTP::Get).new(uri)
      headers.each { |key, value| request[key] = value }
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(request) }
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError => e
      raise Failed, "couldn't reach #{uri.host}: #{e.message}"
    end

    def registry_reachable!(host)
      addresses = Addrinfo.getaddrinfo(host, 443, nil, :STREAM).map(&:ip_address)
      raise Failed, "#{host} can't be found" if addresses.empty?

      bad = addresses.map { |address| IPAddr.new(address) }.find { |ip| ip.loopback? || ip.link_local? || ip.to_s == '0.0.0.0' || ip.to_s == '::' }
      raise Failed, "#{host} is #{bad}, which Amahi-kai doesn't sign in to" if bad
    rescue SocketError
      raise Failed, "#{host} can't be found"
    end
  end
end
