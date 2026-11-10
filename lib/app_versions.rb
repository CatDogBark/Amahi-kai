require 'ipaddr'
require 'json'
require 'net/http'
require 'socket'
require 'uri'
require 'yaml'

# Newer versions of the catalog's apps (config/apps), for script/app-versions. A person runs it,
# reads the release notes and opens a PR; nothing runs it on its own (docs/plans/apps.md, P4.5).
#
# A release counts when its tag has the pinned tag's shape (digits may change, nothing else):
# 2.5.5-rootless finds 2.5.6-rootless but not nightly-rootless or 2.5.6-slim-rootless. A tag
# that's been rebuilt (Jellyfin republishes 12.1) shows as a newer build of the same version.
class AppVersions
  CATALOG_DIR = File.expand_path('../config/apps', __dir__)

  # kind: :newer (another release), :rebuilt (the same tag, a newer build) or :current; error
  # when the registry couldn't be asked.
  Result = Struct.new(:id, :repo, :tag, :latest, :image, :kind, :notes, :major, :error, keyword_init: true)

  class << self
    # The pinned tag with its digits as wildcards.
    def shape(tag)
      Regexp.new("\\A#{Regexp.escape(tag).gsub(/\d+/, '\d+')}\\z")
    end

    def numbers(tag)
      tag.scan(/\d+/).map(&:to_i)
    end

    # The highest release of the same shape as +current+, if it's higher than +current+; with
    # +same_major+, only one whose first number is +current+'s (no new major version).
    def newest(current, tags, same_major: false)
      found = tags.grep(shape(current))
      found = found.select { |tag| numbers(tag).first == numbers(current).first } if same_major
      best = found.max_by { |tag| numbers(tag) }
      best if best && (numbers(best) <=> numbers(current)) == 1
    end

    def release_notes(template, tag)
      version = tag.to_s[/\A\d+(?:\.\d+)*/]
      template.sub('{version}', version) if template && version
    end

    # Writes +image+ as the manifest's image line, keeping everything else as it is.
    def write(path, image)
      text = File.read(path)
      raise ArgumentError, "#{path} has no image line" unless text.match?(/^image: \S+$/)
      File.write(path, text.sub(/^image: \S+$/, "image: #{image}"))
    end
  end

  # An image as an app file names it: name:tag, pinned or not (@sha256:digest), in the root
  # helper's spelling (its APP_IMAGE): lowercase names, a registry's host first when it isn't
  # Docker Hub, and no port.
  IMAGE = %r{\A(?<repo>[a-z0-9]+(?:[._/-][a-z0-9]+)*):(?<tag>[A-Za-z0-9._-]{1,64})(?:@(?<digest>sha256:\h{64}))?\z}

  # The registry says an image is private, or that it isn't there (it can't tell which). +place+
  # is where a token for it would be (RegistryTokens: its registry and its name's first part).
  class Private < RuntimeError
    attr_reader :place

    def initialize(place, message)
      @place = place
      super(message)
    end
  end

  # +registry+ answers for every image (tests); otherwise each image's own registry: Docker Hub,
  # GitHub's (ghcr.io), or any other by the registry API (Registry). +tokens+ (RegistryTokens, in
  # the web app) answers for an image under a place the owner keeps a token for: the root helper
  # asks its registry with the token.
  def initialize(registry: nil, dir: CATALOG_DIR, tokens: nil)
    @registry = registry
    @dir = dir
    @tokens = tokens
  end

  def registry_for(repo)
    return @registry if @registry
    return @tokens if @tokens&.for_repo(repo)

    host = repo.split('/').first
    if !repo.include?('/') || !host.include?('.') || host.match?(/\Adocker\.io\z/) then DockerHub.new
    elsif host == 'ghcr.io' then Ghcr.new
    else Registry.new(host)
    end
  end

  # +image+ (name:tag) pinned to the build its tag names now: name:tag@sha256:digest. One pinned
  # already is kept as it is (Docker checks the digest when it pulls it).
  def pin(image)
    match = image.to_s.match(IMAGE) or raise ArgumentError, "#{image} isn't name:tag (an image with its tag, like mealie-recipes/mealie:v2.4.1)"
    return image if match[:digest]

    "#{match[:repo]}:#{match[:tag]}@#{registry_for(match[:repo]).digest(match[:repo], match[:tag])}"
  end

  # A newer release of the image +image+ runs (name:tag@sha256:digest), as #check finds one:
  # Result with kind :newer or :rebuilt, or :current; with +same_major+, not a new major version
  # (a new install stays on the catalog's). Raises when the registry can't be asked.
  def check_image(image, releases: nil, id: nil, same_major: false)
    match = image.to_s.match(IMAGE)
    raise ArgumentError, 'its image is not name:tag@sha256:digest' unless match && match[:digest]

    repo, tag = match[:repo], match[:tag]
    registry = registry_for(repo)
    latest = self.class.newest(tag, registry.tags(repo), same_major: same_major)
    digest = registry.digest(repo, latest || tag)
    kind = if latest then :newer
           elsif digest != match[:digest] then :rebuilt
           else :current
           end
    shown = latest || tag
    Result.new(id: id, repo: repo, tag: tag, latest: shown, image: "#{repo}:#{shown}@#{digest}", kind: kind,
               notes: self.class.release_notes(releases, shown),
               major: latest ? self.class.numbers(latest).first != self.class.numbers(tag).first : false)
  end

  def ids
    Dir[File.join(@dir, '*.yml')].map { |path| File.basename(path, '.yml') }.sort
  end

  def path(id)
    File.join(@dir, "#{id}.yml")
  end

  def check(id)
    manifest = YAML.safe_load(File.read(path(id)))
    check_image(manifest['image'], releases: manifest['releases'], id: id)
  rescue StandardError => e
    match = manifest.is_a?(Hash) && manifest['image'].to_s.match(IMAGE)
    Result.new(id: id, repo: match && match[:repo], tag: match && match[:tag], error: e.message)
  end

  INDEX_TYPES = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json
                   application/vnd.oci.image.manifest.v1+json application/vnd.docker.distribution.manifest.v2+json].join(',')

  module Http
    private

    def request(url, method: :get, headers: {})
      response = answer(url, method: method, headers: headers)
      raise "#{URI(url).host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response
    end

    # The registry's answer, whatever it is (https only).
    def answer(url, method: :get, headers: {})
      uri = URI(url)
      raise "#{url} isn't https" unless uri.is_a?(URI::HTTPS)
      req = (method == :head ? Net::HTTP::Head : Net::HTTP::Get).new(uri)
      headers.each { |key, value| req[key] = value }
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(req) }
    end
  end

  # Docker Hub: recent tags from its API, a tag's digest (the multi-architecture image's, as
  # the manifests pin) from the registry.
  class DockerHub
    include Http
    PAGES = 5

    def tags(repo)
      url = "https://hub.docker.com/v2/repositories/#{full(repo)}/tags?page_size=100&ordering=last_updated"
      names = []
      PAGES.times do
        break unless url
        page = JSON.parse(request(url).body)
        names.concat(Array(page['results']).map { |t| t['name'] })
        url = page['next']
      end
      names
    end

    def digest(repo, tag)
      token = JSON.parse(request("https://auth.docker.io/token?service=registry.docker.io&scope=repository:#{full(repo)}:pull").body)['token']
      response = answer("https://registry-1.docker.io/v2/#{full(repo)}/manifests/#{tag}", method: :head,
                        headers: { 'Authorization' => "Bearer #{token}", 'Accept' => INDEX_TYPES })
      # Docker Hub says 401 for a repository it doesn't have, as for a private one
      raise Private.new("docker.io/#{full(repo).split('/').first}", "Docker Hub says #{repo} is private, or isn't there") if response.is_a?(Net::HTTPUnauthorized)
      raise "Docker Hub's #{repo} has no tag #{tag}" if response.is_a?(Net::HTTPNotFound)
      raise "registry-1.docker.io answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response['Docker-Content-Digest'] or raise "the registry gave no digest for #{repo}:#{tag}"
    end

    private

    def full(repo)
      repo = repo.sub(%r{\Adocker\.io/}, '')
      repo.include?('/') ? repo : "library/#{repo}"
    end
  end

  # GitHub's registry (ghcr.io), through the registry API with an anonymous token: it answers
  # for public packages (a private one says 401 or 403: Private).
  class Ghcr
    include Http

    def tags(repo)
      name = repo.delete_prefix('ghcr.io/')
      JSON.parse(request("https://ghcr.io/v2/#{name}/tags/list", headers: auth(name)).body)['tags'] || []
    end

    def digest(repo, tag)
      name = repo.delete_prefix('ghcr.io/')
      response = answer("https://ghcr.io/v2/#{name}/manifests/#{tag}", method: :head, headers: auth(name).merge('Accept' => INDEX_TYPES))
      # ghcr.io says 403 for a package it doesn't have, as for a private one
      raise private_image(name) if response.is_a?(Net::HTTPForbidden) || response.is_a?(Net::HTTPUnauthorized)
      raise "ghcr.io's #{name} has no tag #{tag}" if response.is_a?(Net::HTTPNotFound)
      raise "ghcr.io answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response['Docker-Content-Digest'] or raise "the registry gave no digest for #{repo}:#{tag}"
    end

    private

    def auth(name)
      token = JSON.parse(request("https://ghcr.io/token?scope=repository:#{name}:pull").body)['token']
      { 'Authorization' => "Bearer #{token}" }
    rescue RuntimeError => e
      raise e unless e.message.match?(/answered 40[13]\z/)
      raise private_image(name)
    end

    def private_image(name)
      Private.new("ghcr.io/#{name.split('/').first}", "ghcr.io says #{name} is private, or isn't there")
    end
  end

  # Any other registry (quay.io, lscr.io, codeberg.org, one of your own): the registry API (the
  # OCI distribution spec's), with the anonymous token it asks for (WWW-Authenticate: Bearer).
  # An image that needs a sign-in says so (Private): the owner's token for it goes through the
  # root helper instead (RegistryTokens). The registry, and where it sends for a
  # token, mustn't be the NAS itself or a link-local address (a cloud's metadata), so an image's
  # name can't be used to make Amahi-kai ask those.
  class Registry
    include Http
    PAGES = 10

    def initialize(host)
      @host = host
    end

    def tags(repo)
      name = path(repo)
      url = registry_url("/v2/#{name}/tags/list", 'n=1000')
      names = []
      PAGES.times do
        break unless url

        response = call(url, name)
        names.concat(Array(JSON.parse(response.body)['tags']).grep(String))
        url = next_page(response['Link'])
      end
      names
    end

    def digest(repo, tag)
      name = path(repo)
      response = call(registry_url("/v2/#{name}/manifests/#{tag}"), name, method: :head, headers: { 'Accept' => INDEX_TYPES })
      response['Docker-Content-Digest'] or raise "#{@host} gave no digest for #{repo}:#{tag}"
    end

    private

    def path(repo)
      repo.delete_prefix("#{@host}/")
    end

    def registry_url(path, query = nil)
      URI::HTTPS.build(host: @host, path: path, query: query).to_s
    end

    # The request, made again with a token when the registry asks for one.
    def call(url, name, method: :get, headers: {})
      reachable!(@host)
      response = answer(url, method: method, headers: headers.merge(@token ? { 'Authorization' => "Bearer #{@token}" } : {}))
      if response.is_a?(Net::HTTPUnauthorized) && !@token
        @token = token(response['WWW-Authenticate'], name)
        response = answer(url, method: method, headers: headers.merge('Authorization' => "Bearer #{@token}"))
      end
      raise private_image(name) if response.is_a?(Net::HTTPUnauthorized) || response.is_a?(Net::HTTPForbidden)
      raise "#{@host} has no #{name}, or not that tag" if response.is_a?(Net::HTTPNotFound)
      raise "#{@host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    # An anonymous pull token from the realm the registry names.
    def token(challenge, name)
      fields = challenge.to_s.sub(/\ABearer\s+/i, '').scan(/(\w+)="([^"]*)"/).to_h
      realm = URI(fields['realm'].to_s)
      raise "#{@host} asks for a sign-in Amahi-kai can't give" unless challenge.to_s.match?(/\ABearer\s/i) && realm.is_a?(URI::HTTPS)

      reachable!(realm.host)
      query = { 'service' => fields['service'], 'scope' => "repository:#{name}:pull" }.compact
      realm.query = [realm.query, URI.encode_www_form(query)].compact.join('&')
      response = answer(realm.to_s)
      raise private_image(name) if response.is_a?(Net::HTTPUnauthorized) || response.is_a?(Net::HTTPForbidden)
      raise "#{realm.host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body['token'] || body['access_token'] or raise "#{realm.host} gave no token"
    end

    def private_image(name)
      Private.new("#{@host}/#{name.split('/').first}", "#{@host} says #{name} is private, or isn't there")
    end

    # The next page of tags, from the Link header (on this registry only).
    def next_page(link)
      target = link.to_s[/<([^>]+)>;\s*rel="?next"?/, 1] or return nil
      url = URI.join(registry_url('/'), target)
      url.host == @host && url.is_a?(URI::HTTPS) ? url.to_s : nil
    end

    def reachable!(host)
      addresses = Addrinfo.getaddrinfo(host, 443, nil, :STREAM).map(&:ip_address)
      raise "#{host} can't be found" if addresses.empty?
      bad = addresses.map { |address| IPAddr.new(address) }.find { |ip| ip.loopback? || ip.link_local? || ip.to_s == '0.0.0.0' || ip.to_s == '::' }
      raise "#{host} is #{bad}, which Amahi-kai doesn't ask for images" if bad
    rescue SocketError
      raise "#{host} can't be found"
    end
  end
end
