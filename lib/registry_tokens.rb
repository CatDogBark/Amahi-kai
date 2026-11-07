require 'json'

# Tokens for private images (the root helper's registry.rb), as the pages show them: the status
# the helper writes (REGISTRY_STATUS), never a token itself. Adding, checking and removing one,
# and the lookups for an image under a token's place (a tag's digest, the tags: AppVersions takes
# this as the registry for those), are helper calls, so the web app never holds a token.
module RegistryTokens
  STATUS = '/var/lib/amahi-kai/registry-tokens.json'.freeze
  # Docker Hub, by the name images give it: in a list, as a quoted docker.* reads to a spec as one of
  # the root helper's operations (privileged_spec)
  DOCKER_HUB = %w[docker.io].first.freeze
  NAMES = { 'ghcr.io' => "GitHub's registry", DOCKER_HUB => 'Docker Hub' }.freeze
  ALIASES = %w[index.docker.io registry-1.docker.io registry.hub.docker.com].to_h { |name| [name, DOCKER_HUB] }.freeze

  # One token as the helper records it. worked: whether the registry took it the last time it
  # was used (checked_at), with its error when it didn't.
  Token = Data.define(:place, :username, :note, :added_at, :checked_at, :worked, :error) do
    def host
      place.split('/').first
    end

    def owner
      place.split('/', 2).last
    end

    def registry_name
      NAMES[host] || host
    end

    def refused?
      worked == false
    end

    # Whether +image+ (name:tag, pinned or not) is one of its images
    def holds?(image)
      RegistryTokens.full_name(image).start_with?("#{place}/")
    end
  end

  class << self
    def status_file
      STATUS
    end

    # The tokens, in the order they were added
    def all
      data = JSON.parse(File.read(status_file))
      rows = data.is_a?(Hash) ? Array(data['tokens']).grep(Hash) : []
      rows.filter_map do |row|
        next unless row['place'].is_a?(String)

        Token.new(place: row['place'], username: row['username'].to_s, note: row['note'].presence, added_at: time(row['added_at']),
                  checked_at: time(row['checked_at']), worked: row['worked'], error: row['error'].presence)
      end
    rescue SystemCallError, JSON::ParserError
      []
    end

    def find(place)
      all.find { |token| token.place == place }
    end

    # The token whose place holds +image+ (the longest), or nil
    def for_image(image)
      all.select { |token| token.holds?(image) }.max_by { |token| token.place.length }
    end
    alias for_repo for_image

    # An image's name as Docker spells it in full, without its tag: registry/owner/name, with
    # Docker Hub's for one that names no registry (and library/ for its own images)
    def full_name(image)
      repo = image.to_s.sub(/@.*\z/, '').sub(%r{:[^:/]+\z}, '')
      first, rest = repo.split('/', 2)
      host, path = rest && first.include?('.') ? [ALIASES.fetch(first, first), rest] : [DOCKER_HUB, repo]
      path = "library/#{path}" if host == DOCKER_HUB && !path.include?('/')
      "#{host}/#{path}"
    end

    # The place a token for +image+ would have: its registry and the first part of its name
    # (ghcr.io/catdogbark for ghcr.io/catdogbark/bitstream)
    def place_for(image)
      host, owner = full_name(image).split('/', 3)
      "#{host}/#{owner}"
    end

    # Installed apps (DockerApp) whose images are +token+'s
    def apps_using(token, apps = DockerApp.all)
      apps.select { |app| app.image.present? && token.holds?(app.image) }
    end

    def save(host:, owner:, username:, token:, note:)
      Privileged.call('registry.save', host: host, owner: owner, username: username, token: token, note: note)
    end

    def check(place)
      Privileged.call('registry.check', place: place)
    end

    def remove(place)
      Privileged.call('registry.remove', place: place)
    end

    # The registry AppVersions asks for an image under a token's place
    def digest(repo, tag)
      Privileged.call('registry.digest', repo: repo, tag: tag)['digest']
    end

    def tags(repo)
      Array(Privileged.call('registry.tags', repo: repo)['tags'])
    end

    private

    def time(value)
      Time.iso8601(value) if value.is_a?(String)
    rescue ArgumentError
      nil
    end
  end
end
