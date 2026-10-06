require 'json'
require 'net/http'
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

    # The highest release of the same shape as +current+, if it's higher than +current+.
    def newest(current, tags)
      best = tags.grep(shape(current)).max_by { |tag| numbers(tag) }
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

  # +registry+ answers for every image (tests); otherwise each image's own registry: Docker Hub,
  # or GitHub's (ghcr.io).
  def initialize(registry: nil, dir: CATALOG_DIR)
    @registry = registry
    @dir = dir
  end

  def registry_for(repo)
    @registry || (repo.start_with?('ghcr.io/') ? Ghcr.new : DockerHub.new)
  end

  def ids
    Dir[File.join(@dir, '*.yml')].map { |path| File.basename(path, '.yml') }.sort
  end

  def path(id)
    File.join(@dir, "#{id}.yml")
  end

  def check(id)
    manifest = YAML.safe_load(File.read(path(id)))
    match = manifest['image'].to_s.match(/\A(?<repo>[^:@]+):(?<tag>[^@]+)@(?<digest>sha256:\h{64})\z/)
    return Result.new(id: id, error: 'its image is not name:tag@sha256:digest') unless match

    repo, tag = match[:repo], match[:tag]
    registry = registry_for(repo)
    latest = self.class.newest(tag, registry.tags(repo))
    digest = registry.digest(repo, latest || tag)
    kind = if latest then :newer
           elsif digest != match[:digest] then :rebuilt
           else :current
           end
    shown = latest || tag
    Result.new(id: id, repo: repo, tag: tag, latest: shown, image: "#{repo}:#{shown}@#{digest}", kind: kind,
               notes: self.class.release_notes(manifest['releases'], shown),
               major: latest ? self.class.numbers(latest).first != self.class.numbers(tag).first : false)
  rescue StandardError => e
    Result.new(id: id, repo: repo, tag: tag, error: e.message)
  end

  INDEX_TYPES = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json
                   application/vnd.oci.image.manifest.v1+json application/vnd.docker.distribution.manifest.v2+json].join(',')

  module Http
    private

    def request(url, method: :get, headers: {})
      uri = URI(url)
      req = (method == :head ? Net::HTTP::Head : Net::HTTP::Get).new(uri)
      headers.each { |key, value| req[key] = value }
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(req) }
      raise "#{uri.host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response
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
      response = request("https://registry-1.docker.io/v2/#{full(repo)}/manifests/#{tag}", method: :head,
                         headers: { 'Authorization' => "Bearer #{token}", 'Accept' => INDEX_TYPES })
      response['Docker-Content-Digest'] or raise "the registry gave no digest for #{repo}:#{tag}"
    end

    private

    def full(repo)
      repo.include?('/') ? repo : "library/#{repo}"
    end
  end

  # GitHub's registry (ghcr.io), through the registry API with an anonymous token: it answers
  # for public packages (a private one says 401).
  class Ghcr
    include Http

    def tags(repo)
      name = repo.delete_prefix('ghcr.io/')
      JSON.parse(request("https://ghcr.io/v2/#{name}/tags/list", headers: auth(name)).body)['tags'] || []
    end

    def digest(repo, tag)
      name = repo.delete_prefix('ghcr.io/')
      response = request("https://ghcr.io/v2/#{name}/manifests/#{tag}", method: :head, headers: auth(name).merge('Accept' => INDEX_TYPES))
      response['Docker-Content-Digest'] or raise "the registry gave no digest for #{repo}:#{tag}"
    end

    private

    def auth(name)
      token = JSON.parse(request("https://ghcr.io/token?scope=repository:#{name}:pull").body)['token']
      { 'Authorization' => "Bearer #{token}" }
    rescue RuntimeError => e
      raise e unless e.message.include?('401')
      raise "the package is private on ghcr.io (it must be public for a NAS to pull it)"
    end
  end
end
