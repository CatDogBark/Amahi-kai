# Amahi-kai
# Ubuntu 24.04, Ruby 3.2, Rails 8.0, MariaDB
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

WORKDIR /amahi

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  ruby ruby-dev ruby-bundler \
  build-essential \
  libmariadb-dev mariadb-client \
  libsqlite3-dev \
  libxml2-dev libxslt-dev \
  zlib1g-dev libffi-dev libssl-dev libreadline-dev libyaml-dev \
  git curl unzip \
  smbclient \
  plocate \
  tzdata \
  && rm -rf /var/lib/apt/lists/*

# Copy Gemfile first for layer caching
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'test' \
  && bundle install --jobs 4 --retry 3

# Copy application
COPY . .

# Create required directories
RUN mkdir -p tmp/cache/tmpfiles tmp/pids log public/assets

# Entrypoint handles DB setup on first run
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0", "-p", "3000"]
